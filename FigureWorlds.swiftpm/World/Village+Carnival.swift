import RealityKit
import UIKit

/// The Night Carnival: a carousel with bobbing horses, a little ferris wheel, a light board with
/// three big buttons (chasing lights, star signs, fireworks), a duck tub, a popcorn cart and
/// striped tents, under a calm evening sky with stars and a moon.
extension Village {
    static let carouselCenter = SIMD2<Float>(0, -3.5)
    static let ferrisCenter = SIMD2<Float>(-9.5, -6.5)
    static let ferrisHub: Float = 3.4
    static let ferrisRadius: Float = 2.6

    func buildCarnival() {
        start = SIMD2<Float>(0, 5.5)
        buildSky()
        buildCarousel()
        buildFerris()
        buildLightBoard(at: [5.6, 2.2])
        buildDuckTub(at: [8.5, -6.5])
        buildPopcorn(at: [-5.8, 2.0])
        for (i, p) in [SIMD2<Float>(-4.5, 8.5), [4.5, 8.5]].enumerated() { starSign(index: i, at: p) }
        for (i, t) in [(SIMD2<Float>(12.5, -1.5), UInt32(0xE94F64)), ([-13, 3], 0x5DA9E9), ([11.5, 9.5], 0xC86FC9), ([-11, 10.5], 0xFFD45C)].enumerated() {
            tent(at: t.0, color: t.1, index: i)
        }
        for (i, p) in [SIMD2<Float>(-3, 10.5), [3, 10.5], [-8.5, -1.5], [6.5, -10.5]].enumerated() {
            streetLamp(id: "lamp\(i)", at: p)
            // It's evening: the lamps start lit.
            if let lamp = interactives.last, let bulb = lamp.parts["bulb"] as? ModelEntity {
                lamp.isOn = true
                bulb.model?.materials = [UnlitMaterial(color: UIColor(hex: 0xFFE08A))]
            }
        }
        let inside: [SIMD2<Float>] = [[-14.5, -7], [14.5, 4], [-6, 14.5], [8, 14], [14, -10]]
        for p in inside { tree(at: p, size: 1.0, solid: true) }
        ringOfTrees(snowy: false)

        // Balls to kick around.
        for (i, b) in [(SIMD2<Float>(-3, 4), UInt32(0xFFD45C)), ([3.2, 4.6], 0xFF8FB1), ([-7, -10], 0x7FD8BE)].enumerated() {
            let ball = makeBall(id: "ball\(i)", radius: 0.3, hex: b.1, kind: .kick, mass: 0.6)
            ball.entity.position = [b.0.x, 0.302, b.0.y]
            ball.home = ball.entity.transform
        }
    }

    // MARK: - Sky

