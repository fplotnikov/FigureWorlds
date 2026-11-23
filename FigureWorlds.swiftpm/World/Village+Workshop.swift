import RealityKit
import UIKit

/// The Robot Workshop: a conveyor belt that carries crates into a bin, a crane with a magnet
/// that lifts metal crates over to another bin, a marble run, a big friendly robot, a wall of
/// gears, three big buttons that light lamps, and a ramp to kick balls up.
extension Village {
    func buildWorkshop() {
        start = SIMD2<Float>(0, 5)

        // Painted lines on the concrete, like a real workshop floor.
        for x: Float in [-1.6, 1.6] {
            box([0.12, 0.012, 9], 0xFFD45C, at: [x, 0.006, 8.5], corner: 0.004, in: root)
        }
        box([22, 0.012, 0.12], 0xFFD45C, at: [0, 0.006, 0.6], corner: 0.004, in: root)

        buildConveyor()
        buildCrane(at: [7, -6])
        buildMarbleRun()
        buildRobot(at: [0, -10.5])
        buildGears(at: [-12.5, 1.5])
        buildBigButtons(at: [5.2, 2.8])
        buildRamp(at: [11.5, 4])
        workbench(at: [-10.5, -10], yaw: 0.5)
        workbench(at: [12.5, -9.5], yaw: -0.6)
        streetLamp(id: "lamp0", at: [-5, 6.5])
        streetLamp(id: "lamp1", at: [8.5, 7.5])

        let inside: [SIMD2<Float>] = [[-14.5, -6], [14.5, -3], [-9.5, 13.5], [9.5, 13.5], [-15, 8]]
        for (i, p) in inside.enumerated() {
            if i % 2 == 0 { tree(at: p, size: 1.0, solid: true) } else { pine(at: p, size: 1.05, snowy: false, solid: true) }
        }
        ringOfTrees(snowy: false)

        // Wooden crates for the belt, metal ones for the magnet, balls for the ramp.
        let woods: [UInt32] = [0xD9B98F, 0xE8C9A9, 0xC89B6D]
        let crates: [SIMD3<Float>] = [[-3.8, 0.77, -2], [-2.4, 0.77, -2], [-4.2, 0.212, -0.7], [-3.4, 0.212, -0.5], [-2.6, 0.212, -0.8]]
        for (i, p) in crates.enumerated() { makeBlock(id: "crate\(i)", at: p, hex: woods[i % woods.count]) }
        makeBlock(id: "metal0", at: [9.2, 0.212, -6.3], hex: 0xA9B4C2)
        makeBlock(id: "metal1", at: [9.8, 0.212, -5.7], hex: 0x8C99A8)
        let metalBall = makeBall(id: "metalball0", radius: 0.2, hex: 0x9AA5B1, kind: .carry, mass: 0.4)
        metalBall.entity.position = [9.0, 0.202, -5.5]
        metalBall.home = metalBall.entity.transform
        for (i, b) in [(SIMD2<Float>(10.2, 0.6), UInt32(0xE94F64)), ([12.6, 0.9], 0x5DA9E9)].enumerated() {
            let ball = makeBall(id: "ball\(i)", radius: 0.3, hex: b.1, kind: .kick, mass: 0.6)
            ball.entity.position = [b.0.x, 0.302, b.0.y]
            ball.home = ball.entity.transform
        }
    }

    /// A glowing ball (lights, eyes, signs): unlit, so it always looks bright.
    @discardableResult
    func glow(_ r: Float, _ hex: UInt32, at p: SIMD3<Float>, in parent: Entity) -> ModelEntity {
        let e = ModelEntity(mesh: .generateSphere(radius: r),
                            materials: [UnlitMaterial(color: UIColor(hex: hex), applyPostProcessToneMap: false)])
        e.position = p
        parent.addChild(e)
        return e
    }

    // MARK: - Conveyor belt

