import RealityKit
import UIKit

/// Snowy Hill: a big hill to climb and sled down, an ice pond to skate on, a snowman whose hat
/// changes, an igloo to go into, snowballs to carry and throw, and big snowballs that grow as
/// they roll. Snow falls gently all the time.
extension Village {
    static let hillCenter = SIMD2<Float>(0, -9)
    static let hillRadius: Float = 7
    static let hillDrop: Float = 4
    static let iceCenter = SIMD2<Float>(8.5, 4.5)
    static let iceRadius: Float = 3.0

    /// Height of the hill's snow `d` metres from its middle.
    static func hillHeight(_ d: Float) -> Float {
        max(0, -hillDrop + sqrt(max(0, hillRadius * hillRadius - d * d)))
    }

    func buildSnow() {
        start = SIMD2<Float>(0, 3.3)
        buildHill()
        buildIce()
        buildSnowman(at: [-5.5, 1.5])
        buildIgloo(at: [-11, -2.5])
        bench(id: "bench0", at: [3.4, 8.2])
        bench(id: "bench1", at: [-3.4, 8.2])
        streetLamp(id: "lamp0", at: [5.0, 1.4])
        streetLamp(id: "lamp1", at: [12.2, 7.6])

        let inside: [SIMD2<Float>] = [[-13.5, 6], [13.5, -5], [-7.5, -13.5], [8, -14], [-2, 14.5], [10, 12], [-14.5, -8]]
        for p in inside { pine(at: p, size: 1.15, snowy: true, solid: true) }
        ringOfTrees(snowy: true)

        // Snowballs to carry and throw, and two big ones that grow as they roll.
        for i in 0..<8 {
            let a = Float(i) * 0.8
            let p = SIMD2<Float>(-5.5, 1.5) + SIMD2<Float>(cos(a), sin(a)) * (1.8 + Float(i % 3) * 0.3)
            let ball = makeBall(id: "snowball\(i)", radius: 0.15, hex: 0xFFFFFF, kind: .carry, mass: 0.15)
            ball.entity.position = [p.x, 0.152, p.y]
            ball.home = ball.entity.transform
        }
        for (i, p) in [SIMD2<Float>(-2.5, -1), [3.5, -0.5]].enumerated() {
            let ball = makeBall(id: "bigball\(i)", radius: 0.32, hex: 0xFAFCFF, kind: .kick, mass: 0.7)
            ball.grows = true
            ball.entity.position = [p.x, 0.322, p.y]
            ball.home = ball.entity.transform
        }

        // Falling snow.
        var flakes: [Entity] = []
        // Unlit, so they never turn grey in the shade; a touch of blue shows against the white.
        let mesh = MeshResource.generateSphere(radius: 0.048)
        // Without tone mapping off they are dimmed to grey.
        let white = UnlitMaterial(color: UIColor(hex: 0xF4F9FF), applyPostProcessToneMap: false)
        for i in 0..<80 {
            let f = ModelEntity(mesh: mesh, materials: [white])
            let a = Float(i) * 2.399
            let r = 1 + Float((i * 37) % 80) / 10
            f.position = [start.x + r * sin(a), Float(i % 11) * 0.5, start.y + r * cos(a)]
            root.addChild(f)
            flakes.append(f)
        }
        ambient["flakes"] = flakes
    }

    // MARK: - The hill and the sled

