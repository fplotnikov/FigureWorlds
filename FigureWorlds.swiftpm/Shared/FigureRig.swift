import RealityKit
import UIKit
import Foundation

/// Holds one figure and plays its actions frame by frame.
///
/// Hierarchy: root (placement + gestures) > turntable (user spin) > motion (actions) > body.
/// All poses are eased toward their target, so switching actions never snaps.
final class FigureRig {
    let root = ModelEntity()
    let turntable = Entity()
    let motion = Entity()

    /// How far the figure runs from its spot, in figure units.
    var runRadius: Float = 0.12
    var keepGoing = false

    private var parts: FigureParts?
    private var action: FigureAction?
    private var actionTime: Double = 0
    private var clock: Double = 0
    private var pose = Pose()

    /// Set when the current animal is a Blender model instead of a shape figure.
    private var real: RealFigure?

    // Robots: the vehicle they change into for Run (models/make_vehicle.py).
    private var vehicleHolder: Entity?
    private var rotor: Entity?
    private var robotScale: Float = 1
    private var vehicleScale: Float = 0
    private var rotorAngle: Float = 0
    private var vehicleKind: String? { real?.vehicleInfo?.kind.rawValue }
    /// Animatronics turn in stiff steps (spin, and the turns while running round).
    private var isAnimatronic: Bool { real?.animal.isAnimatronic ?? false }
    private var isDinosaur: Bool { real?.animal.group == .dinosaurs }
    /// Vehicles are shown a little smaller than the robot so the trip fits on the shelf.
    private static let vehicleSize: Float = 0.75
    private var currentLook: Look?
    private var loadObserver: NSObjectProtocol?

    /// Figure Worlds: walking across the world (the run clip on a loop, without the run circle).
    private(set) var walking = false
    /// True while an action (dance, jump...) is playing.
    var isActing: Bool { action != nil }

    func setWalking(_ on: Bool) {
        guard on != walking else { return }
        walking = on
        if action == nil { playClip(for: nil) }
    }

    init() {
        root.addChild(turntable)
        turntable.addChild(motion)
        root.collision = CollisionComponent(shapes: [
            ShapeResource.generateBox(size: [0.16, 0.26, 0.16]).offsetBy(translation: [0, 0.12, 0])
        ])
        // When a Blender model finishes loading, swap it in for the shape figure.
        loadObserver = NotificationCenter.default.addObserver(
            forName: RealModelLibrary.didLoad, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let look = self.currentLook, self.real == nil else { return }
            self.setLook(look)
        }
    }

    deinit {
        if let loadObserver { NotificationCenter.default.removeObserver(loadObserver) }
    }

    func setLook(_ look: Look) {
        currentLook = look
        let library = RealModelLibrary.shared
        if let template = library.template(for: look.animal) {
            // Same animal, new color or extra: change it in place so the animation keeps going.
            if let real, real.animal == look.animal {
                real.apply(look)
                return
            }
            parts?.body.removeFromParent()
            let figure = RealFigure(template: template, look: look)
            motion.addChild(figure.body)
            setUpVehicle(template.vehicle)
            parts = FigureParts(body: figure.body, legL: Entity(), legR: Entity(), armL: Entity(), armR: Entity())
            real = figure
            if let action, figure.hasClip(action.rawValue) {
                figure.play(action.rawValue, transition: 0)
            } else if walking {
                figure.playLoop("run", transition: 0)
            } else {
                figure.playIdle(transition: 0)
            }
            apply(pose)
            return
        }
        library.load(look.animal) // no-op for animals without a model file
        real = nil
        setUpVehicle(nil)
        parts?.body.removeFromParent()
        let built = FigureBuilder.build(look)
        motion.addChild(built.body)
        parts = built
        apply(pose)
    }

    func play(_ newAction: FigureAction?) {
        action = newAction
        actionTime = 0
        playClip(for: newAction)
        SoundBoard.shared.play(newAction, vehicle: vehicleKind, animatronic: isAnimatronic,
                                   dinosaur: isDinosaur, flyer: real?.animal == .pteranodon)
    }

    /// Robots run as their vehicle, which takes a little longer (change, trip, change back).
    private func duration(of action: FigureAction) -> Double {
        action == .run && real?.vehicleInfo != nil ? 6.0 : action.duration
    }

