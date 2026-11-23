import SwiftUI
import RealityKit
import ARKit
import Combine
import AVFoundation
import UIKit.UIGestureRecognizerSubclass

/// A RealityKit view that shows the figure either on the shelf (a 3D turntable)
/// or in the room (AR camera).
struct StageView: UIViewRepresentable {
    enum Mode { case shelf, room }

    let mode: Mode
    let look: Look
    let actionRequest: ActionRequest?
    let keepGoing: Bool
    var onPlacedChange: ((Bool) -> Void)? = nil
    var onCameraOff: (() -> Void)? = nil
    var resetViewID: UUID? = nil
    var onTurned: (() -> Void)? = nil
    var turnRequest: TurnRequest? = nil
    var onTouch: (() -> Void)? = nil

    func makeCoordinator() -> StageCoordinator {
        StageCoordinator(mode: mode, initialRequestID: actionRequest?.id)
    }

    func makeUIView(context: Context) -> ARView {
        context.coordinator.makeView()
    }

    func updateUIView(_ view: ARView, context: Context) {
        let c = context.coordinator
        c.onPlacedChange = onPlacedChange
        c.onCameraOff = onCameraOff
        c.onTurned = onTurned
        c.onTouch = onTouch
        c.resetView(id: resetViewID)
        c.turn(turnRequest)
        c.apply(look: look, request: actionRequest, keepGoing: keepGoing)
    }

    static func dismantleUIView(_ view: ARView, coordinator: StageCoordinator) {
        coordinator.tearDown()
    }
}

final class StageCoordinator: NSObject {
    let mode: StageView.Mode
    let rig = FigureRig()
    var onPlacedChange: ((Bool) -> Void)?
    var onCameraOff: (() -> Void)?
    var onTurned: (() -> Void)?
    var onTouch: (() -> Void)?
    private var lastResetID: UUID?
    private var lastTurnID: UUID?
    private static let shelfAngle = simd_quatf(angle: 0.35, axis: [0, 1, 0])

    private var arView: ARView?
    private var updateSubscription: Cancellable?
    private var lastLook: Look?
    private var lastRequestID: UUID?
    private var anchor: AnchorEntity?
    private var placed = false

    init(mode: StageView.Mode, initialRequestID: UUID?) {
        self.mode = mode
        self.lastRequestID = initialRequestID
    }