    private func buildConveyor() {
        let z: Float = -2, x0: Float = -4.5, x1: Float = 2.5
        let mid = (x0 + x1) / 2, len = x1 - x0
        let belt = Interactive(id: "belt", kind: .conveyor, center: [-5.4, z])
        belt.standRadius = 0.9
        belt.path = [[x0, 0.55, z], [x1, 0.55, z]]
        var parts: [ModelEntity] = []
        parts.append(box([len, 0.1, 0.9], 0x3B4252, at: [mid, 0.5, z], corner: 0.03, in: root, solid: true))
        for s: Float in [-1, 1] {
            parts.append(box([len, 0.16, 0.06], 0xFFC83D, at: [mid, 0.63, z + s * 0.48], corner: 0.02, in: root, solid: true))
            for x in stride(from: x0 + 0.3, through: x1 - 0.2, by: 1.6) {
                box([0.1, 0.45, 0.1], 0x6B7280, at: [x, 0.225, z + s * 0.38], corner: 0.02, in: root)
            }
        }
        // Rollers at both ends, and stripes that move when the belt runs.
        for x in [x0, x1] {
            cylinder(h: 0.9, r: 0.08, 0x9AA5B1, at: [x, 0.5, z], rotation: rotX(.pi / 2), in: root)
        }
        for i in 0..<10 {
            let stripe = box([0.08, 0.012, 0.8], 0xFFD45C, at: [x0 + Float(i) * len / 10, 0.557, z], corner: 0.004, in: root)
            belt.parts["stripe\(i)"] = stripe
        }
        // The start button on a post.
        let bx = belt.center.x, bz = belt.center.y
        parts.append(cylinder(h: 0.9, r: 0.08, 0x4A5060, at: [bx, 0.45, bz], in: root))
        parts.append(box([0.4, 0.12, 0.4], 0x4A5060, at: [bx, 0.95, bz], corner: 0.04, in: root))
        let cap = cylinder(h: 0.1, r: 0.15, 0x7DCB5A, at: [bx, 1.06, bz], in: root)
        parts.append(cap)
        belt.parts["cap"] = cap
        belt.parts["lamp"] = glow(0.07, 0x5A6170, at: [bx, 1.25, bz], in: root)
        addRect([mid, z], half: [len / 2 + 0.05, 0.5], yaw: 0)
        addCircle([bx, bz], 0.25)
        tappable(parts, .use(belt))
        interactives.append(belt)

        // The bin at the end catches what falls off.
        let c = SIMD2<Float>(3.2, z)
        box([1.3, 0.05, 1.3], 0x5DA9E9, at: [c.x, 0.025, c.y], corner: 0.01, in: root, solid: true)
        for s: Float in [-1, 1] {
            // The side under the belt's end is low, so crates tip in instead of catching on it.
            let h: Float = s < 0 ? 0.22 : 0.4
            box([0.06, h, 1.3], 0x5DA9E9, at: [c.x + s * 0.65, h / 2, c.y], corner: 0.02, in: root, solid: true)
            box([1.3, 0.4, 0.06], 0x5DA9E9, at: [c.x, 0.2, c.y + s * 0.65], corner: 0.02, in: root, solid: true)
        }
        addRect(c, half: [0.68, 0.68], yaw: 0)
    }

    // MARK: - Crane with a magnet