    private func setUpVehicle(_ vehicle: RealModelLibrary.Vehicle?) {
        vehicleHolder?.removeFromParent()
        vehicleHolder = nil
        rotor = nil
        robotScale = 1
        vehicleScale = 0
        guard let vehicle else { return }
        let holder = Entity()
        holder.addChild(vehicle.entity.clone(recursive: true))
        if vehicle.kind == .heli {
            // a soft, see-through spinning disc above the blades
            var disc = UnlitMaterial(color: UIColor(white: 0.25, alpha: 1))
            disc.blending = .transparent(opacity: .init(floatLiteral: 0.22))
            let r = ModelEntity(mesh: .generateCylinder(height: 0.001, radius: vehicle.length * 0.45), materials: [disc])
            r.position = [0, vehicle.height + 0.002, 0]
            holder.addChild(r)
            rotor = r
        }
        holder.scale = .zero
        holder.isEnabled = false
        motion.addChild(holder)
        vehicleHolder = holder
    }

    /// Blender models play their own clip for an action; spin and "stop" use idle.
    private func playClip(for action: FigureAction?) {
        guard let real else { return }
        if action == .run, real.vehicleInfo != nil {
            real.playIdle()          // the robot folds away; the vehicle does the running
        } else if let action, real.hasClip(action.rawValue) {
            real.play(action.rawValue)
        } else if walking {
            real.playLoop("run")
        } else {
            real.playIdle()
        }
    }

