import RealityKit
import Foundation

/// One animal walking around the world: the player's animal or the friend.
///
/// Hierarchy: entity (place on the ground + facing) > rig.root (the Figure Shelf figure, scaled up)
/// and carryAnchor (above the head, for carried things).
@MainActor
final class Walker {
    /// Figure Shelf figures are about 20 cm tall; here they are about 80 cm.
    static let scale: Float = 4
    /// Footprint on the ground.
    static let radius: Float = 0.32

    let entity = Entity()
    let rig = FigureRig()
    let carryAnchor = Entity()

    var walkSpeed: Float = 2.0
    /// 0 = the ground (and downstairs), 1 = upstairs in the big house.
    var level = 0
    var floorY: Float { Float(level) * Village.floorHeight }
    private(set) var yaw: Float
    private(set) var velocity: SIMD2<Float> = .zero
    private(set) var arrivedStuck = false

    var carrying: Prop?
    /// The thing it is walking to pick up (it should not push it away on the way).
    var ignoreProp: Prop?
    /// Called when it starts walking in the middle of an action, so the buttons can reset.
    var onStopActing: (@MainActor () -> Void)?

    struct Ride {
        let anchor: Entity
        let thing: Interactive
    }

    /// One step of a scripted move (hop, climb, slide).
    struct Key {
        var position: SIMD3<Float>
        var yaw: Float
        var duration: Float
        var hop: Float = 0
        /// Even speed (stairs) instead of easing in and out.
        var linear = false
    }

    private struct Script {
        var from: SIMD3<Float>
        var fromYaw: Float
        var keys: [Key]
        var index = 0
        var t: Float = 0
        var done: (@MainActor () -> Void)?
    }

    private(set) var ride: Ride?
    private var script: Script?
    private var goal: (@MainActor () -> SIMD2<Float>)?
    /// Corners to walk past on the way (around furniture, through doors).
    private var waypoints: [SIMD2<Float>] = []
    private var onArrive: (@MainActor () -> Void)?
    private var faceYaw: Float?
    private var currentSpeed: Float = 0
    private var bestDistance: Float = .infinity
    private var stuckTime: Float = 0

    init(look: Look, at p: SIMD2<Float>, yaw: Float) {
        self.yaw = yaw
        rig.root.scale = SIMD3<Float>(repeating: Self.scale)
        // The figure's tap box should not push balls around; it is only for taps.
        rig.root.collision?.filter = CollisionFilter(group: .default, mask: [])
        entity.addChild(rig.root)
        carryAnchor.position = [0, 0.95, 0]
        entity.addChild(carryAnchor)
        entity.position = [p.x, 0, p.y]
        entity.orientation = rotY(yaw)
        rig.setLook(look)
    }

    var ground: SIMD2<Float> { flat(entity.position(relativeTo: nil)) }
    var isWalking: Bool { goal != nil }
    var isBusy: Bool { script != nil }
    var isRiding: Bool { ride != nil }

    // MARK: - Commands

    func walk(to point: SIMD2<Float>, via: [SIMD2<Float>] = [], then: (@MainActor () -> Void)? = nil) {
        walk(follow: { point }, via: via, then: then)
    }

    /// Walks toward a target that may move (a rolling ball, the other animal).
    func walk(follow target: @escaping @MainActor () -> SIMD2<Float>, via: [SIMD2<Float>] = [],
              then: (@MainActor () -> Void)? = nil) {
        guard script == nil, ride == nil else { return }
        waypoints = via
        if rig.isActing {
            rig.play(nil)
            onStopActing?()
        }
        goal = target
        onArrive = then
        faceYaw = nil
        bestDistance = .infinity
        stuckTime = 0
        arrivedStuck = false
    }

    func stop() {
        goal = nil
        waypoints = []
        onArrive = nil
        rig.setWalking(false)
    }

    func face(_ yaw: Float) { faceYaw = yaw }

    /// Puts the animal down somewhere new (going to another place on the map).
    func reset(at p: SIMD2<Float>, yaw: Float) {
        script = nil
        ride = nil
        goal = nil
        waypoints = []
        onArrive = nil
        faceYaw = nil
        level = 0
        velocity = .zero
        self.yaw = yaw
        entity.position = [p.x, 0, p.y]
        entity.orientation = rotY(yaw)
        rig.setWalking(false)
    }

    func playAction(_ action: FigureAction?) {
        guard script == nil else { return }
        if ride == nil {
            goal = nil
            waypoints = []
            onArrive = nil
        }
        rig.setWalking(false)
        rig.play(action)
    }