    private func buildCrane(at c: SIMD2<Float>) {
        let crane = Interactive(id: "crane", kind: .crane, center: c + SIMD2<Float>(0, 1.5))
        crane.spots = [c + SIMD2<Float>(0, 2.3)]
        let yellow: UInt32 = 0xFFC83D
        var parts: [ModelEntity] = []
        parts.append(box([1.0, 0.3, 1.0], 0x4A5060, at: [c.x, 0.15, c.y], corner: 0.05, in: root, solid: true))
        parts.append(cylinder(h: 3.2, r: 0.16, yellow, at: [c.x, 1.75, c.y], in: root, solid: true))
        parts.append(box([0.6, 0.5, 0.6], yellow, at: [c.x, 3.55, c.y], corner: 0.08, in: root))
        let pivot = Entity()
        pivot.position = [c.x, 3.55, c.y]
        root.addChild(pivot)
        parts.append(box([3.6, 0.18, 0.22], yellow, at: [0.8, 0.3, 0], corner: 0.04, in: pivot))
        parts.append(box([0.5, 0.4, 0.4], 0x4A5060, at: [-0.9, 0.15, 0], corner: 0.05, in: pivot))
        let hook = Entity()
        hook.position = [2.4, 0.2, 0]
        pivot.addChild(hook)
        let cable = cylinder(h: 1, r: 0.02, 0x2E3440, at: [0, -0.5, 0], in: hook)
        let magnet = Entity()
        magnet.position = [0, -1, 0]
        hook.addChild(magnet)
        cylinder(h: 0.14, r: 0.32, 0x6B7280, at: [0, 0, 0], in: magnet)
        cylinder(h: 0.06, r: 0.33, 0xE94F64, at: [0, 0.08, 0], in: magnet)
        crane.parts = ["pivot": pivot, "cable": cable, "magnet": magnet]

        // The control box with a big red button.
        let k = crane.center
        parts.append(box([0.6, 0.8, 0.4], 0x4A5060, at: [k.x, 0.4, k.y], corner: 0.05, in: root))
        let cap = cylinder(h: 0.1, r: 0.14, 0xE94F64, at: [k.x, 0.85, k.y], in: root)
        parts.append(cap)
        crane.parts["cap"] = cap

        // Where the magnet picks up (yellow pad) and where it drops (blue bin).
        cylinder(h: 0.012, r: 0.95, 0xFFD45C, at: [c.x + 2.4, 0.006, c.y], in: root)
        let b = SIMD2<Float>(c.x - 2.4, c.y)
        box([1.3, 0.05, 1.3], 0x7FD8BE, at: [b.x, 0.025, b.y], corner: 0.01, in: root, solid: true)
        for s: Float in [-1, 1] {
            box([0.06, 0.4, 1.3], 0x7FD8BE, at: [b.x + s * 0.65, 0.2, b.y], corner: 0.02, in: root, solid: true)
            box([1.3, 0.4, 0.06], 0x7FD8BE, at: [b.x, 0.2, b.y + s * 0.65], corner: 0.02, in: root, solid: true)
        }
        addRect(b, half: [0.68, 0.68], yaw: 0)
        let o = addCircle(c, 0.55)
        obstacles[o].view = Obstacle.ViewBlock(crown: 0.4, crownBottom: 3.2, top: 3.9)
        addRect(k, half: [0.32, 0.22], yaw: 0)
        tappable(parts, .use(crane))
        interactives.append(crane)
    }

    // MARK: - Marble run

