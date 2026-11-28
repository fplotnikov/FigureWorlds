import SwiftUI
import RealityKit
import Combine
import UIKit

/// The buttons around the world talk to the 3D view through this.
@MainActor
final class WorldControls: ObservableObject {
    @Published var canUndoTidy = false
    /// The place on the map he is in now.
    @Published private(set) var scene: SceneKind = SceneKind.saved {
        didSet { SoundBoard.shared.danceTheme = scene.rawValue }
    }
    /// Goes up by one each time a wardrobe is opened: the screen shows the outfit chooser.
    @Published var wardrobeRequest = 0
    /// True while the animal chooser covers the screen (sparkles wait until it closes).
    var chooserOpen = false
    weak var handler: WorldCoordinator?
    /// Resets the action buttons ("Again") when the animal walks off in the middle of an action.
    var stopActing: (@MainActor () -> Void)?

    init() {
        SoundBoard.shared.danceTheme = scene.rawValue
    }

    func tidyUp() { handler?.tidyUp() }
    func undoTidy() { handler?.undoTidy() }
    func recenter() { handler?.recenter() }
    func openWardrobe() { wardrobeRequest += 1 }

    func go(to place: SceneKind) {
        guard place != scene else { return }
        scene = place
        UserDefaults.standard.set(place.rawValue, forKey: SceneKind.storageKey)
        handler?.switchScene(place)
    }
}

/// The 3D village (RealityKit, no camera: the world is on the screen, not in the room).
struct WorldView: UIViewRepresentable {
    let look: Look
    let friendLook: Look
    let actionRequest: ActionRequest?
    let keepGoing: Bool
    let controls: WorldControls

    func makeCoordinator() -> WorldCoordinator {
        WorldCoordinator(look: look, friendLook: friendLook, initialRequestID: actionRequest?.id, controls: controls,
                         scene: controls.scene)
    }

    func makeUIView(context: Context) -> ARView {
        context.coordinator.makeView()
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.apply(look: look, friendLook: friendLook, request: actionRequest, keepGoing: keepGoing)
    }

    static func dismantleUIView(_ view: ARView, coordinator: WorldCoordinator) {
        coordinator.tearDown()
    }
}

@MainActor
final class WorldCoordinator: NSObject {
    private var village: Village
    private var world: AnchorEntity?
    private let me: Walker
    private let friend: Walker
    private let camera = PerspectiveCamera()
    private weak var controls: WorldControls?
    private var arView: ARView?
    private var updateSubscription: Cancellable?
    private var observers: [NSObjectProtocol] = []

    private var lastLook: Look
    private var lastFriendLook: Look
    private var lastRequestID: UUID?

    // Camera: follows behind the animal; one finger turns it, two fingers zoom.
    private var camYaw: Float = .pi
    private var camPitch: Float = 0.42
    private var camDistance: Float = 6.5
    private var shownPitch: Float = 0.42
    private var shownDistance: Float = 6.5
    private var camTarget: SIMD3<Float> = .zero
    private var sinceCameraTouch: Float = 100
    private var recentering: Float = 0
    /// How much the camera is pulled in so it stays out of a house the animal is not in.
    private var camSqueeze: Float = 1
    /// Camera distance after pulling in in front of trees and lamp posts (eased, never snaps).
    private var viewLength: Float = 100
    /// Extra tilt so the camera looks down over a thing standing right behind the animal.
    private var pitchLift: Float = 0
    /// The walk direction the camera glides toward, smoothed; a sharp turn pauses the glide.
    private var smoothWalkYaw: Float = .pi
    private var sharpTurnHold: Float = 0
    private let sun = DirectionalLight()
    private let fill = DirectionalLight()

    // Sparkles when an outfit changes
    private struct Spark {
        let entity: ModelEntity
        var velocity: SIMD3<Float>
        var life: Float
    }
    private var sparks: [Spark] = []
    private lazy var sparkMesh = MeshResource.generateSphere(radius: 0.09)
    private var sparkleMe = false
    private var sparkleFriend = false
    private var fadedWalls = Set<ObjectIdentifier>()
    /// Resting heights of the big buttons' caps (they dip when pressed).
    private var capBase: [ObjectIdentifier: Float] = [:]

    // The friend
    private var friendIdle: Float = 0
    private var friendNextWander: Float = 4
    private var friendCooldown: Float = 0
    private var friendCopy: (action: FigureAction, delay: Float)?

    // Toys
    private struct Move {
        let prop: Prop
        let from: Transform
        let to: Transform
    }
    private var lastPositions: [String: SIMD3<Float>] = [:]
    private var velocities: [String: SIMD3<Float>] = [:]
    private var moves: [Move] = []
    private var moveTime: Float = 0
    private var undoSnapshot: [String: Transform]?

    private var clock: Float = 0
    private var saveTimer: Float = 0
    private var delayed: [(time: Float, run: @MainActor () -> Void)] = []

    private enum Tap {
        case ground(SIMD2<Float>, Int)
        case prop(Prop)
        case use(Interactive)
        case me
        case friend
    }

    init(look: Look, friendLook: Look, initialRequestID: UUID?, controls: WorldControls, scene: SceneKind) {
        let v = Village(scene: scene)
        village = v
        me = Walker(look: look, at: v.start, yaw: .pi)
        friend = Walker(look: friendLook, at: v.start + SIMD2<Float>(1.4, 0.7), yaw: .pi)
        lastLook = look
        lastFriendLook = friendLook
        v.letSwimmerIn(look.animal.isSwimmer)
        lastRequestID = initialRequestID
        self.controls = controls
        super.init()
        friend.walkSpeed = 2.4
        controls.handler = self
        me.onStopActing = { [weak controls] in controls?.stopActing?() }
    }

    // MARK: - Setup