    func hop(to p: SIMD3<Float>, yaw: Float, duration: Float = 0.45, height: Float = 0.45,
             then: (@MainActor () -> Void)? = nil) {
        run([Key(position: p, yaw: yaw, duration: duration, hop: height)], then: then)
    }

    func run(_ keys: [Key], then: (@MainActor () -> Void)? = nil) {
        guard !keys.isEmpty else { then?(); return }
        goal = nil
        waypoints = []
        onArrive = nil
        rig.setWalking(false)
        script = Script(from: entity.position(relativeTo: nil), fromYaw: yaw, keys: keys, done: then)
    }

    func sit(on anchor: Entity, thing: Interactive) {
        ride = Ride(anchor: anchor, thing: thing)
    }

    func leaveRide() -> Ride? {
        let r = ride
        ride = nil
        return r
    }

    // MARK: - Every frame

    func update(_ dt: Float, village: Village, avoid other: SIMD2<Float>? = nil) {
        defer { rig.update(deltaTime: Double(dt)) }

        if script != nil {
            stepScript(dt)
            velocity = .zero
            return
        }
        if let ride {
            entity.setPosition(ride.anchor.position(relativeTo: nil), relativeTo: nil)
            let q = ride.anchor.orientation(relativeTo: nil)
            entity.setOrientation(q, relativeTo: nil)
            let f = q.act(SIMD3<Float>(0, 0, 1))
            yaw = atan2(f.x, f.z)
            velocity = .zero
            return
        }

        let here = ground
        var next = here
        if let goal {
            if let w = waypoints.first, simd_distance(w, here) < 0.35 {
                nextWaypoint()
            }
            let target = waypoints.first ?? goal()
            let d = target - here
            let dist = simd_length(d)
            if dist < 0.1 && waypoints.isEmpty {
                arrive(stuck: false)
            } else if dist < 0.0001 {
                nextWaypoint()
            } else {
                let want = waypoints.isEmpty ? min(walkSpeed, dist * 2.5 + 0.35) : walkSpeed
                currentSpeed += (want - currentSpeed) * min(1, dt * 6)
                let dir = d / dist
                next = here + dir * min(dist, currentSpeed * dt)
                yaw = turnToward(yaw, atan2(dir.x, dir.y), dt * 9)
                rig.setWalking(true)
                if dist < bestDistance - 0.02 {
                    bestDistance = dist
                    stuckTime = 0
                } else {
                    stuckTime += dt
                    if stuckTime > 0.9 {
                        if waypoints.isEmpty { arrive(stuck: true) } else { nextWaypoint() }
                    }
                }
            }
        } else {
            currentSpeed = 0
            if let f = faceYaw {
                yaw = turnToward(yaw, f, dt * 7)
                if abs(angleDiff(f, yaw)) < 0.02 { faceYaw = nil }
            }
        }

        next = village.resolve(next, radius: Self.radius, level: level)
        if let other {
            let o = Obstacle(center: other, shape: .circle(radius: Self.radius + 0.36))   // about 1 m apart: the models are wider than the walk circle
            next = o.pushOut(next, radius: Self.radius)
        }
        velocity = (next - here) / max(dt, 0.0001)
        entity.position = [next.x, floorY, next.y]
        entity.orientation = rotY(yaw)
    }

    private func nextWaypoint() {
        if !waypoints.isEmpty { waypoints.removeFirst() }
        bestDistance = .infinity
        stuckTime = 0
    }

    private func arrive(stuck: Bool) {
        goal = nil
        waypoints = []
        arrivedStuck = stuck
        currentSpeed = 0
        rig.setWalking(false)
        let done = onArrive
        onArrive = nil
        done?()
    }

    private func stepScript(_ dt: Float) {
        guard var s = script else { return }
        s.t += dt
        var start = s.index == 0 ? s.from : s.keys[s.index - 1].position
        var startYaw = s.index == 0 ? s.fromYaw : s.keys[s.index - 1].yaw
        while s.index < s.keys.count && s.t >= s.keys[s.index].duration {
            s.t -= s.keys[s.index].duration
            start = s.keys[s.index].position
            startYaw = s.keys[s.index].yaw
            s.index += 1
        }
        if s.index >= s.keys.count {
            let last = s.keys[s.keys.count - 1]
            entity.position = last.position
            yaw = last.yaw
            entity.orientation = rotY(yaw)
            script = nil
            s.done?()
            return
        }
        let key = s.keys[s.index]
        let raw = min(1, s.t / max(key.duration, 0.001))
        let u = key.linear ? raw : smoothStep(raw)
        var p = start + (key.position - start) * u
        p.y += key.hop * sin(.pi * u)
        entity.position = p
        yaw = startYaw + angleDiff(key.yaw, startYaw) * u
        entity.orientation = rotY(yaw)
        script = s
    }
}