    func makeView() -> ARView {
        let view: ARView
        switch mode {
        case .shelf:
            view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
            setUpShelf(in: view)
        case .room:
            view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
            setUpRoom(in: view)
        }
        arView = view
        updateSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(event.deltaTime)
        }
        return view
    }

    /// Turn buttons in the room: ease the figure round by the requested angle.
    func turn(_ request: TurnRequest?) {
        guard let request else { return }
        guard lastTurnID != nil else { lastTurnID = request.id; return }   // first update: just remember
        guard request.id != lastTurnID else { return }
        lastTurnID = request.id
        guard mode == .room else { return }
        var t = rig.root.transform
        t.rotation = simd_quatf(angle: request.angle, axis: [0, 1, 0]) * t.rotation
        rig.root.move(to: t, relativeTo: rig.root.parent, duration: 0.4, timingFunction: .easeInOut)
    }

    /// Smoothly turns the shelf figure back to its default angle (room view: no change).
    func resetView(id: UUID?) {
        guard let id else { return }
        guard let last = lastResetID else { lastResetID = id; return }   // first update: just remember
        guard id != last else { return }
        lastResetID = id
        guard mode == .shelf else { return }
        resetZoom()
        var t = rig.turntable.transform
        t.rotation = Self.shelfAngle
        rig.turntable.move(to: t, relativeTo: rig.turntable.parent, duration: 0.4, timingFunction: .easeInOut)
    }

    func apply(look: Look, request: ActionRequest?, keepGoing: Bool) {
        if look != lastLook {
            if mode == .shelf, let last = lastLook, last.animal != look.animal { resetZoom() }
            rig.setLook(look)
            lastLook = look
        }
        if let request, request.id != lastRequestID {
            lastRequestID = request.id
            rig.play(request.action)
        }
        rig.keepGoing = keepGoing
    }

    func tearDown() {
        updateSubscription?.cancel()
        updateSubscription = nil
        if mode == .room {
            arView?.session.pause()
        }
    }

    // Shelf camera: the view can be wide (menu shown) or tall (menu hidden, full screen).
    // The field of view is vertical, so a tall view would cut off long figures at the sides:
    // move the camera back until about half a metre (the shelf and a dinosaur) fits across.
    private static let shelfTarget: SIMD3<Float> = [0, 0.1, -0.04]
    private static let shelfEye: SIMD3<Float> = [0, 0.23, 0.66]
    private var shelfCamera: PerspectiveCamera?
    private var cameraBack: Float = 1

    private func frameShelf(_ dt: Double) {
        guard let camera = shelfCamera, let view = arView, view.bounds.height > 1 else { return }
        let aspect = Float(view.bounds.width / view.bounds.height)
        let want = max(1, 0.72 * 1.45 / max(aspect, 0.2)) * userZoom
        let ease = Float(min(1, dt * 10))
        guard abs(want - cameraBack) > 0.0005 || simd_length(slideTarget - slideOffset) > 0.0002 else { return }
        cameraBack += (want - cameraBack) * ease
        slideOffset += (slideTarget - slideOffset) * ease
        let back = Self.shelfEye - Self.shelfTarget
        let right = simd_normalize(simd_cross([0, 1, 0], back))
        let up = simd_normalize(simd_cross(back, right))
        let target = Self.shelfTarget + right * slideOffset.x + up * slideOffset.y
        camera.look(at: target, from: target + back * cameraBack, relativeTo: nil)
    }

    private func tick(_ dt: Double) {
        if mode == .shelf { frameShelf(dt) }
        rig.update(deltaTime: dt)

        if mode == .room, let anchor {
            let nowPlaced = anchor.isAnchored
            if nowPlaced != placed {
                placed = nowPlaced
                if nowPlaced { faceCamera() }
                let callback = onPlacedChange
                DispatchQueue.main.async { callback?(nowPlaced) }
            }
        }
    }

    // MARK: - Shelf (3D turntable)

    private func setUpShelf(in view: ARView) {
        view.environment.background = .color(UIColor(hex: 0xF3EEE6))

        let world = AnchorEntity(world: .zero)

        let shelf = ModelEntity(
            mesh: .generateCylinder(height: 0.02, radius: 0.2),
            materials: [SimpleMaterial(color: UIColor(hex: 0xD9B98F), roughness: .float(0.85), isMetallic: false)]
        )
        shelf.position = [0, -0.01, -0.07]
        world.addChild(shelf)

        rig.runRadius = 0.09
        rig.turntable.orientation = Self.shelfAngle
        world.addChild(rig.root)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 38
        camera.look(at: Self.shelfTarget, from: Self.shelfEye, relativeTo: nil)
        world.addChild(camera)
        shelfCamera = camera

        let sun = DirectionalLight()
        sun.light.intensity = 2800
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 2, depthBias: 2)
        sun.look(at: [0, 0, 0], from: [0.4, 1.0, 0.7], relativeTo: nil)
        world.addChild(sun)

        view.scene.addAnchor(world)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSpin(_:)))
        pan.maximumNumberOfTouches = 1          // two fingers are for zooming
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handleZoom(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)
        let twice = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        twice.numberOfTapsRequired = 2
        view.addGestureRecognizer(twice)
    }

    // Pinch on the shelf moves the camera closer (up to 2.5x) or a little further (dolly, the
    // figure keeps its size), toward the spot between the fingers. Double-tap, Reset
    // or picking another figure eases it back.
    private var userZoom: Float = 1            // camera distance factor: 0.4 = 2.5x closer
    private var zoomAtStart: Float = 1
    private var slideOffset = SIMD2<Float>(0, 0)   // metres, right/up in the camera's view
    private var slideTarget = SIMD2<Float>(0, 0)

    private var lastPinchPoint: CGPoint = .zero

    /// Pinch zooms toward the point between the fingers; moving both fingers slides the view.
    @objc private func handleZoom(_ gesture: UIPinchGestureRecognizer) {
        guard let view = arView else { return }
        let p = gesture.location(in: view)
        switch gesture.state {
        case .began:
            zoomAtStart = userZoom
            lastPinchPoint = p
        case .changed:
            let h = Float(max(view.bounds.height, 1))
            let metresPerPoint = sceneViewHeight(at: userZoom) / h
            // slide with the fingers
            let d = CGPoint(x: p.x - lastPinchPoint.x, y: p.y - lastPinchPoint.y)
            lastPinchPoint = p
            var target = slideTarget
            target.x -= Float(d.x) * metresPerPoint
            target.y += Float(d.y) * metresPerPoint
            // zoom, keeping the spot under the fingers where it is
            let old = userZoom
            let new = min(1.25, max(0.4, zoomAtStart / Float(max(gesture.scale, 0.05))))
            if gesture.numberOfTouches >= 2 {
                let fx = (Float(p.x) - Float(view.bounds.midX)) * metresPerPoint
                let fy = (Float(view.bounds.midY) - Float(p.y)) * metresPerPoint
                target.x += fx * (1 - new / old)
                target.y += fy * (1 - new / old)
            }
            userZoom = new
            let limit: Float = 0.2 * (1.2 - min(1, userZoom))       // no sliding at full view
            target.x = min(limit, max(-limit, target.x))
            target.y = min(limit, max(-limit, target.y))
            slideTarget = target
            let callback = onTurned
            DispatchQueue.main.async { callback?() }      // Reset lights up, like after turning
        default: break
        }
    }

    /// Height of the scene the camera sees at the figure's distance, for a zoom factor.
    private func sceneViewHeight(at zoom: Float) -> Float {
        guard let view = arView, view.bounds.height > 1 else { return 0.3 }
        let aspect = Float(view.bounds.width / view.bounds.height)
        let back = max(1, 0.72 * 1.45 / max(aspect, 0.2)) * zoom
        return 2 * tan(19 * Float.pi / 180) * simd_length(Self.shelfEye - Self.shelfTarget) * back
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) { resetZoom() }

    private func resetZoom() {
        userZoom = 1
        slideTarget = .zero
    }

    @objc private func handleSpin(_ gesture: UIPanGestureRecognizer) {
        guard let view = arView else { return }
        let dx = Float(gesture.translation(in: view).x)
        gesture.setTranslation(.zero, in: view)
        let turn = simd_quatf(angle: dx * 0.012, axis: [0, 1, 0])
        rig.turntable.stopAllAnimations()
        rig.turntable.orientation = turn * rig.turntable.orientation
        if abs(dx) > 0.5 {
            let callback = onTurned
            DispatchQueue.main.async { callback?() }
        }
    }

    // MARK: - Room (AR)

    private func setUpRoom(in view: ARView) {
        // Always draw the camera picture behind the figure.
        view.environment.background = .cameraFeed()
        view.session.delegate = self
        startRoomSession(in: view)

        // Show Apple's gentle "move your phone" guide until the floor is found.
        let coaching = ARCoachingOverlayView()
        coaching.session = view.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(coaching)

        // Toy size: about 30 cm tall. Pinch to change.
        rig.root.scale = [1.5, 1.5, 1.5]
        rig.runRadius = 0.15

        let floor = AnchorEntity(plane: .horizontal, classification: .any, minimumBounds: [0.2, 0.2])
        floor.addChild(rig.root)
        view.scene.addAnchor(floor)
        anchor = floor

        // Pinch (RealityKit) and our own two-finger twist work at the same time; the twist only
        // turns the figure about its upright axis.
        for g in view.installGestures([.scale, .translation], for: rig.root) { g.delegate = self }
        let twist = UIRotationGestureRecognizer(target: self, action: #selector(handleTwist(_:)))
        twist.delegate = self
        view.addGestureRecognizer(twist)
        let watcher = TouchWatcher { [weak self] in self?.onTouch?() }
        watcher.delegate = self
        view.addGestureRecognizer(watcher)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
    }

    /// Starts the camera once access is known. With the camera off the view says so
    /// calmly (no popup); iOS asks for access the first time only.
    private func startRoomSession(in view: ARView, fresh: Bool = true) {
        let run = { [weak view] in
            guard let view else { return }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            config.environmentTexturing = .automatic
            view.session.run(config, options: fresh ? [.resetTracking, .removeExistingAnchors] : [])
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async(execute: run)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { run() } else { self?.reportCameraOff() }
                }
            }
        default:
            reportCameraOff()
        }
    }

    private func reportCameraOff() {
        let callback = onCameraOff
        DispatchQueue.main.async { callback?() }
    }

    @objc private func handleTwist(_ g: UIRotationGestureRecognizer) {
        guard g.state == .changed || g.state == .ended else { return }
        rig.root.stopAllAnimations()
        let turn = simd_quatf(angle: -Float(g.rotation), axis: [0, 1, 0])
        rig.root.orientation = turn * rig.root.orientation
        g.rotation = 0
    }

    /// Tap the floor to move the figure there.
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = arView else { return }
        let point = gesture.location(in: view)
        if view.entity(at: point) != nil { return } // tapped the figure itself
        guard let hit = view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first else {
            return
        }
        let spot = AnchorEntity(world: hit.worldTransform)
        view.scene.addAnchor(spot)
        rig.root.removeFromParent()
        rig.root.position = .zero
        spot.addChild(rig.root)
        if let old = anchor { view.scene.removeAnchor(old) }
        anchor = spot
        faceCamera()
    }

    private func faceCamera() {
        guard let view = arView else { return }
        let cam = view.cameraTransform.translation
        let here = rig.root.position(relativeTo: nil)
        let dir = cam - here
        let yaw = atan2(dir.x, dir.z)
        rig.root.setOrientation(simd_quatf(angle: yaw, axis: [0, 1, 0]), relativeTo: nil)
    }
}

extension StageCoordinator: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        if let arError = error as? ARError, arError.code == .cameraUnauthorized {
            reportCameraOff()
        } else {
            print("Figure Shelf: AR session failed: \(error)")
        }
    }

    /// Back from the background (or an interruption): start the camera again.
    func sessionInterruptionEnded(_ session: ARSession) {
        guard let view = arView else { return }
        startRoomSession(in: view, fresh: false)
    }
}

extension StageCoordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

/// Notices every touch on the room view (to keep the menu awake) without taking any.
final class TouchWatcher: UIGestureRecognizer {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) {
        self.action = action
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        action()
        state = .failed
    }
}