    private func buildMarbleRun() {
        let run = Interactive(id: "marbles", kind: .marbleRun, center: [-5.0, -4.4])
        run.spots = [[-5.0, -3.6]]
        let zr: Float = -6.0, zt: Float = -5.6
        run.path = [
            [-8.0, 0.33, zt], [-8.0, 2.6, zt], [-7.8, 2.5, zr], [-6.0, 2.1, zr], [-6.0, 1.8, zr],
            [-7.8, 1.4, zr], [-7.8, 1.1, zr], [-6.0, 0.7, zr], [-5.7, 0.33, zt], [-8.0, 0.33, zt]
        ]
        var parts: [ModelEntity] = []
        let wood: UInt32 = 0xC89B6D
        // Posts and the clear lift tube.
        for x: Float in [-8.3, -5.7] {
            parts.append(box([0.12, 2.8, 0.12], wood, at: [x, 1.4, zr - 0.2], corner: 0.03, in: root))
        }
        var clear = SimpleMaterial(color: UIColor(hex: 0xBFE6FF), roughness: .float(0.1), isMetallic: false)
        clear.color = .init(tint: UIColor(hex: 0xBFE6FF).withAlphaComponent(0.35))
        let tube = ModelEntity(mesh: .generateCylinder(height: 2.35, radius: 0.15), materials: [clear])
        tube.position = [-8.0, 1.5, zt]
        root.addChild(tube)
        parts.append(tube)
        // Ramps (a marble is 0.1 m round, so each ramp sits just under its path).
        let colors: [UInt32] = [0xE94F64, 0xFFD45C, 0x5DA9E9]
        for (k, pair) in [(2, 3), (4, 5), (6, 7)].enumerated() {
            let a = run.path[pair.0], b = run.path[pair.1]
            let d = b - a
            let len = simd_length(SIMD2<Float>(d.x, d.y))
            let mid = (a + b) / 2 - SIMD3<Float>(0, 0.12, 0)
            let ramp = box([len + 0.3, 0.04, 0.24], colors[k], at: mid, corner: 0.01, in: root)
            ramp.orientation = rotZ(atan2(d.y, d.x))
            parts.append(ramp)
            for s: Float in [-1, 1] {
                let rail = box([len + 0.3, 0.08, 0.03], colors[k], at: mid + SIMD3<Float>(0, 0.05, s * 0.12), corner: 0.01, in: root)
                rail.orientation = rotZ(atan2(d.y, d.x))
            }
        }
        // The trough back to the lift.
        parts.append(box([2.6, 0.06, 0.26], 0x7FD8BE, at: [-6.85, 0.2, zt], corner: 0.02, in: root))
        let marble = ModelEntity(mesh: .generateSphere(radius: 0.1),
                                 materials: [SimpleMaterial(color: UIColor(hex: 0xC86FC9), roughness: .float(0.15), isMetallic: true)])
        marble.position = run.path[0]
        root.addChild(marble)
        run.parts["marble"] = marble
        run.time = 100
        // The button.
        let bp = run.center
        parts.append(cylinder(h: 0.9, r: 0.08, 0x4A5060, at: [bp.x, 0.45, bp.y], in: root))
        parts.append(box([0.4, 0.12, 0.4], 0x4A5060, at: [bp.x, 0.95, bp.y], corner: 0.04, in: root))
        let cap = cylinder(h: 0.1, r: 0.15, 0xC86FC9, at: [bp.x, 1.06, bp.y], in: root)
        parts.append(cap)
        run.parts["cap"] = cap
        addRect([-6.9, -5.8], half: [1.5, 0.5], yaw: 0)
        addCircle(bp, 0.25)
        tappable(parts, .use(run))
        interactives.append(run)
    }

    // MARK: - The robot

    private func buildRobot(at p: SIMD2<Float>) {
        let layout = Layout(origin: p, yaw: yawFacing(from: p, to: start))
        let g = group(layout)
        let robot = Interactive(id: "robot", kind: .robot, center: p)
        robot.spots = [layout.world([0, 1.6])]
        let blue: UInt32 = 0x8FB8DE, dark: UInt32 = 0x4A5060
        var parts: [ModelEntity] = []
        for x: Float in [-0.3, 0.3] {
            parts.append(box([0.36, 0.2, 0.5], dark, at: [x, 0.1, 0.05], corner: 0.06, in: g))
            parts.append(cylinder(h: 0.65, r: 0.12, 0x9AA5B1, at: [x, 0.5, 0], in: g))
        }
        let body = Entity()
        g.addChild(body)
        parts.append(box([1.1, 1.0, 0.75], blue, at: [0, 1.3, 0], corner: 0.15, in: body))
        box([0.6, 0.4, 0.03], 0x3B4252, at: [0, 1.35, 0.38], corner: 0.04, in: body)
        for i in 0..<3 {
            robot.parts["chest\(i)"] = glow(0.06, 0x5A6170, at: [Float(i - 1) * 0.17, 1.35, 0.41], in: body)
        }
        let head = Entity()
        head.position = [0, 1.82, 0]
        body.addChild(head)
        parts.append(box([0.8, 0.6, 0.65], blue, at: [0, 0.3, 0], corner: 0.14, in: head))
        for x: Float in [-0.18, 0.18] {
            glow(0.09, 0x7FF0FF, at: [x, 0.36, 0.32], in: head)
            let ear = cylinder(h: 0.08, r: 0.13, 0xFFC83D, at: [x > 0 ? 0.42 : -0.42, 0.3, 0], rotation: rotZ(.pi / 2), in: head)
            parts.append(ear)
        }
        box([0.3, 0.05, 0.02], 0x3B4252, at: [0, 0.16, 0.33], corner: 0.01, in: head)
        cylinder(h: 0.3, r: 0.025, 0x9AA5B1, at: [0, 0.75, 0], in: head)
        robot.parts["bulb"] = glow(0.07, 0xE94F64, at: [0, 0.93, 0], in: head)
        for side: Float in [-1, 1] {
            let arm = Entity()
            arm.position = [0.66 * side, 1.7, 0]
            body.addChild(arm)
            parts.append(cylinder(h: 0.8, r: 0.1, 0x9AA5B1, at: [0, -0.4, 0], in: arm))
            parts.append(sphere(0.15, 0xFFC83D, at: [0, -0.85, 0], in: arm))
            robot.parts[side < 0 ? "armL" : "armR"] = arm
        }
        robot.parts["body"] = body
        robot.parts["head"] = head
        let o = addCircle(p, 0.75)
        obstacles[o].view = Obstacle.ViewBlock(crown: 0.8, crownBottom: 0, top: 2.9)
        tappable(parts, .use(robot))
        interactives.append(robot)
    }