    private func buildSky() {
        var seed: UInt32 = 77
        func rnd() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(seed >> 8) / Float(1 << 24)
        }
        let mesh = MeshResource.generateSphere(radius: 0.18)
        let white = UnlitMaterial(color: UIColor(hex: 0xFFF8E0), applyPostProcessToneMap: false)
        for _ in 0..<70 {
            let a = rnd() * 2 * .pi
            let up = 0.25 + rnd() * 0.9
            let r: Float = 42
            let star = ModelEntity(mesh: mesh, materials: [white])
            star.position = [r * cos(up) * sin(a), 6 + r * sin(up) * 0.7, r * cos(up) * cos(a)]
            star.scale = SIMD3<Float>(repeating: 0.6 + rnd() * 0.9)
            root.addChild(star)
        }
        glow(2.4, 0xFFF4C8, at: [-18, 22, -34], in: root)
    }

    // MARK: - Carousel

    private func buildCarousel() {
        let p = Self.carouselCenter
        let m = Interactive(id: "carousel", kind: .merry, center: p)
        m.standRadius = 3.25
        m.ringRadius = 1.85
        m.spinSpeed = 0.75
        let g = group(Layout(origin: p, yaw: 0))
        var parts: [ModelEntity] = []
        parts.append(cylinder(h: 0.25, r: 2.75, 0xF4E3C1, at: [0, 0.125, 0], in: g))
        let platform = Entity()
        platform.position = [0, 0.25, 0]
        g.addChild(platform)
        parts.append(cylinder(h: 0.12, r: 2.55, 0xFF8FB1, at: [0, 0.06, 0], in: platform))
        parts.append(cylinder(h: 3.2, r: 0.32, 0xFFD45C, at: [0, 1.6, 0], in: platform))
        // A striped canopy (two cones) with lights round the edge.
        parts.append(cone(h: 1.1, r: 2.95, 0xE94F64, at: [0, 3.75, 0], in: platform))
        cone(h: 0.75, r: 2.0, 0xFFFFFF, at: [0, 4.05, 0], in: platform)
        glow(0.16, 0xFFD45C, at: [0, 4.5, 0], in: platform)
        cylinder(h: 0.3, r: 2.95, 0xFFFFFF, at: [0, 3.15, 0], in: platform)
        for i in 0..<16 {
            let a = Float(i) / 16 * 2 * .pi
            let hex: UInt32 = i % 2 == 0 ? 0xFFE08A : 0xFF8FB1
            m.parts["light\(i)"] = glow(0.07, hex, at: [3.0 * sin(a), 3.0, 3.0 * cos(a)], in: platform)
        }
        let horseColors: [UInt32] = [0xFFFFFF, 0xFFD45C, 0x8ED3F5, 0xFFB7C6, 0xC6E6A8, 0xD9C2F0]
        for i in 0..<6 {
            let a = Float(i) / 6 * 2 * .pi
            let x = m.ringRadius * sin(a), z = m.ringRadius * cos(a)
            cylinder(h: 3.0, r: 0.03, 0xFFD45C, at: [x, 1.55, z], in: platform)
            let horse = Entity()
            horse.position = [x, 0.6, z]
            horse.orientation = rotY(a + .pi / 2)   // facing the way it goes round
            platform.addChild(horse)
            let c = horseColors[i]
            let body = sphere(0.22, c, at: [0, 0.35, 0], in: horse)
            body.scale = [0.8, 0.85, 1.6]
            parts.append(body)
            let neck = cylinder(h: 0.32, r: 0.08, c, at: [0, 0.55, 0.28], rotation: rotX(0.5), in: horse)
            parts.append(neck)
            let head = sphere(0.13, c, at: [0, 0.72, 0.42], in: horse)
            head.scale = [0.8, 0.9, 1.3]
            sphere(0.06, 0xE94F64, at: [0, 0.62, 0.2], in: horse)   // mane bow
            for (lx, lz) in [(Float(-0.09), Float(0.2)), (0.09, 0.2), (-0.09, -0.2), (0.09, -0.2)] {
                cylinder(h: 0.32, r: 0.03, c, at: [lx, 0.14, lz], in: horse)
            }
            box([0.24, 0.04, 0.26], 0xE94F64, at: [0, 0.53, -0.02], corner: 0.015, in: horse)
            let saddle = Entity()
            saddle.position = [0, 0.48, -0.02]
            horse.addChild(saddle)
            m.parts["horse\(i)"] = horse
            m.parts["saddle\(i)"] = saddle
        }
        m.parts["platform"] = platform
        let o = addCircle(p, 2.8)
        obstacles[o].view = Obstacle.ViewBlock(crown: 3.0, crownBottom: 2.9, top: 4.6, trunk: 0.45)
        tappable(parts, .use(m))
        interactives.append(m)
    }

    // MARK: - Ferris wheel

    private func buildFerris() {
        let p = Self.ferrisCenter
        let layout = Layout(origin: p, yaw: yawFacing(from: p, to: start))
        let g = group(layout)
        let wheel = Interactive(id: "ferris", kind: .ferris, center: p)
        wheel.spots = [layout.world([0, 1.7])]
        let hub = Self.ferrisHub, r = Self.ferrisRadius
        var parts: [ModelEntity] = []
        // Legs (an A-frame on each side) and the step to get on.
        for zs: Float in [-0.55, 0.55] {
            for xs: Float in [-1, 1] {
                let leg = cylinder(h: 3.7, r: 0.07, 0x9AA5B1, at: [xs * 0.75, hub / 2, zs], rotation: rotZ(xs * 0.24), in: g)
                parts.append(leg)
            }
        }
        cylinder(h: 1.3, r: 0.1, 0x9AA5B1, at: [0, hub, 0], rotation: rotX(.pi / 2), in: g)
        box([1.6, 0.3, 1.2], 0xF4E3C1, at: [0, 0.15, 0.9], corner: 0.05, in: g)
        let pivot = Entity()
        pivot.position = [0, hub, 0]
        g.addChild(pivot)
        let spokeColors: [UInt32] = [0xFFFFFF, 0xFF8FB1]
        for i in 0..<12 {
            let a = Float(i) / 12 * 2 * .pi
            let spoke = box([0.05, r, 0.05], spokeColors[i % 2], at: [0.5 * r * sin(a), -0.5 * r * cos(a), 0], corner: 0.01, in: pivot)
            spoke.orientation = rotZ(a)
            parts.append(spoke)
        }
        let seg = 2 * r * sin(.pi / 24)
        for i in 0..<24 {
            let a = (Float(i) + 0.5) / 24 * 2 * .pi
            let rim = box([seg + 0.02, 0.08, 0.08], 0xE94F64, at: [r * sin(a), -r * cos(a), 0], corner: 0.02, in: pivot)
            rim.orientation = rotZ(a)
            parts.append(rim)
            wheel.parts["light\(i)"] = glow(0.06, i % 2 == 0 ? 0xFFE08A : 0x8ED3F5, at: [(r + 0.08) * sin(a), -(r + 0.08) * cos(a), 0.06], in: pivot)
        }
        // Gondolas hang from the rim and stay upright (placed every frame).
        let cups: [UInt32] = [0xFFD45C, 0x5DA9E9, 0x7DCB5A, 0xC86FC9, 0xFF9A3C, 0x7FD8BE]
        for i in 0..<6 {
            let gondola = Entity()
            g.addChild(gondola)
            parts.append(box([0.85, 0.45, 0.75], cups[i], at: [0, -0.55, 0], corner: 0.1, in: gondola))
            box([0.9, 0.05, 0.8], 0xFFFFFF, at: [0, 0.05, 0], corner: 0.02, in: gondola)
            cylinder(h: 0.35, r: 0.025, 0x9AA5B1, at: [0, -0.15, 0], in: gondola)
            if i == 0 {
                let seat = Entity()
                seat.position = [0, -0.6, 0]
                gondola.addChild(seat)
                wheel.seat = seat
            }
            wheel.parts["gondola\(i)"] = gondola
        }
        wheel.parts["pivot"] = pivot
        Self.placeGondolas(wheel)
        addRect(layout.world([0, 0.2]), half: [1.1, 0.75], yaw: layout.yaw)
        tappable(parts, .use(wheel))
        interactives.append(wheel)
    }

    /// Turns the wheel to its phase and hangs each gondola at its place on the rim.
    static func placeGondolas(_ wheel: Interactive) {
        let hub = ferrisHub, r = ferrisRadius
        wheel.parts["pivot"]?.orientation = rotZ(wheel.phase)
        for i in 0..<6 {
            let a = wheel.phase + Float(i) / 6 * 2 * .pi
            wheel.parts["gondola\(i)"]?.position = [r * sin(a), hub - r * cos(a), 0]
        }
    }

    // MARK: - Light board, signs, tents

    private func buildLightBoard(at p: SIMD2<Float>) {
        let layout = Layout(origin: p, yaw: yawFacing(from: p, to: start))
        let g = group(layout)
        let console = box([2.4, 0.75, 0.6], 0x5A4A8A, at: [0, 0.375, 0], corner: 0.1, in: g)
        tappable([console], .ground)
        addRect(p, half: [1.25, 0.32], yaw: layout.yaw)
        let colors: [UInt32] = [0xFF8FB1, 0xFFD45C, 0x8ED3F5]
        var buttons: [Interactive] = []
        for (i, hex) in colors.enumerated() {
            let x = Float(i - 1) * 0.75
            let b = Interactive(id: "light\(i)", kind: .lightButton, center: layout.world([x, 0]))
            b.spots = [layout.world([x, 0.95])]
            b.numbers = [Float(i)]
            cylinder(h: 0.06, r: 0.24, 0x2E3440, at: [x, 0.78, 0], in: g)
            let cap = cylinder(h: 0.12, r: 0.19, hex, at: [x, 0.85, 0], in: g)
            b.parts["cap"] = cap
            tappable([cap], .use(b))
            interactives.append(b)
            buttons.append(b)
        }
        // Button 1: strings of lights from pole to pole round the carousel.
        let c = Self.carouselCenter
        let poles = 8
        var n = 0
        for k in 0..<poles {
            let a0 = (Float(k) + 0.5) / Float(poles) * 2 * .pi
            let a1 = (Float(k) + 1.5) / Float(poles) * 2 * .pi
            let p0 = c + SIMD2<Float>(sin(a0), cos(a0)) * 4.4
            let p1 = c + SIMD2<Float>(sin(a1), cos(a1)) * 4.4
            cylinder(h: 2.6, r: 0.05, 0x4A5060, at: [p0.x, 1.3, p0.y], in: root)
            let o = addCircle(p0, 0.12)
            obstacles[o].view = Obstacle.ViewBlock(crown: 0.2, crownBottom: 2.4, top: 2.7)
            for j in 1..<8 {
                let u = Float(j) / 8
                let q = p0 + (p1 - p0) * u
                let y = 2.55 - 0.45 * sin(.pi * u)
                buttons[0].parts["bulb\(n)"] = glow(0.07, 0xFFE8B0, at: [q.x, y, q.y], in: root)
                n += 1
            }
        }
        buttons[0].numbers.append(Float(n))
    }

    /// A star on a post at the gate: it lights up from the light board's yellow button.
    private func starSign(index: Int, at p: SIMD2<Float>) {
        let g = group(Layout(origin: p, yaw: yawFacing(from: p, to: start)))
        cylinder(h: 2.6, r: 0.07, 0x4A5060, at: [0, 1.3, 0], in: g)
        let star = Entity()
        star.position = [0, 3.0, 0]
        g.addChild(star)
        for k in 0..<5 {
            let a = Float(k) / 5 * 2 * .pi
            let ray = box([0.16, 0.5, 0.06], 0xD8D2C0, at: [0.25 * sin(a), 0.25 * cos(a), 0], corner: 0.03, in: star)
            ray.orientation = rotZ(-a)
            ray.name = "ray"
        }
        let middle = sphere(0.2, 0xD8D2C0, at: .zero, in: star)
        middle.scale = [1, 1, 0.3]
        middle.name = "ray"
        addCircle(p, 0.15)
        ambient["star\(index)"] = [star]
    }

    private func tent(at p: SIMD2<Float>, color: UInt32, index: Int) {
        let g = group(Layout(origin: p, yaw: Float(index) * 0.7))
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi
            let stripe = box([0.95, 1.4, 0.06], k % 2 == 0 ? color : 0xFFFFFF, at: [1.15 * sin(a), 0.7, 1.15 * cos(a)], corner: 0.02, in: g)
            stripe.orientation = rotY(a)
        }
        cone(h: 1.3, r: 1.55, color, at: [0, 2.05, 0], in: g)
        glow(0.1, 0xFFE08A, at: [0, 2.75, 0], in: g)
        cylinder(h: 0.5, r: 0.02, 0x4A5060, at: [0, 2.95, 0], in: g)
        box([0.3, 0.2, 0.02], 0xFFD45C, at: [0.15, 3.1, 0], corner: 0.01, in: g)
        addCircle(p, 1.4)
    }

    // MARK: - Duck tub and popcorn

    private func buildDuckTub(at p: SIMD2<Float>) {
        cylinder(h: 0.5, r: 1.35, 0x5DA9E9, at: [p.x, 0.25, p.y], in: root)
        cylinder(h: 0.06, r: 1.42, 0xFFFFFF, at: [p.x, 0.5, p.y], in: root)
        let water = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 1.25), materials: [Self.water()])
        water.position = [p.x, 0.46, p.y]
        root.addChild(water)
        addCircle(p, 1.4)
        let colors: [UInt32] = [0xFFD45C, 0xFF8FB1, 0x8ED3F5, 0xFFD45C]
        for i in 0..<4 {
            let d = Interactive(id: "duck\(i)", kind: .duck, center: p)
            d.fromAfar = true
            d.phase = Float(i) * .pi / 2
            d.orbit = [0.8, 0.8]
            d.floatY = 0.42
            let g = Entity()
            root.addChild(g)
            let body = sphere(0.13, colors[i], at: [0, 0.09, 0], in: g)
            body.scale = [1, 0.8, 1.3]
            let head = sphere(0.08, colors[i], at: [0, 0.23, 0.12], in: g)
            box([0.06, 0.025, 0.07], 0xF28C38, at: [0, 0.22, 0.21], corner: 0.01, in: g)
            sphere(0.015, 0x2E3440, at: [0.045, 0.26, 0.17], in: g)
            sphere(0.015, 0x2E3440, at: [-0.045, 0.26, 0.17], in: g)
            d.parts["duck"] = g
            tappable([body, head], .use(d))
            interactives.append(d)
        }
    }

    private func buildPopcorn(at p: SIMD2<Float>) {
        let layout = Layout(origin: p, yaw: yawFacing(from: p, to: start))
        let g = group(layout)
        let cart = Interactive(id: "popcorn", kind: .popcorn, center: p)
        cart.spots = [layout.world([0, 1.0])]
        var parts: [ModelEntity] = []
        parts.append(box([1.1, 0.7, 0.7], 0xE94F64, at: [0, 0.55, 0], corner: 0.06, in: g))
        box([1.12, 0.12, 0.72], 0xFFFFFF, at: [0, 0.75, 0], corner: 0.03, in: g)
        for x: Float in [-0.45, 0.45] {
            cylinder(h: 0.06, r: 0.2, 0x3B4252, at: [x, 0.2, 0.36], rotation: rotX(.pi / 2), in: g)
        }
        var clear = SimpleMaterial(color: UIColor(hex: 0xFFFFFF), roughness: .float(0.1), isMetallic: false)
        clear.color = .init(tint: UIColor.white.withAlphaComponent(0.3))
        let glass = ModelEntity(mesh: .generateBox(size: [0.9, 0.6, 0.55], cornerRadius: 0.03), materials: [clear])
        glass.position = [0, 1.2, 0]
        g.addChild(glass)
        parts.append(glass)
        parts.append(box([1.0, 0.08, 0.65], 0xE94F64, at: [0, 1.54, 0], corner: 0.03, in: g))
        for i in 0..<14 {
            let x = Float(i % 5) * 0.16 - 0.32, z = Float(i / 5) * 0.14 - 0.14
            let kernel = sphere(0.05, i % 3 == 0 ? 0xFFE08A : 0xFFFBEA, at: [x, 0.95, z], in: g)
            cart.parts["kernel\(i)"] = kernel
        }
        // Balloons tied to the cart.
        for (k, hex) in [UInt32(0xFF8FB1), 0x8ED3F5, 0xFFD45C].enumerated() {
            let x = Float(k - 1) * 0.3
            cylinder(h: 1.2, r: 0.006, 0xFFFFFF, at: [0.5 + x * 0.2, 2.15, -0.2], in: g)
            let balloon = sphere(0.22, hex, at: [0.5 + x, 2.85 + Float(k % 2) * 0.2, -0.2], in: g)
            balloon.scale = [1, 1.2, 1]
        }
        addRect(p, half: [0.6, 0.4], yaw: layout.yaw)
        tappable(parts, .use(cart))
        interactives.append(cart)
    }
}