    func makeView() -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(hex: village.scene.sky))

        let world = AnchorEntity(world: .zero)
        self.world = world
        world.addChild(village.root)
        world.addChild(me.entity)
        world.addChild(friend.entity)

        camera.camera.fieldOfViewInDegrees = 55
        camera.camera.near = 0.3   // a pole or bulb right at the lens is cut away, not a big blob
        world.addChild(camera)

        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 22, depthBias: 3)
        sun.look(at: .zero, from: [7, 14, 9], relativeTo: nil)
        world.addChild(sun)

        fill.look(at: .zero, from: [-8, 6, -10], relativeTo: nil)
        world.addChild(fill)
        setLights()

        view.scene.addAnchor(world)
        arView = view

        restore()
        camTarget = me.entity.position(relativeTo: nil) + SIMD3<Float>(0, 0.75, 0)
        updateCamera(1, inside: false)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)

        updateSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = event.deltaTime
            MainActor.assumeIsolated { self?.tick(dt) }
        }
        let resign = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
        observers.append(resign)
        return view
    }

    /// White snow needs a softer sun and less fill light, or the shadows wash out.
    private func setLights() {
        switch village.scene {
        case .snow:
            sun.light.intensity = 2100
            fill.light.intensity = 350
            fill.light.color = .white
        case .carnival:
            // Evening: a soft moonlit fill; the lamps, bulbs and signs do the rest.
            sun.light.intensity = 1500
            fill.light.intensity = 700
            fill.light.color = UIColor(hex: 0xA9B8FF)
        default:
            sun.light.intensity = 3200
            fill.light.intensity = 900
            fill.light.color = .white
        }
    }

    func tearDown() {
        save()
        updateSubscription?.cancel()
        updateSubscription = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
    }

    func apply(look: Look, friendLook: Look, request: ActionRequest?, keepGoing: Bool) {
        if look != lastLook {
            village.letSwimmerIn(look.animal.isSwimmer)   // sea figures may swim into the pond
            me.rig.setLook(look)
            lastLook = look
            sparkleMe = true
        }
        if friendLook != lastFriendLook {
            friend.rig.setLook(friendLook)
            lastFriendLook = friendLook
            sparkleFriend = true
        }
        me.rig.keepGoing = keepGoing
        if let request, request.id != lastRequestID {
            lastRequestID = request.id
            if let action = request.action {
                me.playAction(action)
                maybeFriendCopies(action)
            } else {
                me.rig.play(nil)
            }
        }
    }

    // MARK: - Every frame

    private func tick(_ seconds: Double) {
        let dt = Float(min(seconds, 0.05))
        clock += dt
        sinceCameraTouch += dt
        runDelayed()

        village.updateAmbient(dt, near: camTarget)
        updateFriend(dt)
        let together = friend.level == me.level && !friend.isBusy && !friend.isRiding
        me.update(dt, village: village, avoid: together && !me.isRiding ? friend.ground : nil)
        friend.update(dt, village: village, avoid: friend.level == me.level ? me.ground : nil)
        updateProps(dt)
        push(by: me)
        push(by: friend)
        updateThings(dt)
        updateMoves(dt)
        if !(controls?.chooserOpen ?? false) {
            // The new look shows once the chooser is closed: sparkles and a happy hop.
            if sparkleMe {
                sparkleMe = false
                sparkle(around: me)
                if !me.isBusy && !me.isRiding { me.playAction(.jump) }
            }
            if sparkleFriend {
                sparkleFriend = false
                sparkle(around: friend)
            }
        }
        updateSparks(dt)
        let inside = updateRoofs()
        updateCamera(dt, inside: inside)
        updateWallFade()

        saveTimer += dt
        if saveTimer > 4 {
            saveTimer = 0
            save()
        }
    }

    private func after(_ seconds: Float, _ run: @escaping @MainActor () -> Void) {
        delayed.append((time: clock + seconds, run: run))
    }

    private func runDelayed() {
        guard !delayed.isEmpty else { return }
        let due = delayed.filter { $0.time <= clock }
        guard !due.isEmpty else { return }
        delayed.removeAll { $0.time <= clock }
        for item in due { item.run() }
    }

    // MARK: - Camera

    private func updateCamera(_ dt: Float, inside: Bool) {
        let target = me.entity.position(relativeTo: nil) + SIMD3<Float>(0, 0.75, 0)
        camTarget += (target - camTarget) * min(1, dt * 6)
        // A sharp change of walking direction (round the pond, a new tap) pauses the glide for a bit,
        // so the camera doesn't swing to and fro.
        if me.isWalking {
            if abs(angleDiff(me.yaw, smoothWalkYaw)) > 1.0 { sharpTurnHold = 1.5 }
            smoothWalkYaw = turnToward(smoothWalkYaw, me.yaw, dt * 1.5)
        } else {
            smoothWalkYaw = me.yaw
        }
        sharpTurnHold = max(0, sharpTurnHold - dt)
        let scripted = me.isBusy || me.isRiding
        if recentering > 0 {
            recentering -= dt
            camYaw = turnToward(camYaw, me.yaw, dt * 5)
        } else if me.isWalking && !scripted && sinceCameraTouch > 5 && sharpTurnHold <= 0 {
            // Glide back behind the animal while it walks, unless he just turned the camera.
            camYaw = turnToward(camYaw, smoothWalkYaw, dt * 0.55)
        }
        // Inside a house the roof hides and the camera looks down over the walls.
        // The big house has more to see: look from higher up so whole rooms fit.
        let inBig = village.bigHouse?.contains(me.ground) ?? false
        var wantPitch = inBig ? max(camPitch, 1.1) : (inside ? max(camPitch, 0.95) : camPitch)
        if village.underCanopy(me.ground, level: me.level) { wantPitch = min(wantPitch, 0.2) }   // look in under it
        let wantDistance = inBig ? min(max(camDistance, 9), 12) : (inside ? min(camDistance, 4.6) : camDistance)
        shownPitch = ease(shownPitch, wantPitch, dt * 4)
        shownDistance = ease(shownDistance, wantDistance, dt * 4)
        // A lamp post or tree closer than the nearest the camera may come: look down over it instead.
        var wantLift: Float = 0
        let near: Float = 2.8
        func sight(_ p: Float) -> SIMD3<Float> { SIMD3<Float>(-sin(camYaw) * cos(p), sin(p), -cos(camYaw) * cos(p)) }
        if village.viewBlocked(from: camTarget, toward: sight(shownPitch), length: near, level: me.level) != nil {
            var p = shownPitch
            while p < 1.3 {
                p = min(1.3, p + 0.08)
                if village.viewBlocked(from: camTarget, toward: sight(p), length: near, level: me.level) == nil { break }
            }
            wantLift = p - shownPitch
        }
        pitchLift = ease(pitchLift, wantLift, dt * (wantLift > pitchLift ? 4 : 1.2))
        let pitch = shownPitch + pitchLift
        let fullAcross = cos(pitch) * shownDistance
        let height = sin(pitch) * shownDistance
        // Pull the camera in when it would end up inside a house the animal is not in
        // (or under the carousel's roof when the animal is outside it).
        let underCanopy = village.underCanopy(me.ground, level: me.level)
        let home = village.houseIndex(containing: me.ground)
        var squeeze: Float = 1
        for _ in 0..<10 {
            let a = fullAcross * squeeze
            let c = camTarget + SIMD3<Float>(-sin(camYaw) * a, height, -cos(camYaw) * a)
            // Roofs stick out past the walls, hence the wide margin. The fountain blocks the view too.
            let inFountain = simd_length(flat(c)) < 2.0 && c.y < 2.2
            let blocked = inFountain || village.houses.indices.contains { i in
                i != home && c.y < village.houses[i].top && village.houses[i].contains(flat(c), margin: 1.2)
            } || (!underCanopy && village.underCanopy(flat(c), level: me.level))
            if !blocked { break }
            squeeze *= 0.82
        }
        camSqueeze = ease(camSqueeze, squeeze, dt * (squeeze < camSqueeze ? 10 : 3))
        let across = fullAcross * camSqueeze
        var offset = SIMD3<Float>(-sin(camYaw) * across, height, -cos(camYaw) * across)

        // Trees and lamp posts in the way: come in to just before them.
        let full = simd_length(offset)
        var want = full
        if full > 0.01, let hit = village.viewBlocked(from: camTarget, toward: offset / full, length: full, level: me.level) {
            want = min(full, max(2.5, hit - 0.3))
        }
        // Come in along the same line before the camera would pass the fence.
        let edge = Village.walkRadius - 0.5
        if full > 0.01 {
            let o = SIMD2<Float>(camTarget.x, camTarget.z)
            let d = SIMD2<Float>(offset.x, offset.z) / full
            let b = simd_dot(o, d)
            let c = simd_length_squared(o) - edge * edge
            let disc = b * b - c
            if disc >= 0 {
                let reach = -b + sqrt(disc)   // how far along the line until the fence circle
                if reach < full { want = min(want, max(2.5, reach)) }
            }
        }
        viewLength = min(viewLength, full)
        viewLength = ease(viewLength, want, dt * (want < viewLength ? 6 : 1.5))
        offset *= viewLength / max(full, 0.01)

        // Never outside the fence, even while easing in.
        var from = camTarget + offset
        let out = simd_length(flat(from))
        if out > edge {
            from.x *= edge / out
            from.z *= edge / out
        }
        camera.look(at: camTarget, from: from, relativeTo: nil)
    }

    func recenter() {
        recentering = 0.8
        sinceCameraTouch = 100
        SoundBoard.shared.pop()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = arView else { return }
        let t = gesture.translation(in: view)
        gesture.setTranslation(.zero, in: view)
        camYaw -= Float(t.x) * 0.008
        camPitch = min(1.25, max(0.12, camPitch + Float(t.y) * 0.005))
        sinceCameraTouch = 0
        recentering = 0
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        let scale = max(0.2, Float(gesture.scale))
        camDistance = min(12, max(3, camDistance / scale))
        gesture.scale = 1
        sinceCameraTouch = 0
    }

    /// True while the animal is downstairs in the big house: the upstairs is hidden so you can see in.
    private var upstairsHidden: Bool {
        me.level == 0 && (village.bigHouse?.contains(me.ground) ?? false)
    }

    private func updateRoofs() -> Bool {
        let inside = village.houseIndex(containing: me.ground)
        for (i, house) in village.houses.enumerated() {
            let show = i != inside
            if house.roof.isEnabled != show { house.roof.isEnabled = show }
        }
        let hide = upstairsHidden
        if let upper = village.bigHouse?.upper, upper.isEnabled == hide {
            upper.isEnabled = !hide
        }
        for p in village.props where p.entity.parent === village.root {
            let show = !(hide && village.level(at: p.entity.position(relativeTo: nil)) == 1)
            if p.entity.isEnabled != show { p.entity.isEnabled = show }
        }
        let showFriend = !(hide && friend.level == 1)
        if friend.entity.isEnabled != showFriend { friend.entity.isEnabled = showFriend }
        return inside != nil
    }

    // MARK: - Taps

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = arView else { return }
        let point = gesture.location(in: view)
        let hits = view.hitTest(point, query: .all, mask: .all).sorted { $0.distance < $1.distance }
        let hide = upstairsHidden
        for hit in hits {
            // While downstairs, the hidden upstairs can't be tapped.
            if hide && hit.position.y > 2.95 && !isStairs(hit.entity) && (village.bigHouse?.contains(flat(hit.position), margin: 0.3) ?? false) {
                continue
            }
            perform(classify(hit.entity, at: hit.position))
            return
        }
        // Nothing with a shape under the finger: walk to that spot on the ground.
        if let ray = view.ray(through: point), ray.direction.y < -0.001 {
            let t = -ray.origin.y / ray.direction.y
            perform(.ground(flat(ray.origin + ray.direction * t), 0))
        }
    }

    private func isStairs(_ e: Entity) -> Bool {
        if case .stairs = village.tapTarget(for: e) { return true }
        return false
    }

    private func classify(_ entity: Entity, at position: SIMD3<Float>) -> Tap {
        var current: Entity? = entity
        while let e = current {
            if e === me.rig.root { return .me }
            if e === friend.rig.root { return .friend }
            if let target = village.tapTarget(for: e) {
                switch target {
                case .ground: return .ground(flat(position), 0)
                case .floor(let level): return .ground(flat(position), level)
                case .stairs:
                    // Tap the stairs to go up (or, from upstairs, down).
                    guard let s = village.stairs else { return .ground(flat(position), 0) }
                    return me.level == 0 ? .ground(s.top, 1) : .ground(s.bottom, 0)
                case .prop(let prop):
                    // A ball lying in the ball pit: tapping it means "jump in".
                    if let pit = village.pit(holding: prop) { return .use(pit) }
                    return .prop(prop)
                case .use(let thing): return .use(thing)
                }
            }
            current = e.parent
        }
        // The igloo tapped from outside: from the front, walk in through the tunnel; from behind
        // or the side, go round to the doorway first.
        let p = flat(position)
        if let house = village.houses.first(where: { $0.entrance != nil && $0.contains(p, margin: 0.5) }),
           let door = house.entrance, !house.contains(me.ground) {
            let fromFront = me.ground.x > house.center.x + house.halfX && abs(me.ground.y - house.center.y) < 1.2
            return .ground(fromFront ? house.center + SIMD2<Float>(0.5, 0) : door, 0)
        }
        // A wall, a tree, a fence: walk toward it (upstairs if it is up there).
        return .ground(p, village.level(at: position))
    }

    private func perform(_ tap: Tap) {
        if me.isBusy { return }
        if me.isRiding {
            getOff { [weak self] in self?.perform(tap) }
            return
        }
        switch tap {
        case .me:
            if let held = me.carrying {
                toss(held)
            } else {
                me.playAction(.jump)
                maybeFriendCopies(.jump)
            }
        case .friend:
            friend.stop()
            friend.face(yawFacing(from: friend.ground, to: me.ground))
            friend.playAction(.wave)
            friendIdle = -3
            me.face(yawFacing(from: me.ground, to: friend.ground))
            me.playAction(.wave)
        case .ground(let p, let level):
            me.ignoreProp = nil
            SoundBoard.shared.ui(.step, volume: 0.25)
            travel(me, to: village.clampToWorld(p), level: level)
        case .prop(let prop):
            if prop === me.carrying { toss(prop) } else { fetch(prop) }
        case .use(let thing):
            if let held = me.carrying { drop(held, soft: true) }
            go(to: thing)
        }
    }

    // MARK: - Toys: kick, carry, toss

    private func velocity(of prop: Prop) -> SIMD3<Float> {
        velocities[prop.id] ?? .zero
    }

    private func fetch(_ prop: Prop, again: Bool = true) {
        clearUndo()
        me.ignoreProp = prop
        let reach = Walker.radius + prop.radius + 0.05
        let at = prop.entity.position(relativeTo: nil)
        let level = village.level(at: at)
        if level != me.level {
            // On the other floor: take the stairs first.
            guard again else { return }
            travel(me, to: flat(at), level: level) { [weak self] in self?.fetch(prop, again: false) }
            return
        }
        let via = Array(village.findPath(from: me.ground, to: flat(at), level: me.level).dropLast())
        me.walk(follow: { [weak self] in
            guard let self else { return .zero }
            let p = flat(prop.entity.position(relativeTo: nil))
            let d = p - self.me.ground
            let len = simd_length(d)
            if len < 0.001 { return self.me.ground }
            return p - d / len * reach
        }, via: via, then: { [weak self] in
            guard let self else { return }
            self.me.ignoreProp = nil
            let p = flat(prop.entity.position(relativeTo: nil))
            guard simd_distance(p, self.me.ground) < reach + 0.6 else { return }
            self.me.face(yawFacing(from: self.me.ground, to: p))
            switch prop.kind {
            case .kick:
                self.kick(prop)
            case .carry:
                if let held = self.me.carrying { self.drop(held, soft: true) }
                self.pickUp(prop)
            }
        })
    }

    private func kick(_ prop: Prop) {
        var d = flat(prop.entity.position(relativeTo: nil)) - me.ground
        if simd_length(d) < 0.001 { d = SIMD2<Float>(sin(me.yaw), cos(me.yaw)) }
        d = simd_normalize(d)
        let want = SIMD3<Float>(d.x * 4.2, 1.8, d.y * 4.2)
        prop.entity.applyLinearImpulse((want - velocity(of: prop)) * prop.mass, relativeTo: nil)
        WorldSounds.shared.play(.thud)
    }

    private func pickUp(_ prop: Prop) {
        prop.entity.physicsBody?.mode = .kinematic
        prop.entity.setParent(me.carryAnchor, preservingWorldTransform: false)
        prop.entity.transform = Transform(scale: .one, rotation: rotY(0), translation: [0, prop.lift, 0])
        me.carrying = prop
        SoundBoard.shared.pop()
    }

    /// Puts down (soft) or throws what the animal carries.
    private func drop(_ prop: Prop, soft: Bool) {
        guard me.carrying === prop else { return }
        me.carrying = nil
        let forward = SIMD3<Float>(sin(me.yaw), 0, cos(me.yaw))
        prop.entity.setParent(village.root, preservingWorldTransform: true)
        var p = me.entity.position(relativeTo: nil) + forward * (soft ? 0.8 : 0.5)
        p.y = me.floorY + (soft ? prop.lift + 0.3 : 1.1 + prop.lift)
        prop.entity.setPosition(p, relativeTo: nil)
        prop.entity.physicsBody?.mode = .dynamic
        lastPositions[prop.id] = p
        velocities[prop.id] = .zero
        let push = soft ? forward * 0.6 + SIMD3<Float>(0, 0.3, 0) : forward * 3.3 + SIMD3<Float>(0, 2.4, 0)
        prop.entity.applyLinearImpulse(push * prop.mass, relativeTo: nil)
        WorldSounds.shared.play(soft ? .thud : .whoosh)
    }

    private func toss(_ prop: Prop) {
        clearUndo()
        drop(prop, soft: false)
    }

    private func updateProps(_ dt: Float) {
        guard dt > 0 else { return }
        for p in village.props where p !== me.carrying {
            let pos = p.entity.position(relativeTo: nil)
            let last = lastPositions[p.id] ?? pos
            let v = (pos - last) / dt
            velocities[p.id] = v
            lastPositions[p.id] = pos
            if !moves.isEmpty { continue }
            if pos.y < -3 || simd_length(flat(pos)) > 19.5 {
                // Somehow left the village: it comes back home.
                p.entity.transform = p.home
                p.entity.applyLinearImpulse(-v * p.mass, relativeTo: nil)
                lastPositions[p.id] = p.home.translation
                continue
            }
            let size = p.entity.scale.x
            if p.grows && p.kind == .kick && pos.y < p.radius * size + 0.08 {
                // A snowball rolling on the snow gets bigger.
                let speed = simd_length(SIMD2<Float>(v.x, v.z))
                if speed > 0.2 && size < 2.4 {
                    let s = min(2.4, size + speed * dt * 0.09)
                    p.entity.scale = SIMD3<Float>(repeating: s)
                }
            }
            if p.kind == .kick && pos.y < p.radius * size + 0.06 {
                // Balls slow down gently on the grass instead of rolling forever.
                let slow = SIMD3<Float>(v.x, 0, v.z) * min(1, dt * 0.9)
                if simd_length(slow) > 0.0001 {
                    p.entity.applyLinearImpulse(-slow * p.mass, relativeTo: nil)
                }
            }
        }
    }

    /// Walking into a toy pushes it along.
    private func push(by walker: Walker) {
        let v = walker.velocity
        guard simd_length(v) > 0.05, moves.isEmpty else { return }
        let here = walker.ground
        for p in village.props where p !== walker.carrying && p !== walker.ignoreProp && p.entity.isEnabled {
            let pos = p.entity.position(relativeTo: nil)
            guard pos.y < walker.floorY + 1.0, pos.y > walker.floorY - 0.4 else { continue }
            let d = flat(pos) - here
            let dist = simd_length(d)
            let reach = Walker.radius + p.radius * p.entity.scale.x
            guard dist < reach, dist > 0.0001 else { continue }
            let n = d / dist
            let along = simd_dot(v, n)
            guard along > 0 else { continue }
            let pv = velocity(of: p)
            let current = simd_dot(SIMD2<Float>(pv.x, pv.z), n)
            let want = along * 1.15 + 0.25
            if current < want {
                p.entity.applyLinearImpulse(SIMD3<Float>(n.x, 0.04, n.y) * ((want - current) * p.mass), relativeTo: nil)
            }
        }
    }

    // MARK: - Tidy up (and undo)

    func tidyUp() {
        guard moves.isEmpty else { return }
        releaseCraneLoad()
        if let held = me.carrying { drop(held, soft: true) }
        var snapshot: [String: Transform] = [:]
        var list: [Move] = []
        for p in village.props {
            let now = p.entity.transform
            let moved = simd_distance(now.translation, p.home.translation) > 0.05
                || abs(simd_dot(now.rotation.vector, p.home.rotation.vector)) < 0.995
            if moved {
                snapshot[p.id] = now
                list.append(Move(prop: p, from: now, to: p.home))
            }
        }
        SoundBoard.shared.pop()
        guard !list.isEmpty else { return }
        undoSnapshot = snapshot
        controls?.canUndoTidy = true
        start(list)
    }

    func undoTidy() {
        guard moves.isEmpty, let snapshot = undoSnapshot else { return }
        releaseCraneLoad()
        clearUndo()
        if let held = me.carrying { drop(held, soft: true) }
        var list: [Move] = []
        for p in village.props {
            if let t = snapshot[p.id] { list.append(Move(prop: p, from: p.entity.transform, to: t)) }
        }
        start(list)
    }

    private func clearUndo() {
        undoSnapshot = nil
        if controls?.canUndoTidy == true { controls?.canUndoTidy = false }
    }

    private func start(_ list: [Move]) {
        for m in list { m.prop.entity.physicsBody?.mode = .kinematic }
        moves = list
        moveTime = 0
        WorldSounds.shared.play(.whoosh)
    }

    private func updateMoves(_ dt: Float) {
        guard !moves.isEmpty else { return }
        moveTime += dt
        let duration: Float = 1.3
        let u = smoothStep(moveTime / duration)
        for m in moves {
            var t = Transform()
            t.translation = m.from.translation + (m.to.translation - m.from.translation) * u
            t.translation.y += sin(.pi * u) * 0.8   // float up and over things
            t.rotation = simd_slerp(m.from.rotation, m.to.rotation, u)
            m.prop.entity.transform = t
        }
        if moveTime >= duration {
            for m in moves {
                m.prop.entity.transform = m.to
                m.prop.entity.physicsBody?.mode = .dynamic
                lastPositions[m.prop.id] = m.to.translation
                velocities[m.prop.id] = .zero
            }
            moves = []
            save()
        }
    }

    // MARK: - Using things

    private func go(to thing: Interactive) {
        if thing.fromAfar {
            // Ducks and frogs on the water: look at them and they react.
            if let e = thing.parts["duck"] ?? thing.parts["frog"] {
                me.face(yawFacing(from: me.ground, to: flat(e.position(relativeTo: nil))))
            }
            use(thing)
            return
        }
        let spot = village.clampToWorld(thing.spot(from: me.ground))
        me.ignoreProp = nil
        travel(me, to: spot, level: thing.level) { [weak self] in
            guard let self else { return }
            guard self.me.level == thing.level, simd_distance(self.me.ground, spot) < 1.3 else { return }
            thing.lastSpot = spot
            self.me.face(yawFacing(from: spot, to: thing.center))
            self.use(thing)
        }
    }

    private func use(_ thing: Interactive) {
        switch thing.kind {
        case .door, .lamp, .streetLamp, .mailbox:
            setToggle(thing, !thing.isOn)
            SoundBoard.shared.ui(.latch, volume: 0.5)
        case .bell:
            thing.time = 0
            WorldSounds.shared.play(.ding)
        case .fountain:
            thing.time = 0
            WorldSounds.shared.play(.splash)
        case .toyBox:
            setToggle(thing, !thing.isOn)
            SoundBoard.shared.ui(.plop, volume: 0.6)
            if thing.isOn {
                after(0.35) { [weak self] in self?.popToys(from: thing) }
            }
        case .bench, .swing, .merry:
            getOn(thing)
        case .slide:
            slideDown(thing)
        case .bed:
            bounce(on: thing)
        case .tv:
            setToggle(thing, !thing.isOn)
            WorldSounds.shared.play(.click)
            if thing.isOn { friendJoins(.dance, near: thing) }
        case .fridge:
            setToggle(thing, !thing.isOn)
            WorldSounds.shared.play(.click)
        case .stove:
            thing.time = 0
            WorldSounds.shared.play(.click)
            after(0.3) { WorldSounds.shared.play(.whoosh, volume: 0.35) }
        case .sink:
            thing.time = 0
            WorldSounds.shared.play(.splash, volume: 0.45)
        case .toilet:
            thing.time = 0
            WorldSounds.shared.play(.whoosh)
            after(0.5) { WorldSounds.shared.play(.splash, volume: 0.5) }
        case .bathtub, .rocker:
            getOn(thing)
        case .wardrobe:
            thing.isOn = true
            thing.time = 0
            SoundBoard.shared.ui(.drape, volume: 0.5)
            after(0.5) { [weak self] in self?.controls?.openWardrobe() }
        case .ballPit:
            jumpIn(thing)
        case .stones:
            crossStones(thing)
        case .boat:
            getOn(thing)
        case .duck:
            thing.time = 0
            WorldSounds.shared.play(.quack)
        case .frog:
            frogJumps(thing)
        case .campfire:
            setToggle(thing, !thing.isOn)
            WorldSounds.shared.play(thing.isOn ? .whoosh : .click, volume: 0.4)
        case .sled:
            sledDown(thing)
        case .ice:
            skate(on: thing)
        case .conveyor, .bigButton:
            thing.time = 0
            setToggle(thing, !thing.isOn)
            WorldSounds.shared.play(.click)
        case .crane:
            guard !thing.isOn else { return }
            thing.isOn = true
            thing.time = 0
            thing.value = 0
            WorldSounds.shared.play(.beep, volume: 0.5)
        case .marbleRun:
            guard !thing.isOn else { return }
            thing.isOn = true
            thing.time = 0
            thing.value = 0
            WorldSounds.shared.play(.click)
        case .robot:
            thing.value = Float((Int(thing.value) + 1) % 3)
            thing.time = 0
            WorldSounds.shared.play(.beep)
            if Int(thing.value) == 1 { me.playAction(.wave) }
        case .gears:
            thing.time = 0
            WorldSounds.shared.play(.click)
        case .ferris:
            getOn(thing)
        case .lightButton:
            thing.time = 0
            WorldSounds.shared.play(.click)
            if Int(thing.numbers.first ?? 0) == 2 {
                fireworks()
            } else {
                setToggle(thing, !thing.isOn)
            }
        case .popcorn:
            thing.time = 0
            WorldSounds.shared.play(.boing, volume: 0.35)
            after(0.25) { WorldSounds.shared.play(.click, volume: 0.3) }
            after(0.5) { WorldSounds.shared.play(.click, volume: 0.3) }
        case .snowman:
            thing.value = Float((Int(thing.value) + 1) % 4)
            thing.time = 0
            for i in 0..<4 { thing.parts["hat\(i)"]?.isEnabled = i == Int(thing.value) }
            sparkle(at: (thing.parts["hat0"]?.parent?.position(relativeTo: nil) ?? .zero) + SIMD3<Float>(0, 2.1, 0))
            SoundBoard.shared.pop()
        }
    }

    private func setToggle(_ thing: Interactive, _ on: Bool, instant: Bool = false) {
        thing.isOn = on
        switch thing.kind {
        case .door:
            if let i = thing.obstacle { village.setObstacle(i, enabled: !on) }
            if instant { thing.value = on ? 1.7 : 0 }
        case .mailbox:
            if instant { thing.value = on ? 0 : -1.5 }
        case .toyBox:
            if instant { thing.value = on ? -1.9 : 0 }
        case .fridge:
            if instant { thing.value = on ? -1.8 : 0 }
        case .campfire:
            thing.parts["flames"]?.isEnabled = on
            thing.light?.isEnabled = on
        case .conveyor:
            if let lamp = thing.parts["lamp"] as? ModelEntity {
                lamp.model?.materials = [UnlitMaterial(color: UIColor(hex: on ? 0x7DFF6A : 0x5A6170), applyPostProcessToneMap: false)]
            }
        case .bigButton:
            if let bulb = thing.parts["bulb"] as? ModelEntity {
                let hex = UInt32(thing.numbers.first ?? 0xFFFFFF)
                bulb.model?.materials = on ? [UnlitMaterial(color: UIColor(hex: hex), applyPostProcessToneMap: false)]
                    : [SimpleMaterial(color: UIColor(hex: 0xF2F2F2), roughness: .float(0.5), isMetallic: false)]
            }
            thing.light?.isEnabled = on
        case .lightButton:
            switch Int(thing.numbers.first ?? 0) {
            case 0:
                if !on { paintBulbs(thing, offset: nil) }
            case 1:
                let material: RealityKit.Material = on
                    ? UnlitMaterial(color: UIColor(hex: 0xFFD45C), applyPostProcessToneMap: false)
                    : SimpleMaterial(color: UIColor(hex: 0xD8D2C0), roughness: .float(0.6), isMetallic: false)
                for key in ["star0", "star1"] {
                    for star in village.ambient[key] ?? [] {
                        for case let ray as ModelEntity in star.children where ray.name == "ray" {
                            ray.model?.materials = [material]
                        }
                    }
                }
            default:
                break
            }
        case .tv:
            thing.parts["dot"]?.isEnabled = on
            thing.value = -1
            if !on, let screen = thing.parts["screen"] as? ModelEntity {
                screen.model?.materials = [SimpleMaterial(color: UIColor(hex: 0x3B4252), roughness: .float(0.3), isMetallic: false)]
            }
        case .lamp, .streetLamp:
            if let bulb = thing.parts["bulb"] as? ModelEntity {
                if on {
                    bulb.model?.materials = [UnlitMaterial(color: UIColor(hex: 0xFFE08A))]
                } else {
                    bulb.model?.materials = [SimpleMaterial(color: UIColor(hex: 0xF2F2F2), roughness: .float(0.5), isMetallic: false)]
                }
            }
            thing.light?.isEnabled = on
        default:
            break
        }
    }

    private func popToys(from box: Interactive) {
        var toward = me.ground - box.center
        if simd_length(toward) < 0.01 { toward = SIMD2<Float>(0, 1) }
        toward = simd_normalize(toward)
        let side = SIMD2<Float>(-toward.y, toward.x)
        let floorY = Float(box.level) * Village.floorHeight
        for (i, ball) in box.contents.enumerated() where ball !== me.carrying {
            let p = ball.entity.position(relativeTo: nil)
            guard simd_distance(flat(p), box.center) < 0.7, p.y < floorY + 0.8 else { continue }
            let h = toward * 1.3 + side * (Float(i) - 1) * 0.6
            ball.entity.applyLinearImpulse(SIMD3<Float>(h.x, 4.2, h.y) * ball.mass, relativeTo: nil)
        }
        WorldSounds.shared.play(.boing)
    }

    private func getOn(_ thing: Interactive) {
        var anchor = thing.seat
        if thing.kind == .merry, thing.parts["saddle0"] != nil {
            // The carousel: climb onto the nearest horse.
            var best: Entity?
            var bestD = Float.infinity
            for i in 0..<12 {
                guard let saddle = thing.parts["saddle\(i)"] else { continue }
                let d = simd_distance(flat(saddle.position(relativeTo: nil)), me.ground)
                if d < bestD { bestD = d; best = saddle }
            }
            anchor = best
        } else if thing.kind == .merry, let platform = thing.parts["platform"] {
            // Sit on the edge nearest to where the animal stands, facing outwards.
            var dir = me.ground - thing.center
            if simd_length(dir) < 0.01 { dir = SIMD2<Float>(0, 1) }
            dir = simd_normalize(dir)
            let a = Entity()
            platform.addChild(a)
            a.setPosition(SIMD3<Float>(thing.center.x + dir.x * thing.ringRadius, 0.36, thing.center.y + dir.y * thing.ringRadius), relativeTo: nil)
            a.setOrientation(rotY(atan2(dir.x, dir.y)), relativeTo: nil)
            thing.seat?.removeFromParent()
            thing.seat = a
            anchor = a
        }
        guard let anchor else { return }
        let q = anchor.orientation(relativeTo: nil)
        let f = q.act(SIMD3<Float>(0, 0, 1))
        me.hop(to: anchor.position(relativeTo: nil), yaw: atan2(f.x, f.z)) { [weak self] in
            guard let self else { return }
            self.me.sit(on: anchor, thing: thing)
            thing.isOn = true
            if thing.kind == .bathtub {
                WorldSounds.shared.play(.splash)
            } else if thing.kind != .bench {
                WorldSounds.shared.play(.whoosh)
            }
        }
    }

    private func getOff(then next: (@MainActor () -> Void)? = nil) {
        guard let ride = me.leaveRide() else { next?(); return }
        let thing = ride.thing
        thing.isOn = false
        var spot = thing.lastSpot
        if thing.kind == .merry {
            var d = me.ground - thing.center
            if simd_length(d) < 0.01 { d = SIMD2<Float>(0, 1) }
            spot = thing.center + simd_normalize(d) * max(2.1, thing.standRadius)
        }
        spot = village.clampToWorld(spot)
        me.hop(to: SIMD3<Float>(spot.x, me.floorY, spot.y), yaw: me.yaw, then: next)
    }

    private func slideDown(_ slide: Interactive) {
        let p = slide.path
        guard p.count == 5 else { return }
        let ahead = yawFacing(from: flat(p[0]), to: flat(p[4]))
        me.run([
            Walker.Key(position: p[0], yaw: ahead, duration: 0.35),
            Walker.Key(position: p[1], yaw: ahead, duration: 1.0),
            Walker.Key(position: p[2], yaw: ahead, duration: 0.35)
        ]) { [weak self] in
            guard let self else { return }
            WorldSounds.shared.play(.whoosh)
            self.me.run([
                Walker.Key(position: p[3], yaw: ahead, duration: 1.1),
                Walker.Key(position: p[4], yaw: ahead, duration: 0.45, hop: 0.3)
            ]) { [weak self] in
                self?.me.playAction(.jump)
            }
        }
    }

    private func bounce(on bed: Interactive) {
        guard let top = bed.seat else { return }
        let spot = top.position(relativeTo: nil)
        let yaw = me.yaw
        me.hop(to: spot, yaw: yaw, duration: 0.5, height: 0.5) { [weak self] in
            guard let self else { return }
            self.me.playAction(.jump)
            WorldSounds.shared.play(.boing)
            let back = bed.lastSpot
            self.me.run([
                Walker.Key(position: spot, yaw: yaw, duration: 2.4),
                Walker.Key(position: SIMD3<Float>(back.x, self.me.floorY, back.y), yaw: yaw + .pi, duration: 0.5, hop: 0.45)
            ])
        }
    }

    /// Hop into the ball pit: balls fly everywhere, then hop back out.
    private func jumpIn(_ pit: Interactive) {
        guard let seat = pit.seat else { return }
        let spot = seat.position(relativeTo: nil)
        let yaw = me.yaw
        me.hop(to: spot, yaw: yaw, duration: 0.55, height: 0.6) { [weak self] in
            guard let self else { return }
            WorldSounds.shared.play(.boing)
            for ball in pit.contents where ball !== self.me.carrying {
                let p = ball.entity.position(relativeTo: nil)
                guard simd_distance(flat(p), pit.center) < 1.0 else { continue }
                let kick = SIMD3<Float>(Float.random(in: -0.7...0.7), Float.random(in: 1.4...2.6), Float.random(in: -0.7...0.7))
                ball.entity.applyLinearImpulse(kick * ball.mass, relativeTo: nil)
            }
            self.me.playAction(.jump)
            let back = pit.lastSpot
            self.me.run([
                Walker.Key(position: spot, yaw: yaw, duration: 3.2),
                Walker.Key(position: SIMD3<Float>(back.x, self.me.floorY, back.y), yaw: yaw + .pi, duration: 0.5, hop: 0.45)
            ])
        }
    }

    private func updateThings(_ dt: Float) {
        for t in village.interactives {
            t.time += dt
            switch t.kind {
            case .door:
                t.value = ease(t.value, t.isOn ? 1.7 : 0, dt * 5)
                t.parts["hinge"]?.orientation = rotY(t.value)
            case .mailbox:
                t.value = ease(t.value, t.isOn ? 0 : -1.5, dt * 6)
                t.parts["flag"]?.orientation = rotX(t.value)
            case .toyBox:
                t.value = ease(t.value, t.isOn ? -1.9 : 0, dt * 5)
                t.parts["lid"]?.orientation = rotX(t.value)
            case .bell:
                let swing: Float = t.time < 4 ? 0.55 * sin(t.time * 9) * exp(-t.time * 1.1) : 0
                t.parts["pivot"]?.orientation = rotX(swing)
            case .fountain:
                updateFountain(t, dt)
            case .swing:
                t.value = ease(t.value, t.isOn ? 0.6 : 0, dt * (t.isOn ? 0.8 : 0.5))
                t.phase += dt * 2.3
                t.parts["pivot"]?.orientation = rotX(t.value * sin(t.phase))
            case .merry:
                t.value = ease(t.value, t.isOn ? t.spinSpeed : 0, dt * (t.isOn ? 0.9 : 0.4))
                t.phase += t.value * dt
                t.parts["platform"]?.orientation = rotY(t.phase)
                // Carousel horses go up and down while it turns; its lights twinkle.
                let going = min(1, t.value / max(t.spinSpeed, 0.01))
                for i in 0..<6 {
                    t.parts["horse\(i)"]?.position.y = 0.6 + 0.14 * going * sin(t.phase * 2.5 + Float(i) * 1.05)
                }
                for i in 0..<16 {
                    guard let light = t.parts["light\(i)"] else { break }
                    light.scale = SIMD3<Float>(repeating: 1 + 0.35 * going * sin(clock * 6 + Float(i) * 0.8))
                }
            case .tv:
                updateTV(t, dt)
            case .fridge:
                t.value = ease(t.value, t.isOn ? -1.8 : 0, dt * 5)
                t.parts["hinge"]?.orientation = rotY(t.value)
            case .stove:
                let cooking = t.time < 4
                let lidY: Float = cooking ? 1.16 + abs(sin(t.time * 14)) * 0.03 : 1.16
                t.parts["lid"]?.position.y = lidY
                for i in 0..<4 {
                    guard let puff = t.parts["puff\(i)"] else { continue }
                    puff.isEnabled = cooking
                    guard cooking else { continue }
                    let u = (t.time * 0.8 + Float(i) * 0.25).truncatingRemainder(dividingBy: 1)
                    puff.position = [-0.17 + sin(Float(i) * 2.1) * 0.06, 1.25 + u * 0.7, cos(Float(i) * 2.1) * 0.06]
                    puff.scale = SIMD3<Float>(repeating: 0.6 + u * 0.9)
                }
            case .sink:
                let running = t.time < 3
                t.parts["jet"]?.isEnabled = running
                if running { t.parts["jet"]?.scale = [1 + 0.15 * sin(t.time * 30), 1, 1] }
            case .toilet:
                t.value = ease(t.value, t.time < 2.4 ? -1.7 : 0, dt * 6)
                t.parts["lid"]?.orientation = rotX(t.value)
                t.phase += dt * (t.time < 2.2 ? 12 : 0.5)
                t.parts["swirl"]?.orientation = rotY(t.phase)
            case .bathtub:
                for i in 0..<7 {
                    guard let bubble = t.parts["bubble\(i)"] else { continue }
                    bubble.isEnabled = t.isOn
                    if t.isOn { bubble.position.y = 0.45 + 0.03 * sin(clock * 3 + Float(i)) }
                }
            case .wardrobe:
                if t.isOn && t.time > 9 { t.isOn = false }
                t.value = ease(t.value, t.isOn ? 1.6 : 0, dt * 5)
                t.parts["left"]?.orientation = rotY(-t.value)
                t.parts["right"]?.orientation = rotY(t.value)
            case .boat:
                updateBoat(t, dt)
            case .duck:
                let a = clock * 0.35 + t.phase
                let o = t.orbit
                let c = t.center + SIMD2<Float>(o.x * sin(a), o.y * cos(a))
                let hop: Float = t.time < 0.6 ? 0.25 * sin(.pi * t.time / 0.6) : 0
                t.parts["duck"]?.position = [c.x, t.floatY + hop + 0.015 * sin(clock * 3 + t.phase), c.y]
                t.parts["duck"]?.orientation = rotY(atan2(o.x * cos(a), -o.y * sin(a)))
            case .frog:
                updateFrog(t)
            case .campfire:
                if t.isOn {
                    // Each flame stretches between 0.8 and 1.2 tall and sways a little, out of step.
                    for i in 0..<3 {
                        guard let flame = t.parts["flame\(i)"] else { continue }
                        let ph = Float(i) * 2.1
                        let y = 1 + 0.2 * sin(clock * (6.5 + Float(i) * 1.7) + ph)
                        let w = 1 + 0.06 * sin(clock * 9 + ph)
                        flame.scale = [w, y, w]
                        let sway = 0.025 * sin(clock * 3.1 + ph)
                        flame.position.x = Float(i - 1) * 0.08 + sway
                        flame.orientation = rotZ(sway * 3)
                    }
                    t.light?.light.intensity = 14000 + 1200 * sin(clock * 11) + 700 * sin(clock * 17.3 + 1)
                }
            case .conveyor:
                pressCap(t)
                updateConveyor(t, dt)
            case .crane:
                pressCap(t)
                updateCrane(t)
            case .marbleRun:
                pressCap(t)
                updateMarbles(t)
            case .robot:
                updateRobot(t)
            case .gears:
                t.value = ease(t.value, t.time < 5 ? 2.0 : 0, dt * 2.5)
                t.phase += t.value * dt
                let r0 = t.numbers.first ?? 1
                for (i, r) in t.numbers.enumerated() {
                    let turn = t.phase * r0 / r * (i % 2 == 0 ? 1 : -1)
                    t.parts["gear\(i)"]?.orientation = rotZ(turn)
                }
            case .bigButton:
                pressCap(t)
            case .ferris:
                updateFerris(t, dt)
            case .lightButton:
                pressCap(t)
                if Int(t.numbers.first ?? 0) == 0, t.isOn {
                    let step = Int(clock * 5)
                    if Float(step) != t.phase {
                        t.phase = Float(step)
                        paintBulbs(t, offset: step)
                    }
                }
            case .popcorn:
                for i in 0..<14 {
                    guard let kernel = t.parts["kernel\(i)"] else { continue }
                    let k = t.time
                    kernel.position.y = k < 3 ? 0.95 + abs(sin(k * 9 + Float(i) * 1.7)) * 0.35 * (1 - k / 3) : 0.95
                }
            case .snowman:
                let wave: Float = t.time < 1.4 ? 0.6 * sin(t.time * 12) * (1 - t.time / 1.4) : 0
                t.parts["armL"]?.orientation = rotZ(wave)
                t.parts["armR"]?.orientation = rotZ(-wave)
            case .rocker:
                t.value = ease(t.value, t.isOn ? 0.22 : 0, dt * (t.isOn ? 1.5 : 0.8))
                t.phase += dt * 2.6
                t.parts["pivot"]?.orientation = rotX(t.value * sin(t.phase))
            default:
                break
            }
        }
    }

    /// When on: a ball bounces across a screen that changes color.
    private func updateTV(_ tv: Interactive, _ dt: Float) {
        guard tv.isOn else { return }
        tv.phase += dt
        let colors: [UInt32] = [0x8ED3F5, 0xFFD45C, 0x9BD77A, 0xFF8FB1]
        let index = Int(tv.phase / 1.6) % colors.count
        if Float(index) != tv.value, let screen = tv.parts["screen"] as? ModelEntity {
            tv.value = Float(index)
            screen.model?.materials = [UnlitMaterial(color: UIColor(hex: colors[index]))]
        }
        let x = 0.5 * sin(tv.phase * 1.3)
        let y = 0.72 + 0.55 * abs(sin(tv.phase * 3.1))
        tv.parts["dot"]?.position = [x, y, 0.0]
    }

    private func updateFountain(_ f: Interactive, _ dt: Float) {
        let burst = f.time < 3.5
        f.value = ease(f.value, burst ? 2.6 : 0.45, dt * (burst ? 6 : 2))
        f.parts["jet"]?.scale = SIMD3<Float>(1, max(0.05, f.value), 1)
        for i in 0..<8 {
            guard let drop = f.parts["drop\(i)"] else { continue }
            drop.isEnabled = burst
            guard burst else { continue }
            let a = Float(i) / 8 * 2 * .pi
            let u = (f.time * 1.3 + Float(i % 3) * 0.33).truncatingRemainder(dividingBy: 1)
            let r = 1.15 * u
            let y = 1.4 + 1.5 * u - 1.9 * u * u
            drop.position = SIMD3<Float>(f.center.x + r * sin(a), y, f.center.y + r * cos(a))
        }
    }

    // MARK: - The friend

    private func maybeFriendCopies(_ action: FigureAction) {
        guard friendCopy == nil, Float.random(in: 0...1) < 0.65, friend.level == me.level,
              simd_distance(friend.ground, me.ground) < 5 else { return }
        friendCopy = (action: action, delay: 0.5)
    }

    /// The friend joins in when something fun starts nearby (the TV).
    private func friendJoins(_ action: FigureAction, near thing: Interactive) {
        guard friendCopy == nil, friend.level == thing.level, !friend.isBusy,
              simd_distance(friend.ground, thing.center) < 7 else { return }
        friend.stop()
        friendCopy = (action: action, delay: 0.8)
    }

    private func updateFriend(_ dt: Float) {
        friendCooldown -= dt
        if let copy = friendCopy {
            let left = copy.delay - dt
            if left <= 0 {
                friendCopy = nil
                friend.face(yawFacing(from: friend.ground, to: me.ground))
                friend.playAction(copy.action)
                SoundBoard.shared.ui(.hail, volume: 0.35)
                friendIdle = -Float(copy.action.duration)
            } else {
                friendCopy = (action: copy.action, delay: left)
            }
        }
        if friend.rig.isActing || friend.isBusy { return }

        let sameFloor = friend.level == me.level
        let distance = sameFloor ? simd_distance(friend.ground, me.ground) : 100
        if distance > 3.4 && friendCooldown <= 0 {
            guard !friend.isWalking, !me.isBusy else { return }
            friend.walkSpeed = 2.4
            var dir = friend.ground - me.ground
            let len = simd_length(dir)
            dir = (len < 0.01 || !sameFloor) ? SIMD2<Float>(0.8, -0.6) : dir / len
            // Next to the animal, but not where it hides it from the camera or stands in a tree.
            var target = village.clampToWorld(me.ground + dir * 1.6)
            for k in 1..<8 {
                let a = Float((k + 1) / 2) * 0.55 * (k % 2 == 0 ? -1 : 1)
                if friendSpotOK(target, level: me.level) { break }
                target = village.clampToWorld(me.ground + rotateY(dir, a) * 1.6)
            }
            friendCooldown = 1.0   // don't plan a new walk every frame if this one can't start
            travel(friend, to: target, level: me.level) { [weak self] in
                guard let self else { return }
                if self.friend.arrivedStuck { self.friendCooldown = 2.5 }
                self.friend.face(yawFacing(from: self.friend.ground, to: self.me.ground))
            }
        } else if !friend.isWalking {
            friendIdle += dt
            // Standing between the camera and the animal: move out of the way soon.
            if sameFloor && friendIdle > 0.8 && friendIdle < friendNextWander && inCameraCorridor(friend.ground) {
                friendIdle = friendNextWander + 0.01
            }
            if friendIdle > friendNextWander {
                friendIdle = 0
                friendNextWander = Float.random(in: 3...7)
                var spot: SIMD2<Float>?
                for _ in 0..<10 {
                    let a = Float.random(in: 0..<(2 * .pi))
                    let r = Float.random(in: 1.6...2.8)
                    let p = village.clampToWorld(me.ground + SIMD2<Float>(sin(a), cos(a)) * r)
                    if friendSpotOK(p, level: friend.level) { spot = p; break }
                }
                guard let p = spot else { return }
                friend.walkSpeed = 1.3
                travel(friend, to: p, level: friend.level) { [weak self] in
                    guard let self else { return }
                    if self.friend.arrivedStuck { self.friendCooldown = 2.5 }
                    self.friend.face(yawFacing(from: self.friend.ground, to: self.me.ground))
                }
            }
        }
    }

    /// A good place for the friend to stand: free ground, not touching the animal, not blocking the view.
    private func friendSpotOK(_ p: SIMD2<Float>, level: Int) -> Bool {
        village.isFree(p, level: level)
            && simd_distance(p, me.ground) > 1.3
            && !(level == me.level && inCameraCorridor(p))
    }

    /// Is this spot in the strip between the camera and the animal?
    private func inCameraCorridor(_ p: SIMD2<Float>) -> Bool {
        let a = me.ground
        let b = flat(camera.position(relativeTo: nil))
        let ab = b - a
        let len2 = simd_length_squared(ab)
        guard len2 > 0.01 else { return false }
        let t = simd_dot(p - a, ab) / len2
        guard t > 0.05, t < 1.1 else { return false }
        return simd_distance(p, a + ab * t) < 0.9
    }

    // MARK: - Getting around: doors, stairs, the way around furniture

    /// Walks a walker to a spot on a floor: through doors (they open by themselves),
    /// around furniture and up or down the stairs.
    private func travel(_ w: Walker, to target: SIMD2<Float>, level: Int, then: (@MainActor () -> Void)? = nil) {
        openDoors(from: w.ground, to: target)
        if w === me {
            me.walkSpeed = simd_distance(me.ground, target) > 6 || w.level != level ? 2.7 : 2.0
        }
        guard w.level != level, let stairs = village.stairs else {
            let path = village.findPath(from: w.ground, to: target, level: w.level)
            w.walk(to: path.last ?? target, via: Array(path.dropLast()), then: then)
            return
        }
        let up = w.level == 0
        let entry = up ? stairs.bottom : stairs.top
        let path = village.findPath(from: w.ground, to: entry, level: w.level)
        w.walk(to: entry, via: Array(path.dropLast())) { [weak self, weak w] in
            guard let self, let w else { return }
            guard simd_distance(w.ground, entry) < 0.9 else {
                then?()
                return
            }
            self.climb(w, up: up) { [weak self, weak w] in
                guard let self, let w else { return }
                self.travel(w, to: target, level: level, then: then)
            }
        }
    }

    private func climb(_ w: Walker, up: Bool, then: @escaping @MainActor () -> Void) {
        guard let stairs = village.stairs else { then(); return }
        if w === me { SoundBoard.shared.ui(.float, volume: 0.4) }
        w.run(up ? stairs.up1 : stairs.down1) { [weak w] in
            guard let w else { return }
            w.level = up ? 1 : 0
            w.run(up ? stairs.up2 : stairs.down2, then: then)
        }
    }

    /// Opens a closed front door when the way goes in or out of that house.
    private func openDoors(from a: SIMD2<Float>, to b: SIMD2<Float>) {
        for house in village.houses {
            guard let door = house.door, !door.isOn, house.contains(a) != house.contains(b) else { continue }
            setToggle(door, true)
            SoundBoard.shared.ui(.latch, volume: 0.3)
        }
    }

    /// Inside the big house, walls between the camera and the animal turn see-through.
    private func updateWallFade() {
        guard let big = village.bigHouse else { return }
        var want = Set<ObjectIdentifier>()
        if big.contains(me.ground) {
            let a = me.ground
            let b = flat(camera.position(relativeTo: nil))
            let n = max(1, Int(simd_distance(a, b) / 0.2))
            for w in village.bigWalls where w.level == me.level {
                for k in 1...n {
                    let p = a + (b - a) * (Float(k) / Float(n))
                    let d = simd_abs(p - w.center)
                    if d.x < w.half.x + 0.15 && d.y < w.half.y + 0.15 {
                        want.insert(ObjectIdentifier(w.entity))
                        break
                    }
                }
            }
        }
        guard want != fadedWalls else { return }
        for w in village.bigWalls {
            let id = ObjectIdentifier(w.entity)
            let faded = want.contains(id)
            if faded != fadedWalls.contains(id) {
                w.entity.components.set(OpacityComponent(opacity: faded ? 0.18 : 1))
            }
        }
        fadedWalls = want
    }

    // MARK: - Sparkles

    private func sparkle(around w: Walker) {
        sparkle(at: w.entity.position(relativeTo: nil) + SIMD3<Float>(0, 0.45, 0))
    }

    private func sparkle(at base: SIMD3<Float>) {
        guard arView != nil else { return }
        let colors: [UInt32] = [0xFFD45C, 0xFF8FB1, 0x8ED3F5, 0x9BD77A, 0xFFFFFF, 0xC86FC9]
        for i in 0..<24 {
            let e = ModelEntity(mesh: sparkMesh, materials: [UnlitMaterial(color: UIColor(hex: colors[i % colors.count]))])
            e.position = base
            village.root.addChild(e)
            let a = Float(i) / 24 * 2 * .pi
            let out = Float.random(in: 0.9...1.6)
            sparks.append(Spark(entity: e, velocity: [cos(a) * out, Float.random(in: 1.0...2.4), sin(a) * out], life: 1.6))
        }
        WorldSounds.shared.play(.ding, volume: 0.25)
    }

    private func updateSparks(_ dt: Float) {
        guard !sparks.isEmpty else { return }
        for i in sparks.indices.reversed() {
            sparks[i].life -= dt
            sparks[i].velocity.y -= 3 * dt
            let s = sparks[i]
            if s.life <= 0 {
                s.entity.removeFromParent()
                sparks.remove(at: i)
                continue
            }
            s.entity.position += s.velocity * dt
            s.entity.scale = SIMD3<Float>(repeating: max(0.05, s.life / 1.6))
        }
    }

    // MARK: - Going to another place

    func switchScene(_ place: SceneKind) {
        guard place != village.scene, let world, moves.isEmpty else { return }
        if let ride = me.leaveRide() { ride.thing.isOn = false }
        if let held = me.carrying { drop(held, soft: true) }
        for child in me.entity.children where child.name == "rideSled" { child.removeFromParent() }
        releaseCraneLoad()
        save()
        village.root.removeFromParent()
        let v = Village(scene: place)
        village = v
        v.letSwimmerIn(lastLook.animal.isSwimmer)
        world.addChild(v.root)
        me.reset(at: v.start, yaw: .pi)
        friend.reset(at: v.start + SIMD2<Float>(1.4, 0.7), yaw: .pi)
        me.ignoreProp = nil
        lastPositions = [:]
        velocities = [:]
        delayed = []
        friendCopy = nil
        friendIdle = 0
        fadedWalls = []
        capBase = [:]
        for s in sparks { s.entity.removeFromParent() }
        sparks = []
        clearUndo()
        restore()
        arView?.environment.background = .color(UIColor(hex: place.sky))
        setLights()
        viewLength = 100
        pitchLift = 0
        smoothWalkYaw = .pi
        sharpTurnHold = 0
        camTarget = me.entity.position(relativeTo: nil) + SIMD3<Float>(0, 0.75, 0)
        camYaw = .pi
        camSqueeze = 1
        recentering = 0
        updateCamera(1, inside: false)
        WorldSounds.shared.play(.whoosh, volume: 0.5)
        sparkle(around: me)
    }

    // MARK: - Pond and snow things

    /// Hop across the pond on the stepping stones, to the other side.
    private func crossStones(_ stones: Interactive) {
        guard stones.spots.count == 2, !stones.path.isEmpty else { return }
        let fromWest = simd_distance(me.ground, stones.spots[0]) <= simd_distance(me.ground, stones.spots[1])
        let pts: [SIMD3<Float>] = fromWest ? stones.path : Array(stones.path.reversed())
        let end = fromWest ? stones.spots[1] : stones.spots[0]
        let yaw: Float = fromWest ? .pi / 2 : -.pi / 2
        var keys = pts.map { Walker.Key(position: $0, yaw: yaw, duration: 0.42, hop: 0.35) }
        keys.append(Walker.Key(position: SIMD3<Float>(end.x, 0, end.y), yaw: yaw, duration: 0.45, hop: 0.35))
        WorldSounds.shared.play(.boing, volume: 0.35)
        me.run(keys) { [weak self] in
            self?.me.playAction(.jump)
        }
    }

    /// The boat goes once round the pond and comes back to the jetty.
    private func updateBoat(_ boat: Interactive, _ dt: Float) {
        let riding = me.ride?.thing === boat && !me.isBusy
        if riding || boat.phase > 0 {
            boat.phase += dt * 0.45
            if boat.phase >= 2 * .pi {
                boat.phase = 0
                if me.ride?.thing === boat { getOff() }
            }
        }
        let (p, yaw) = Village.boatPose(boat.phase)
        boat.parts["boat"]?.position = [p.x, 0.06 + 0.02 * sin(clock * 2.2), p.y]
        boat.parts["boat"]?.orientation = rotY(yaw) * rotZ(0.03 * sin(clock * 1.7))
    }

    private func frogJumps(_ frog: Interactive) {
        guard frog.time > 0.7, !frog.path.isEmpty else { return }
        let taken = Set(village.interactives.filter { $0.kind == .frog && $0 !== frog }.map { Int($0.value) })
        let ducks = village.interactives.filter { $0.kind == .duck }.compactMap { $0.parts["duck"]?.position(relativeTo: nil) }
        let free = frog.path.indices.filter { i in
            !taken.contains(i) && i != Int(frog.value)
                && !ducks.contains { simd_distance(flat($0), flat(frog.path[i])) < 1.0 }
        }
        guard let next = free.randomElement() else { return }
        frog.phase = frog.value
        frog.value = Float(next)
        frog.time = 0
        WorldSounds.shared.play(.ribbit)
    }

    private func updateFrog(_ frog: Interactive) {
        guard let e = frog.parts["frog"], !frog.path.isEmpty else { return }
        let from = frog.path[min(frog.path.count - 1, Int(frog.phase))]
        let to = frog.path[min(frog.path.count - 1, Int(frog.value))]
        guard frog.time < 0.65 else {
            e.position = to
            return
        }
        let u = smoothStep(frog.time / 0.65)
        var p = from + (to - from) * u
        p.y += 0.7 * sin(.pi * u)
        e.position = p
        e.orientation = rotY(atan2(to.x - from.x, to.z - from.z))
    }

    /// Climb the icy steps, then sled down the hill.
    private func sledDown(_ hill: Interactive) {
        let p = hill.path
        guard p.count == 10 else { return }
        let up: Float = -.pi / 2
        me.run([
            Walker.Key(position: p[0], yaw: up, duration: 0.4),
            Walker.Key(position: p[1], yaw: up, duration: 0.6, hop: 0.15),
            Walker.Key(position: p[2], yaw: up, duration: 0.55, hop: 0.15),
            Walker.Key(position: p[3], yaw: up, duration: 0.55, hop: 0.15),
            Walker.Key(position: p[4], yaw: 0, duration: 0.6)
        ]) { [weak self] in
            guard let self else { return }
            let sled = self.village.makeSledModel()
            sled.name = "rideSled"
            sled.position = [0, -0.05, 0]
            self.me.entity.addChild(sled)
            hill.parts["sled"]?.isEnabled = false
            SoundBoard.shared.ui(.drift, volume: 0.5)
            WorldSounds.shared.play(.whoosh, volume: 0.5)
            self.me.run([
                Walker.Key(position: p[5], yaw: 0, duration: 0.35, linear: true),
                Walker.Key(position: p[6], yaw: 0, duration: 0.5, linear: true),
                Walker.Key(position: p[7], yaw: 0, duration: 0.4, linear: true),
                Walker.Key(position: p[8], yaw: 0, duration: 0.4, linear: true),
                Walker.Key(position: p[9], yaw: 0, duration: 0.8)
            ]) { [weak self] in
                sled.removeFromParent()
                hill.parts["sled"]?.isEnabled = true
                self?.me.playAction(.jump)
                self?.maybeFriendCopies(.jump)
            }
        }
    }

    /// Skate a big circle on the ice, then spin.
    private func skate(on rink: Interactive) {
        let c = rink.center
        var d = me.ground - c
        if simd_length(d) < 0.01 { d = SIMD2<Float>(0, 1) }
        let start = atan2(d.x, d.y)
        var keys: [Walker.Key] = []
        let steps = 12
        for k in 1...steps {
            let a = start + Float(k) / Float(steps) * 2 * .pi
            let p = c + SIMD2<Float>(sin(a), cos(a)) * 2.0
            keys.append(Walker.Key(position: [p.x, 0.03, p.y], yaw: a + .pi / 2, duration: 0.32, linear: true))
        }
        let back = c + SIMD2<Float>(sin(start), cos(start)) * 2.0
        keys.insert(Walker.Key(position: [back.x, 0.03, back.y], yaw: start + .pi / 2, duration: 0.5), at: 0)
        WorldSounds.shared.play(.whoosh, volume: 0.5)
        me.run(keys) { [weak self] in
            self?.me.playAction(.spin)
            self?.maybeFriendCopies(.spin)
        }
    }

    // MARK: - Workshop and carnival things

    /// A big button dips down for a moment after it is pressed.
    private func pressCap(_ t: Interactive) {
        guard let cap = t.parts["cap"] else { return }
        let id = ObjectIdentifier(cap)
        let base = capBase[id] ?? cap.position.y
        capBase[id] = base
        cap.position.y = base - (t.time < 0.3 ? 0.05 * sin(.pi * t.time / 0.3) : 0)
    }

    /// While the belt runs, its stripes move and whatever lies on it rides to the bin.
    private func updateConveyor(_ belt: Interactive, _ dt: Float) {
        guard belt.isOn, belt.path.count == 2, dt > 0 else { return }
        let a = belt.path[0], b = belt.path[1]
        let len = b.x - a.x
        belt.phase = (belt.phase + dt * 0.9).truncatingRemainder(dividingBy: len)
        for i in 0..<10 {
            let x = (Float(i) * len / 10 + belt.phase).truncatingRemainder(dividingBy: len)
            belt.parts["stripe\(i)"]?.position.x = a.x + x
        }
        guard moves.isEmpty else { return }
        for p in village.props where p !== me.carrying && p.entity.parent === village.root {
            let pos = p.entity.position(relativeTo: nil)
            // On the belt, or just tipping off its end.
            let onBelt = pos.x > a.x - 0.1 && pos.x < b.x + 0.15 && pos.y > a.y
            let tipping = pos.x >= b.x + 0.15 && pos.x < b.x + 0.6 && pos.y > 0.3
            guard onBelt || tipping, abs(pos.z - a.z) < 0.5, pos.y < a.y + 0.9 else { continue }
            let v = velocity(of: p)
            let push = SIMD3<Float>(0.9 - v.x, 0, -v.z * 0.5 - (pos.z - a.z) * 0.8)
            p.entity.applyLinearImpulse(push * p.mass * 0.5, relativeTo: nil)
        }
    }

    /// The crane: lower, pick up a metal thing, swing round, drop it in the bin, swing back.
    private func updateCrane(_ crane: Interactive) {
        guard let pivot = crane.parts["pivot"], let cable = crane.parts["cable"], let magnet = crane.parts["magnet"] else { return }
        let t = crane.time
        let up: Float = 0.9, down: Float = 3.2, drop: Float = 2.6
        var length = up
        var angle: Float = 0
        if crane.isOn {
            switch t {
            case ..<1.3: length = up + (down - up) * smoothStep(t / 1.3)
            case ..<2.6: length = down + (up - down) * smoothStep((t - 1.3) / 1.3)
            case ..<4.6: angle = .pi * smoothStep((t - 2.6) / 2)
            case ..<5.9: angle = .pi; length = up + (drop - up) * smoothStep((t - 4.6) / 1.3)
            case ..<7.0: angle = .pi; length = drop + (up - drop) * smoothStep((t - 5.9) / 1.1)
            case ..<9.0: angle = .pi * (1 - smoothStep((t - 7.0) / 2))
            default: crane.isOn = false
            }
            // Pick up at the bottom of the first drop, let go over the bin.
            if crane.value < 1.3, t >= 1.3 { pickWithMagnet(crane, magnet) }
            if crane.value < 5.9, t >= 5.9 { releaseCraneLoad() }
            crane.value = t
        } else {
            crane.value = 100
        }
        pivot.orientation = rotY(angle)
        cable.scale = [1, length, 1]
        cable.position.y = -length / 2
        magnet.position.y = -length
    }

    private func pickWithMagnet(_ crane: Interactive, _ magnet: Entity) {
        let m = magnet.position(relativeTo: nil)
        let near = village.props.filter { p in
            p.id.hasPrefix("metal") && p !== me.carrying && p.entity.parent === village.root
                && simd_distance(flat(p.entity.position(relativeTo: nil)), flat(m)) < 0.8
                && p.entity.position(relativeTo: nil).y < 1.3
        }
        guard let prop = near.min(by: {
            simd_distance(flat($0.entity.position(relativeTo: nil)), flat(m)) < simd_distance(flat($1.entity.position(relativeTo: nil)), flat(m))
        }) else { return }
        prop.entity.physicsBody?.mode = .kinematic
        prop.entity.setParent(magnet, preservingWorldTransform: false)
        prop.entity.transform = Transform(scale: .one, rotation: rotY(0), translation: [0, -0.08 - prop.lift, 0])
        crane.contents = [prop]
        WorldSounds.shared.play(.thud, volume: 0.4)
    }

    /// Lets go of whatever the crane's magnet holds.
    private func releaseCraneLoad() {
        for crane in village.interactives where crane.kind == .crane {
            for prop in crane.contents where prop.entity.parent === crane.parts["magnet"] {
                prop.entity.setParent(village.root, preservingWorldTransform: true)
                prop.entity.physicsBody?.mode = .dynamic
                lastPositions[prop.id] = prop.entity.position(relativeTo: nil)
                velocities[prop.id] = .zero
            }
            crane.contents = []
        }
    }

    /// The marble goes up the lift and zig-zags down the ramps, with a soft click at each turn.
    private func updateMarbles(_ run: Interactive) {
        guard let marble = run.parts["marble"], run.path.count > 1 else { return }
        guard run.isOn else { return }
        var lengths: [Float] = []
        for i in 1..<run.path.count { lengths.append(simd_distance(run.path[i - 1], run.path[i])) }
        let total = lengths.reduce(0, +)
        var s = run.time * 1.5
        if s >= total {
            run.isOn = false
            marble.position = run.path[0]
            WorldSounds.shared.play(.ding, volume: 0.35)
            return
        }
        var i = 0
        while i < lengths.count - 1 && s > lengths[i] { s -= lengths[i]; i += 1 }
        if Float(i) > run.value {
            run.value = Float(i)
            if i >= 2 && i <= 8 { WorldSounds.shared.play(.click, volume: 0.25) }
        }
        let u = lengths[i] > 0 ? s / lengths[i] : 1
        marble.position = run.path[i] + (run.path[i + 1] - run.path[i]) * u
    }

    /// The robot waves, dances or looks around with its lights, a different one each tap.
    private func updateRobot(_ robot: Interactive) {
        let k = robot.time
        let active = k < 3
        let fade: Float = active ? min(1, k * 4) * min(1, (3 - k) * 2) : 0
        var armL: Float = 0, armR: Float = 0, bob: Float = 0, tilt: Float = 0, turn: Float = 0
        switch Int(robot.value) {
        case 1:   // wave
            armR = (2.5 + 0.4 * sin(k * 9)) * fade
        case 2:   // dance
            bob = 0.08 * abs(sin(k * 6)) * fade
            armL = -(1.3 + 0.5 * sin(k * 6)) * fade
            armR = (1.3 + 0.5 * sin(k * 6)) * fade
            tilt = 0.2 * sin(k * 6) * fade
        default:  // look around with a light show
            turn = 0.7 * sin(k * 2.5) * fade
        }
        robot.parts["armL"]?.orientation = rotZ(armL)
        robot.parts["armR"]?.orientation = rotZ(armR)
        robot.parts["body"]?.position.y = bob
        robot.parts["head"]?.orientation = rotY(turn) * rotZ(tilt)
        robot.parts["bulb"]?.isEnabled = clock.truncatingRemainder(dividingBy: 1.2) < 0.7
        let fast = active && Int(robot.value) == 0
        let step = Int(clock * (fast ? 8 : 1.2))
        if Float(step) != robot.phase {
            robot.phase = Float(step)
            let colors: [UInt32] = [0x7DFF6A, 0xFFD45C, 0xFF6F91, 0x7FF0FF]
            for i in 0..<3 {
                if let light = robot.parts["chest\(i)"] as? ModelEntity {
                    light.model?.materials = [UnlitMaterial(color: UIColor(hex: colors[(step + i) % colors.count]), applyPostProcessToneMap: false)]
                }
            }
        }
    }

    /// The ferris wheel goes round once with the animal in a gondola, then stops at the bottom.
    private func updateFerris(_ wheel: Interactive, _ dt: Float) {
        let riding = me.ride?.thing === wheel && !me.isBusy
        if riding || wheel.phase > 0 {
            wheel.phase += dt * 0.4
            if wheel.phase >= 2 * .pi {
                wheel.phase = 0
                if me.ride?.thing === wheel { getOff() }
            }
        }
        Village.placeGondolas(wheel)
    }

    /// The string lights: chasing colors (offset), or all warm white (nil).
    private func paintBulbs(_ board: Interactive, offset: Int?) {
        let count = Int(board.numbers.count > 1 ? board.numbers[1] : 0)
        let colors: [UInt32] = [0xFF6F91, 0xFFD45C, 0x7DFF6A, 0x7FD0FF, 0xC88BFF]
        var materials: [UnlitMaterial] = []
        for c in colors { materials.append(UnlitMaterial(color: UIColor(hex: c), applyPostProcessToneMap: false)) }
        let warm = UnlitMaterial(color: UIColor(hex: 0xFFE8B0), applyPostProcessToneMap: false)
        for i in 0..<count {
            guard let bulb = board.parts["bulb\(i)"] as? ModelEntity else { continue }
            if let offset {
                bulb.model?.materials = [materials[(i + offset) % materials.count]]
            } else {
                bulb.model?.materials = [warm]
            }
        }
    }

    /// Three gentle bursts of sparkles above the carousel.
    private func fireworks() {
        let c = Village.carouselCenter
        let spots: [SIMD3<Float>] = [[c.x - 2.2, 5.6, c.y + 0.5], [c.x + 2.4, 6.2, c.y - 0.5], [c.x, 6.8, c.y]]
        WorldSounds.shared.play(.whoosh, volume: 0.4)
        for (i, p) in spots.enumerated() {
            after(0.35 + Float(i) * 0.45) { [weak self] in self?.sparkle(at: p) }
        }
        if !me.isBusy && !me.isRiding { me.playAction(.jump) }
        maybeFriendCopies(.jump)
    }

    // MARK: - Saving

    private func save() {
        var s = WorldSave()
        for p in village.props {
            let t = Transform(matrix: p.entity.transformMatrix(relativeTo: nil))
            s.props[p.id] = WorldSave.Item(
                p: [t.translation.x, t.translation.y, t.translation.z],
                q: [t.rotation.imag.x, t.rotation.imag.y, t.rotation.imag.z, t.rotation.real])
        }
        for t in village.interactives {
            switch t.kind {
            case .door, .lamp, .streetLamp, .mailbox, .toyBox, .tv, .fridge, .campfire, .conveyor, .bigButton:
                s.toggles[t.id] = t.isOn
            case .lightButton where Int(t.numbers.first ?? 0) != 2:
                s.toggles[t.id] = t.isOn
            default: break
            }
        }
        WorldStore.save(s, for: village.scene)
    }

    private func restore() {
        guard let s = WorldStore.load(village.scene) else { return }
        for p in village.props {
            guard let item = s.props[p.id], item.p.count == 3, item.q.count == 4 else { continue }
            let pos = SIMD3<Float>(item.p[0], item.p[1], item.p[2])
            if pos.y < -1 || simd_length(flat(pos)) > 19 { continue }
            p.entity.position = pos
            p.entity.orientation = simd_quatf(ix: item.q[0], iy: item.q[1], iz: item.q[2], r: item.q[3])
            lastPositions[p.id] = pos
        }
        for t in village.interactives {
            if let on = s.toggles[t.id] { setToggle(t, on, instant: true) }
        }
    }
}