    private func buildHill() {
        let c = Self.hillCenter
        let hill = sphere(Self.hillRadius, 0xDDE7F1, at: [c.x, -Self.hillDrop, c.y], in: root)
        Self.makeSolid(hill, .generateSphere(radius: Self.hillRadius))
        addCircle(c, 5.5)

        let sled = Interactive(id: "sled", kind: .sled, center: c)
        sled.spots = [c + SIMD2<Float>(6.7, 0.6)]
        var parts = [hill]
        // Icy steps up the right side.
        for k in 0..<6 {
            let d = 5.5 - Float(k) * 0.85
            let y = Self.hillHeight(d)
            parts.append(box([0.75, 0.12, 0.55], 0xBCD5EA, at: [c.x + d, y + 0.02, c.y], corner: 0.03, in: root))
        }
        // The sled waits at the bottom of the steps.
        let parked = makeSledModel()
        parked.position = [c.x + 6.6, 0, c.y + 1.5]
        parked.orientation = rotY(-.pi / 2)
        root.addChild(parked)
        for case let m as ModelEntity in parked.children { parts.append(m) }
        sled.parts["sled"] = parked

        // Climb up the steps, then slide down the front, toward the start.
        sled.path = [
            [c.x + 6.2, 0, c.y],
            [c.x + 4.6, Self.hillHeight(4.6), c.y],
            [c.x + 3.0, Self.hillHeight(3.0), c.y],
            [c.x + 1.4, Self.hillHeight(1.4), c.y],
            [c.x, Self.hillHeight(0.4), c.y + 0.4],
            [c.x, Self.hillHeight(1.0), c.y + 1.0],
            [c.x, Self.hillHeight(3.0), c.y + 3.0],
            [c.x, Self.hillHeight(4.5), c.y + 4.5],
            [c.x, 0.02, c.y + 5.8],
            [c.x, 0, c.y + 8.0]
        ]
        tappable(parts, .use(sled))
        interactives.append(sled)
    }

    /// A little red sled (also put under the animal while it slides).
    func makeSledModel() -> Entity {
        let g = Entity()
        box([0.55, 0.06, 0.95], 0xE94F64, at: [0, 0.14, 0], corner: 0.03, in: g)
        box([0.55, 0.18, 0.06], 0xE94F64, at: [0, 0.22, 0.46], corner: 0.03, in: g)
        for x: Float in [-0.24, 0.24] {
            box([0.04, 0.04, 1.05], 0x4A5060, at: [x, 0.03, 0.02], corner: 0.015, in: g)
            for z: Float in [-0.3, 0.3] {
                box([0.03, 0.1, 0.03], 0x4A5060, at: [x, 0.08, z], corner: 0.01, in: g)
            }
        }
        return g
    }

    // MARK: - Ice

    private func buildIce() {
        let c = Self.iceCenter, r = Self.iceRadius
        cylinder(h: 0.02, r: r + 0.25, 0xDCE6F0, at: [c.x, 0.01, c.y], in: root)
        let ice = ModelEntity(mesh: .generateCylinder(height: 0.03, radius: r),
                              materials: [SimpleMaterial(color: UIColor(hex: 0xCDEBFA), roughness: .float(0.05), isMetallic: false)])
        ice.position = [c.x, 0.02, c.y]
        root.addChild(ice)
        for i in 0..<5 {
            let a = Float(i) * 1.3
            let p = c + SIMD2<Float>(cos(a), sin(a)) * (0.6 + Float(i) * 0.4)
            let streak = box([0.8, 0.005, 0.05], 0xFFFFFF, at: [p.x, 0.037, p.y], corner: 0.002, in: root)
            streak.orientation = rotY(a * 2)
        }
        let rink = Interactive(id: "ice", kind: .ice, center: c)
        rink.standRadius = r + 0.4
        tappable([ice], .use(rink))
        interactives.append(rink)
    }

    // MARK: - Snowman