    // MARK: - Gears

    private func buildGears(at p: SIMD2<Float>) {
        let layout = Layout(origin: p, yaw: yawFacing(from: p, to: .zero))
        let g = group(layout)
        let gears = Interactive(id: "gears", kind: .gears, center: p)
        gears.spots = [layout.world([0, 1.3])]
        var parts: [ModelEntity] = []
        parts.append(box([3.6, 2.6, 0.15], 0xC89B6D, at: [0, 1.5, 0], corner: 0.05, in: g))
        for x: Float in [-1.6, 1.6] { box([0.15, 0.3, 0.6], 0x8A5A3A, at: [x, 0.15, 0], corner: 0.03, in: g) }
        let radii: [Float] = [0.55, 0.38, 0.5, 0.32]
        let angles: [Float] = [0, 0.6, -0.5, 0.7]
        let colors: [UInt32] = [0xE94F64, 0xFFD45C, 0x5DA9E9, 0x7DCB5A]
        var c = SIMD2<Float>(-1.0, 1.2)
        for (i, r) in radii.enumerated() {
            if i > 0 {
                let d = radii[i - 1] + r + 0.07
                c += SIMD2<Float>(cos(angles[i]), sin(angles[i])) * d
            }
            let pivot = Entity()
            pivot.position = [c.x, c.y, 0.12]
            g.addChild(pivot)
            parts.append(cylinder(h: 0.08, r: r, colors[i], at: .zero, rotation: rotX(.pi / 2), in: pivot))
            cylinder(h: 0.12, r: 0.08, 0x4A5060, at: .zero, rotation: rotX(.pi / 2), in: pivot)
            let teeth = max(8, Int(r * 22))
            for k in 0..<teeth {
                let a = Float(k) / Float(teeth) * 2 * .pi
                let tooth = box([0.09, 0.1, 0.08], colors[i], at: [(r + 0.03) * sin(a), (r + 0.03) * cos(a), 0], corner: 0.015, in: pivot)
                tooth.orientation = rotZ(-a)
            }
            if i == 0 { box([0.08, 0.08, 0.25], 0x4A5060, at: [0, r * 0.6, 0.12], corner: 0.02, in: pivot) }
            gears.parts["gear\(i)"] = pivot
        }
        gears.numbers = radii
        addRect(p, half: [1.85, 0.3], yaw: layout.yaw)
        tappable(parts, .use(gears))
        interactives.append(gears)
    }

    // MARK: - Big buttons and lamps