    func update(deltaTime: Double) {
        let dt = min(deltaTime, 0.1)
        clock += dt
        var target = Pose()
        target.stretch = 1 + 0.012 * sin(Float(clock) * 2.2) // gentle breathing

        if let current = action {
            actionTime += dt
            target = targetPose(for: current, at: Float(actionTime))
            if actionTime >= duration(of: current) {
                if keepGoing {
                    actionTime = 0
                    SoundBoard.shared.play(current, vehicle: vehicleKind, animatronic: isAnimatronic,
                                   dinosaur: isDinosaur, flyer: real?.animal == .pteranodon)   // "Again" repeats the sound too
                } else {
                    action = nil
                    SoundBoard.shared.play(nil)
                }
                playClip(for: action)
            }
        }

        // Figure Worlds: shape figures swing their legs and arms while walking.
        if action == nil && walking {
            let s = Float(clock) * 14
            target.leg = 0.7 * sin(s)
            target.armSwing = 0.6 * sin(s)
            target.armOutL = 0.3
            target.armOutR = 0.3
            target.y = 0.006 * abs(sin(s))
        }

        // Robots: Run = change into the vehicle, travel like it, change back.
        var robotTarget: Float = 1, vehicleTarget: Float = 0
        var tilt = simd_quatf(angle: 0, axis: [0, 1, 0])
        if action == .run, let v = real?.vehicleInfo {
            let (p, rs, vs, pitch, roll) = robotRun(v, t: Float(actionTime))
            target = p
            robotTarget = rs; vehicleTarget = vs
            tilt = simd_quatf(angle: roll, axis: [0, 0, 1]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
        }
        if let holder = vehicleHolder, let real {
            let kk = Float(1 - exp(-30 * dt))
            robotScale += (robotTarget - robotScale) * kk
            vehicleScale += (vehicleTarget - vehicleScale) * kk
            real.body.scale = .init(repeating: max(0.0001, robotScale))
            real.body.isEnabled = robotScale > 0.002
            holder.isEnabled = vehicleScale > 0.002
            holder.scale = .init(repeating: max(0.0001, vehicleScale * Self.vehicleSize))
            holder.orientation = simd_slerp(holder.orientation, tilt, Float(1 - exp(-10 * dt)))
            if let rotor {
                rotorAngle += Float(dt) * 30
                rotor.orientation = simd_quatf(angle: rotorAngle, axis: [0, 1, 0])
            }
            if action == .run {
                let k = Float(1 - exp(-18 * dt))
                pose = pose.blended(toward: target, amount: k)
                apply(pose)
                real.followBones()
                return
            }
        }

        if real != nil {
            // The clips already bounce, sway and move the limbs. Keep only the
            // whole-figure motion they cannot do: the run circle and the spin.
            var kept = Pose()
            switch action {
            case .run:
                kept.x = target.x
                kept.z = target.z
                if isAnimatronic { target.yaw = Self.stepped(target.yaw, step: .pi / 6) }
                // Creatures that stand turned (like their picture) still run head first.
                let turn = smooth(min(1, Float(actionTime) / 0.4, max(0, Float(FigureAction.run.duration - actionTime)) / 0.4))
                kept.yaw = target.yaw - (real?.bodyYaw ?? 0) * turn
            case .spin:
                // animatronics rotate like a turntable: eight clunky steps
                kept.yaw = isAnimatronic ? Self.stepped(target.yaw, step: .pi / 4) : target.yaw
                kept.y = isAnimatronic ? 0 : target.y
            default:
                break
            }
            target = kept
        }

        // Ease toward the target pose (animatronics snap faster).
        let k = Float(1 - exp(-(isAnimatronic ? 40 : 18) * dt))
        pose = pose.blended(toward: target, amount: k)
        apply(pose)
        real?.followBones()
    }

    /// Snaps an angle to steps with a quick, slightly overshooting move between them.
    private static func stepped(_ a: Float, step: Float) -> Float {
        let f = a / step
        let k = floor(f), u = f - k
        let snap = smooth(min(1, u / 0.3))
        let settle = 0.1 * sin(.pi * min(1, max(0, (u - 0.2) / 0.3))) * (1 - smooth(min(1, max(0, (u - 0.3) / 0.3))))
        return (k + snap + settle) * step
    }

    // MARK: - Robot vehicles

    /// Where the robot/vehicle is during a 6 s Run: (pose, robot size, vehicle size, pitch, roll).
    /// Pitch > 0 dips the nose; roll < 0 leans into the (left-hand) turn.
    private func robotRun(_ v: RealModelLibrary.Vehicle, t: Float) -> (Pose, Float, Float, Float, Float) {
        let d: Float = 6, change: Float = 0.8
        var p = Pose()
        var robot: Float = 0, car: Float = 1, pitch: Float = 0, roll: Float = 0
        let r = max(runRadius, v.length * Self.vehicleSize * 0.5) * (v.kind == .digger || v.kind == .forklift ? 0.75 : (v.kind == .airship ? 1.25 : 1))
        if t < change {
            // fold up with a quick spin; the vehicle grows from the same spot
            let k = smooth(t / change)
            robot = 1 - smooth(min(1, t / (change * 0.7)))
            car = smooth(max(0, (t - change * 0.3) / (change * 0.7)))
            p.yaw = (2 * .pi + .pi / 2) * k
            p.y = 0.015 * sin(.pi * k)
            return (p, robot, car, 0, 0)
        }
        if t > d - change {
            let k = smooth((t - (d - change)) / change)
            car = 1 - smooth(min(1, k / 0.7))
            robot = smooth(max(0, (k - 0.3) / 0.7))
            p.yaw = (.pi / 2) * (1 - k) + 2 * .pi * k
            p.y = 0.015 * sin(.pi * k)
            return (p, robot, car, 0, 0)
        }
        let u = (t - change) / (d - 2 * change)            // 0...1 along the trip
        var theta = 2 * Float.pi * smooth(u)
        let mid = smooth(min(1, u / 0.15, (1 - u) / 0.15)) // calm start and stop
        switch v.kind {
        case .car, .truck, .snow:
            let bump: Float = v.kind == .truck ? 0.0025 : 0.0015
            p.y = bump * abs(sin(t * (v.kind == .truck ? 11 : 17))) * mid
            pitch = 0.02 * sin(t * 9) * mid
            roll = -0.07 * mid
        case .bike:
            p.y = 0.001 * abs(sin(t * 15)) * mid
            roll = -0.35 * mid
        case .digger:
            p.y = 0.0012 * abs(sin(t * 9)) * mid
            pitch = 0.015 * sin(t * 5) * mid
            roll = -0.03 * mid
        case .jet, .plane:
            let up = smooth(min(1, u / 0.25)) * smooth(min(1, (1 - u) / 0.25))
            p.y = (v.kind == .jet ? 0.16 : 0.13) * up
            pitch = u < 0.25 ? -0.25 * sin(.pi * u / 0.25) : (u > 0.75 ? 0.18 * sin(.pi * (u - 0.75) / 0.25) : 0)
            roll = -0.4 * smooth(min(1, (u - 0.2) / 0.15, (0.8 - u) / 0.15))
        case .heli:
            // straight up, tilt and circle, then straight down
            theta = 2 * .pi * smooth(min(1, max(0, (u - 0.2) / 0.6)))
            p.y = 0.12 * smooth(min(1, u / 0.2)) * smooth(min(1, (1 - u) / 0.2))
            let fly = smooth(min(1, max(0, (u - 0.2) / 0.1), max(0, (0.8 - u) / 0.1)))
            pitch = 0.18 * fly
            roll = -0.15 * fly
            p.y += 0.004 * sin(t * 3)
        case .boat:
            p.y = 0.002 * sin(t * 4)
            pitch = 0.06 * sin(t * 3.1) - 0.04 * mid
            roll = (-0.1 + 0.05 * sin(t * 2.3)) * mid
        case .train:
            // steady chug: a small rhythmic rock, hardly any lean
            p.y = 0.001 * abs(sin(t * 12)) * mid
            pitch = 0.012 * sin(t * 6) * mid
            roll = -0.04 * mid
        case .bus:
            p.y = 0.0012 * abs(sin(t * 8)) * mid
            pitch = 0.012 * sin(t * 4) * mid
            roll = (-0.09 + 0.015 * sin(t * 3)) * mid
        case .tractor:
            // slow and bumpy, big wheels wobble it about
            p.y = 0.003 * abs(sin(t * 7)) * mid
            pitch = 0.035 * sin(t * 5.5) * mid
            roll = (-0.04 + 0.035 * sin(t * 6.5)) * mid
        case .forklift:
            // putters round, tipping back now and then as if lifting the forks
            p.y = 0.0012 * abs(sin(t * 10)) * mid
            pitch = (-0.07 * max(0, sin(t * 1.6)) + 0.01 * sin(t * 9)) * mid
            roll = -0.03 * mid
        case .sub:
            // floats a little above the ground, nose dipping and rising like a dive
            p.y = (0.012 + 0.008 * sin(t * 2.1)) * mid
            pitch = 0.14 * sin(t * 2.1 + 1.2) * mid
            roll = -0.08 * mid
        case .cable:
            // up as if hanging from a cable, gliding round with a gentle pendulum sway
            p.y = 0.1 * smooth(min(1, u / 0.2)) * smooth(min(1, (1 - u) / 0.2))
            roll = 0.12 * sin(t * 2.4) * mid
            pitch = 0.05 * sin(t * 1.7) * mid
        case .rover:
            // floaty low-gravity hops
            p.y = 0.02 * abs(sin(t * 3.2)) * mid
            pitch = 0.06 * sin(t * 3.2) * mid
            roll = -0.05 * mid
        case .airship:
            // lifts off slowly and floats a wide loop
            p.y = 0.11 * smooth(min(1, u / 0.3)) * smooth(min(1, (1 - u) / 0.3)) + 0.004 * sin(t * 1.5)
            pitch = 0.03 * sin(t * 1.3) * mid
            roll = -0.06 * mid
        }
        p.x = r * sin(theta)
        p.z = r * cos(theta) - r
        p.yaw = .pi / 2 + theta
        return (p, robot, car, pitch, roll)
    }

    // MARK: - Poses

    private func targetPose(for action: FigureAction, at t: Float) -> Pose {
        var p = Pose()
        let d = Float(action.duration)
        let fade = smooth(min(1, t / 0.3, max(0, d - t) / 0.3))

        switch action {
        case .dance:
            let beat = t * 2 * .pi
            p.y = 0.012 * abs(sin(beat)) * fade
            p.roll = 0.18 * sin(beat) * fade
            p.yaw = 0.35 * sin(beat * 0.5) * fade
            let up = (1.6 + 0.4 * sin(beat * 2)) * fade
            p.armOutL = up
            p.armOutR = (1.6 + 0.4 * sin(beat * 2 + .pi)) * fade
            p.leg = 0.3 * sin(beat) * fade

        case .jump:
            let hop = (t.truncatingRemainder(dividingBy: 0.8)) / 0.8
            var air: Float = 0
            var squash: Float = 0
            if hop < 0.7 {
                air = sin(.pi * hop / 0.7)
            } else {
                squash = sin(.pi * (hop - 0.7) / 0.3)
            }
            p.y = 0.07 * air
            p.stretch = 1 + 0.06 * air - 0.12 * squash
            p.armOutL = 2.2 * air
            p.armOutR = 2.2 * air

        case .run:
            let r = runRadius
            let stride = t * 18
            if t < 0.4 {
                p.yaw = (.pi / 2) * smooth(t / 0.4)
            } else if t < d - 0.4 {
                let theta = 2 * .pi * smooth((t - 0.4) / (d - 0.8))
                p.x = r * sin(theta)
                p.z = r * cos(theta) - r
                p.yaw = .pi / 2 + theta
                p.y = 0.008 * abs(sin(stride))
                p.leg = 0.7 * sin(stride)
                p.armSwing = 0.6 * sin(stride)
                p.armOutL = 0.3
                p.armOutR = 0.3
            } else {
                p.yaw = (.pi / 2) * (1 - smooth((t - (d - 0.4)) / 0.4))
            }

        case .spin:
            let k = smooth(min(t / d, 1))
            p.yaw = 2 * .pi * k
            p.y = 0.02 * sin(.pi * k)
            p.armOutL = 1.2 * sin(.pi * k)
            p.armOutR = 1.2 * sin(.pi * k)

        case .wave:
            p.armOutR = (2.6 + 0.35 * sin(t * 10)) * fade
            p.roll = 0.06 * fade
        }
        return p
    }

    private func apply(_ p: Pose) {
        motion.position = [p.x, p.y, p.z]
        motion.orientation = simd_quatf(angle: p.yaw, axis: [0, 1, 0]) * simd_quatf(angle: p.roll, axis: [0, 0, 1])
        motion.scale = [1, p.stretch, 1]
        guard let parts else { return }
        // Left arm rises toward -x (negative angle), right arm toward +x.
        parts.armL.orientation = simd_quatf(angle: -p.armOutL, axis: [0, 0, 1]) * simd_quatf(angle: p.armSwing, axis: [1, 0, 0])
        parts.armR.orientation = simd_quatf(angle: p.armOutR, axis: [0, 0, 1]) * simd_quatf(angle: -p.armSwing, axis: [1, 0, 0])
        parts.legL.orientation = simd_quatf(angle: p.leg, axis: [1, 0, 0])
        parts.legR.orientation = simd_quatf(angle: -p.leg, axis: [1, 0, 0])
    }
}

private func smooth(_ x: Float) -> Float {
    let c = min(max(x, 0), 1)
    return c * c * (3 - 2 * c)
}

private struct Pose {
    var x: Float = 0
    var y: Float = 0
    var z: Float = 0
    var yaw: Float = 0
    var roll: Float = 0
    var stretch: Float = 1
    var armOutL: Float = 0
    var armOutR: Float = 0
    var armSwing: Float = 0
    var leg: Float = 0

    func blended(toward t: Pose, amount k: Float) -> Pose {
        func mix(_ a: Float, _ b: Float) -> Float { a + (b - a) * k }
        var out = Pose()
        out.x = mix(x, t.x)
        out.y = mix(y, t.y)
        out.z = mix(z, t.z)
        // Turn the short way round so a finished spin never unwinds backwards.
        var dy = (t.yaw - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if dy > .pi { dy -= 2 * .pi }
        if dy < -.pi { dy += 2 * .pi }
        out.yaw = (yaw + dy * k).truncatingRemainder(dividingBy: 2 * .pi)
        out.roll = mix(roll, t.roll)
        out.stretch = mix(stretch, t.stretch)
        out.armOutL = mix(armOutL, t.armOutL)
        out.armOutR = mix(armOutR, t.armOutR)
        out.armSwing = mix(armSwing, t.armSwing)
        out.leg = mix(leg, t.leg)
        return out
    }
}