    private func buildSnowman(at p: SIMD2<Float>) {
        let layout = Layout(origin: p, yaw: yawFacing(from: p, to: start))
        let g = group(layout)
        let man = Interactive(id: "snowman", kind: .snowman, center: p)
        man.spots = [layout.world([0, 1.25])]
        let white: UInt32 = 0xFFFFFF
        var parts = [
            sphere(0.55, white, at: [0, 0.5, 0], in: g),
            sphere(0.4, white, at: [0, 1.25, 0], in: g),
            sphere(0.3, white, at: [0, 1.85, 0], in: g)
        ]
        for x: Float in [-0.1, 0.1] { sphere(0.035, 0x2E3440, at: [x, 1.93, 0.27], in: g) }
        for y: Float in [1.15, 1.32, 1.49] { sphere(0.04, 0x2E3440, at: [0, y, 0.39], in: g) }
        let nose = cone(h: 0.25, r: 0.05, 0xF28C38, at: [0, 1.84, 0.38], in: g)
        nose.orientation = rotX(.pi / 2)
        parts.append(cylinder(h: 0.1, r: 0.31, 0xE94F64, at: [0, 1.58, 0], in: g))
        parts.append(box([0.12, 0.35, 0.05], 0xE94F64, at: [0.15, 1.4, 0.3], corner: 0.02, in: g))
        for side: Float in [-1, 1] {
            let pivot = Entity()
            pivot.position = [0.36 * side, 1.35, 0]
            g.addChild(pivot)
            let arm = cylinder(h: 0.6, r: 0.025, 0x8A5A3A, at: [0.28 * side, 0.12, 0], rotation: rotZ(side * -1.1), in: pivot)
            parts.append(arm)
            man.parts[side < 0 ? "armL" : "armR"] = pivot
        }
        // Four hats; one shows at a time.
        let hats: [(UInt32, UInt32)] = [(0x2E3440, 0xE94F64), (0x5DA9E9, 0xFFFFFF), (0xFFD45C, 0xFF8FB1), (0x7FD8BE, 0xFFFFFF)]
        for (i, h) in hats.enumerated() {
            let hat = Entity()
            hat.position = [0, 2.08, 0]
            hat.isEnabled = i == 0
            g.addChild(hat)
            if i == 0 {
                parts.append(cylinder(h: 0.03, r: 0.3, h.0, at: [0, 0, 0], in: hat))
                parts.append(cylinder(h: 0.35, r: 0.19, h.0, at: [0, 0.18, 0], in: hat))
                cylinder(h: 0.06, r: 0.195, h.1, at: [0, 0.06, 0], in: hat)
            } else {
                let dome = sphere(0.23, h.0, at: [0, 0.0, 0], in: hat)
                dome.scale = [1, 0.75, 1]
                parts.append(dome)
                cylinder(h: 0.07, r: 0.235, h.1, at: [0, -0.04, 0], in: hat)
                sphere(0.08, h.1, at: [0, 0.19, 0], in: hat)
            }
            man.parts["hat\(i)"] = hat
        }
        addCircle(p, 0.55)
        tappable(parts, .use(man))
        interactives.append(man)
    }

    // MARK: - Igloo