    private func buildBigButtons(at p: SIMD2<Float>) {
        let layout = Layout(origin: p, yaw: yawFacing(from: p, to: start))
        let g = group(layout)
        let console = box([2.4, 0.7, 0.6], 0x6B7280, at: [0, 0.35, 0], corner: 0.08, in: g)
        let colors: [UInt32] = [0xE94F64, 0xFFD45C, 0x5DA9E9]
        for (i, hex) in colors.enumerated() {
            let x = Float(i - 1) * 0.75
            let b = Interactive(id: "button\(i)", kind: .bigButton, center: layout.world([x, 0]))
            b.spots = [layout.world([x, 0.95])]
            b.numbers = [Float(hex)]
            cylinder(h: 0.06, r: 0.24, 0x3B4252, at: [x, 0.73, 0], in: g)
            let cap = cylinder(h: 0.12, r: 0.19, hex, at: [x, 0.8, 0], in: g)
            let pole = cylinder(h: 2.2, r: 0.05, 0x4A5060, at: [x, 1.1, -0.9], in: g)
            let bulb = sphere(0.24, 0xF2F2F2, at: [x, 2.35, -0.9], in: g)
            let light = PointLight()
            light.light.color = UIColor(hex: hex)
            light.light.intensity = 9000
            light.light.attenuationRadius = 4
            light.position = [x, 2.2, -0.6]
            light.isEnabled = false
            g.addChild(light)
            b.parts["cap"] = cap
            b.parts["bulb"] = bulb
            b.light = light
            let o = addCircle(layout.world([x, -0.9]), 0.12)
            obstacles[o].view = Obstacle.ViewBlock(crown: 0.3, crownBottom: 2.05, top: 2.65)
            tappable([cap, pole, bulb], .use(b))
            interactives.append(b)
        }
        tappable([console], .ground)
        addRect(p, half: [1.25, 0.32], yaw: layout.yaw)
    }

    // MARK: - Ramp and workbenches

    private func buildRamp(at p: SIMD2<Float>) {
        let ramp = box([1.8, 0.12, 3.2], 0xD9AE7E, at: [p.x, 0.36, p.y], corner: 0.03, in: root, solid: true)
        ramp.orientation = rotX(0.22)
        for s: Float in [-1, 1] {
            let rail = box([0.06, 0.2, 3.2], 0xE94F64, at: [p.x + s * 0.9, 0.46, p.y], corner: 0.02, in: root, solid: true)
            rail.orientation = rotX(0.22)
        }
        box([1.8, 0.7, 0.12], 0xC89B6D, at: [p.x, 0.35, p.y - 1.55], corner: 0.03, in: root)
        addRect(p, half: [0.95, 1.6], yaw: 0)
    }

    private func workbench(at p: SIMD2<Float>, yaw: Float) {
        let g = group(Layout(origin: p, yaw: yaw))
        box([2.0, 0.1, 0.9], 0xC89B6D, at: [0, 0.85, 0], corner: 0.03, in: g)
        for x: Float in [-0.9, 0.9] {
            for z: Float in [-0.38, 0.38] { box([0.1, 0.8, 0.1], 0x8A5A3A, at: [x, 0.4, z], corner: 0.02, in: g) }
        }
        // A hammer, a wrench and a few bolts.
        cylinder(h: 0.5, r: 0.03, 0xC89B6D, at: [-0.5, 0.93, 0], rotation: rotZ(.pi / 2), in: g)
        box([0.1, 0.1, 0.25], 0x6B7280, at: [-0.27, 0.95, 0], corner: 0.02, in: g)
        box([0.5, 0.03, 0.08], 0x9AA5B1, at: [0.3, 0.92, 0.15], corner: 0.01, in: g)
        for i in 0..<4 { cylinder(h: 0.05, r: 0.04, 0xFFC83D, at: [0.2 + Float(i) * 0.12, 0.93, -0.2], in: g) }
        addRect(p, half: [1.05, 0.5], yaw: yaw)
    }
}