    private func buildIgloo(at c: SIMD2<Float>) {
        let r: Float = 2.1
        let ice: UInt32 = 0xF0F6FC, line: UInt32 = 0xD5E4F1
        // A low wall of snow blocks all round, with a doorway facing the middle of the world (+x).
        let n = 14
        for i in 0..<n {
            let a = Float(i) / Float(n) * 2 * .pi
            if abs(angleDiff(a, 0)) < 0.42 { continue }
            let tangent = SIMD2<Float>(-sin(a), cos(a))
            // The two blocks beside the doorway are shorter and sit back, so the doorway is wide
            // enough to walk through.
            let byDoor = abs(angleDiff(a, 0)) < 0.5
            let away: Float = byDoor ? (angleDiff(a, 0) > 0 ? 1 : -1) * 0.17 : 0
            let p = c + SIMD2<Float>(cos(a), sin(a)) * r + tangent * away
            let yaw = -(a + .pi / 2)
            let length: Float = byDoor ? 0.6 : 0.9
            for row in 0..<2 {
                let b = box([length, 0.34, 0.32], row == 0 ? ice : line, at: [p.x, 0.17 + Float(row) * 0.35, p.y], corner: 0.06, in: root, solid: true)
                b.orientation = rotY(yaw + (row == 0 ? 0 : 0.12))
            }
            // A little longer and thicker than the blocks, so the rects overlap with no gap to slip through.
            addRect(p, half: [length / 2 + 0.1, 0.22], yaw: yaw)
        }
        // Tunnel out of the doorway: side walls (they also keep walkers in the tunnel)...
        let tx = c.x + r + 0.45
        for side: Float in [-1, 1] {
            box([1.0, 0.8, 0.22], ice, at: [tx, 0.4, c.y + side * 0.8], corner: 0.08, in: root, solid: true)
            addRect([tx, c.y + side * 0.8], half: [0.55, 0.11], yaw: 0)
        }

        // The roof: the dome, the tunnel's round top and its dark doorway. It all hides while the
        // animal is inside (the tunnel included), so the animal never vanishes under it.
        let roof = Entity()
        root.addChild(roof)
        let dome = sphere(r + 0.15, ice, at: [c.x, 0, c.y], in: roof)
        dome.scale = [1, 0.95, 1]
        let tunnel = cylinder(h: 1.1, r: 0.95, ice, at: [tx + 0.05, 0.1, c.y], rotation: rotZ(.pi / 2), in: roof)
        for k in 0..<3 {
            // Block lines on the tunnel so it reads as built from snow blocks.
            cylinder(h: 0.03, r: 0.97, line, at: [tx - 0.35 + Float(k) * 0.4, 0.1, c.y], rotation: rotZ(.pi / 2), in: roof)
        }
        let door = cylinder(h: 0.02, r: 0.62, 0x34405A, at: [tx + 0.61, 0.12, c.y], rotation: rotZ(.pi / 2), in: roof)
        door.scale = [1, 1, 1.15]
        // A soft glow over the doorway so it is easy to spot.
        cylinder(h: 0.03, r: 0.72, 0xBCD5EA, at: [tx + 0.6, 0.12, c.y], rotation: rotZ(.pi / 2), in: roof)
        tappable([dome, tunnel, door], .ground)
        tapTargets[ObjectIdentifier(dome)] = nil
        tapTargets[ObjectIdentifier(tunnel)] = nil
        tapTargets[ObjectIdentifier(door)] = nil
        // "Inside" reaches out over the tunnel too.
        var igloo = House(center: c, yaw: 0, halfX: r - 0.05, halfZ: r - 0.05, roof: roof, top: r * 0.95 + 0.3)
        igloo.annex = (center: SIMD2<Float>(r + 0.5, 0), half: SIMD2<Float>(0.65, 0.7))
        igloo.entrance = c + SIMD2<Float>(r + 1.4, 0)
        houses.append(igloo)

        // Inside: a fur rug and a lantern.
        cylinder(h: 0.02, r: 1.0, 0xC89B6D, at: [c.x - 0.3, 0.012, c.y], in: root)
        let lantern = Interactive(id: "lantern", kind: .lamp, center: c + SIMD2<Float>(-1.2, 0.8))
        lantern.spots = [c + SIMD2<Float>(-0.4, 0.4)]
        let lx = c.x - 1.2, lz = c.y + 0.8
        let base = box([0.3, 0.45, 0.3], 0x9C6B4E, at: [lx, 0.225, lz], corner: 0.04, in: root, solid: true)
        let bulb = sphere(0.1, 0xF2F2F2, at: [lx, 0.58, lz], in: root)
        let cap = cone(h: 0.12, r: 0.13, 0x4A5060, at: [lx, 0.72, lz], in: root)
        let light = PointLight()
        light.light.color = UIColor(hex: 0xFFD9A0)
        light.light.intensity = 9000
        light.light.attenuationRadius = 3.5
        light.position = [lx, 0.8, lz]
        light.isEnabled = false
        root.addChild(light)
        lantern.parts["bulb"] = bulb
        lantern.light = light
        addRect(lantern.center, half: [0.15, 0.15], yaw: 0)
        tappable([base, bulb, cap], .use(lantern))
        interactives.append(lantern)
    }
}
