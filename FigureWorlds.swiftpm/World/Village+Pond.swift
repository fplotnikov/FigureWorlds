import RealityKit
import UIKit

/// The Forest Pond: a round pond with stepping stones across it, a little boat that goes round,
/// ducks and frogs on lily pads, a campfire with log seats, giant bouncy mushrooms, a picnic
/// and a tree swing. Fish jump now and then and butterflies fly about.
extension Village {
    static let pondCenter = SIMD2<Float>(0, -4)
    static let pondRadius: Float = 5.5
    /// The boat goes round this oval (south half of the pond) and parks at its south end.
    static let boatLoopCenter = SIMD2<Float>(0, -1.3)
    static let boatLoopRadius = SIMD2<Float>(3.2, 1.5)

    /// Where the boat is on its loop (0 = parked by the shore), and which way it points.
    static func boatPose(_ phase: Float) -> (SIMD2<Float>, Float) {
        let c = boatLoopCenter, r = boatLoopRadius
        let p = c + SIMD2<Float>(r.x * sin(phase), r.y * cos(phase))
        let yaw = atan2(r.x * cos(phase), -r.y * sin(phase))
        return (p, yaw)
    }

    func buildPond() {
        start = SIMD2<Float>(0, 3.6)
        let c = Self.pondCenter, r = Self.pondRadius

        // Water, with a sandy edge and darker deep middle.
        cylinder(h: 0.04, r: r + 0.6, 0xE8D9A8, at: [c.x, 0.02, c.y], in: root)
        let water = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: r),
                                materials: [SimpleMaterial(color: UIColor(hex: 0x7ACCEB), roughness: .float(0.15), isMetallic: false)])
        water.position = [c.x, 0.03, c.y]
        root.addChild(water)
        cylinder(h: 0.01, r: r * 0.6, 0x5FB4D9, at: [c.x, 0.058, c.y - 1.5], in: root)
        pondWater = addCircle(c, r - 0.25)

        // Reeds and rocks around the edge (not where the stones, boat and path meet the shore).
        var k = 0
        for i in 0..<18 {
            let a = Float(i) / 18 * 2 * .pi + 0.1
            let dir = SIMD2<Float>(sin(a), cos(a))
            if abs(dir.x) > 0.93 || dir.y > 0.85 { continue }
            let p = c + dir * (r + 0.25)
            if k % 3 == 0 {
                sphere(0.28, 0xB8B2A6, at: [p.x, 0.08, p.y], in: root)
                addCircle(p, 0.26)
            } else {
                for j in 0..<3 {
                    let q = p + SIMD2<Float>(Float(j) * 0.12 - 0.12, Float(j % 2) * 0.1)
                    let h: Float = 0.9 + Float(j) * 0.15
                    cylinder(h: h, r: 0.02, 0x6FAF4E, at: [q.x, h / 2, q.y], in: root)
                    cylinder(h: 0.16, r: 0.045, 0x8A5A3A, at: [q.x, h - 0.05, q.y], in: root)
                }
            }
            k += 1
        }

        buildStones()
        buildBoat()
        buildDucks()
        buildFrogs()
        buildCampfire(at: [-7.5, 6.5])
        for (i, p) in [SIMD2<Float>(10, 3), [11.6, 5.3], [9.0, 6.4]].enumerated() {
            mushroom(id: "mushroom\(i)", at: p, size: 1 - Float(i) * 0.12, cap: [0xE94F64, 0xFF8FB1, 0xFFD45C][i])
        }
        buildSwing(at: [-12, -1])
        buildPicnic(at: [5.5, 9.5])

        // Trees: some inside to walk around, a ring outside.
        let inside: [SIMD2<Float>] = [[-13, -7], [13, -6.5], [-8, -13], [8.5, -13.5], [-14.5, 5], [14, 10], [-4, 14.5]]
        for (i, p) in inside.enumerated() {
            if i % 2 == 0 { tree(at: p, size: 1.1, solid: true) } else { pine(at: p, size: 1.1, snowy: false, solid: true) }
        }
        ringOfTrees(snowy: false)

        // Pinecones to carry, two balls to kick, flowers.
        let cones: [SIMD2<Float>] = [[-12, -5.5], [12, -5], [-6.8, -11.5], [7, -12], [-13, 4], [12.6, 8.6]]
        for (i, p) in cones.enumerated() { makePinecone(id: "cone\(i)", at: [p.x, 0.12, p.y]) }
        for (i, b) in [(SIMD2<Float>(-3, 5.5), UInt32(0xFFD45C)), ([7.5, 1], 0x5DA9E9)].enumerated() {
            let ball = makeBall(id: "ball\(i)", radius: 0.3, hex: b.1, kind: .kick, mass: 0.6)
            ball.entity.position = [b.0.x, 0.302, b.0.y]
            ball.home = ball.entity.transform
        }
        let flowerSpots: [SIMD2<Float>] = [[-9, 10], [3, 13], [11, -2], [-11, -9], [6, -9.5], [-4, 9.5]]
        let colors: [UInt32] = [0xFF8FB1, 0xFFD45C, 0xFFFFFF, 0xC86FC9]
        for (i, f) in flowerSpots.enumerated() {
            for j in 0..<5 {
                let a = Float(j) * 1.3
                let p = f + SIMD2<Float>(cos(a), sin(a)) * 0.45
                cylinder(h: 0.25, r: 0.015, 0x6FAF4E, at: [p.x, 0.125, p.y], in: root)
                sphere(0.08, colors[(i + j) % colors.count], at: [p.x, 0.27, p.y], in: root)
            }
        }
        buildButterflies(around: flowerSpots)
        buildFish()
    }

    // MARK: - Stones, boat, ducks, frogs

    private func buildStones() {
        let st = Interactive(id: "stones", kind: .stones, center: Self.pondCenter)
        let y = Self.pondCenter.y
        st.spots = [[-6.3, y], [6.3, y]]
        var parts: [ModelEntity] = []
        for i in 0..<7 {
            let x = -4.2 + Float(i) * 1.4
            let z = y + (i % 2 == 0 ? 0.25 : -0.25)
            parts.append(cylinder(h: 0.14, r: 0.4, 0xA9A39A, at: [x, 0.07, z], in: root))
            sphere(0.06, 0x8FC27A, at: [x + 0.18, 0.13, z - 0.12], in: root)   // a bit of moss
            st.path.append([x, 0.14, z])
        }
        tappable(parts, .use(st))
        interactives.append(st)
    }

    private func buildBoat() {
        let b = Interactive(id: "boat", kind: .boat, center: Self.boatPose(0).0)
        b.spots = [[0, 2.0]]
        let g = Entity()
        let (p, yaw) = Self.boatPose(0)
        g.position = [p.x, 0.06, p.y]
        g.orientation = rotY(yaw)
        root.addChild(g)
        let wood: UInt32 = 0xC8784A
        var parts = [
            box([0.9, 0.12, 1.5], wood, at: [0, 0.06, 0], corner: 0.05, in: g),
            box([0.08, 0.3, 1.5], wood, at: [-0.43, 0.2, 0], corner: 0.03, in: g),
            box([0.08, 0.3, 1.5], wood, at: [0.43, 0.2, 0], corner: 0.03, in: g),
            box([0.9, 0.3, 0.08], wood, at: [0, 0.2, -0.72], corner: 0.03, in: g),
            box([0.6, 0.3, 0.3], wood, at: [0, 0.2, 0.68], corner: 0.08, in: g),
            box([0.8, 0.05, 0.3], 0xF4E3C1, at: [0, 0.26, -0.3], corner: 0.02, in: g)
        ]
        parts.append(cylinder(h: 1.1, r: 0.025, 0x8A5A3A, at: [0, 0.75, 0.25], in: g))
        let sail = box([0.03, 0.5, 0.45], 0xFFFFFF, at: [0, 0.85, 0.02], corner: 0.02, in: g)
        parts.append(sail)
        box([0.04, 0.12, 0.2], 0xE94F64, at: [0, 1.32, 0.33], corner: 0.01, in: g)
        let seat = Entity()
        seat.position = [0, 0.14, -0.05]
        g.addChild(seat)
        b.seat = seat
        b.parts["boat"] = g
        tappable(parts, .use(b))
        interactives.append(b)

        // A little jetty to step off.
        box([1.0, 0.08, 1.6], 0xB98B5E, at: [0, 0.07, 1.35], corner: 0.02, in: root)
    }

    private func buildDucks() {
        for i in 0..<3 {
            let d = Interactive(id: "duck\(i)", kind: .duck, center: [1, -6.8])
            d.fromAfar = true
            d.phase = Float(i) * 2.1
            let g = Entity()
            root.addChild(g)
            let white = i == 1
            let body = sphere(0.18, white ? 0xFFFFFF : 0xFFD45C, at: [0, 0.12, 0], in: g)
            body.scale = [1, 0.8, 1.3]
            let head = sphere(0.11, white ? 0xFFFFFF : 0xFFD45C, at: [0, 0.32, 0.17], in: g)
            box([0.08, 0.035, 0.1], 0xF28C38, at: [0, 0.3, 0.29], corner: 0.015, in: g)
            sphere(0.02, 0x2E3440, at: [0.06, 0.36, 0.23], in: g)
            sphere(0.02, 0x2E3440, at: [-0.06, 0.36, 0.23], in: g)
            d.parts["duck"] = g
            tappable([body, head], .use(d))
            interactives.append(d)
        }
    }

    private func buildFrogs() {
        let pads: [SIMD3<Float>] = [[-3.0, 0.07, -6.6], [-1.6, 0.07, -8.0], [2.8, 0.07, -7.2], [-3.9, 0.07, -8.0], [3.6, 0.07, -5.6]]
        for p in pads {
            let pad = cylinder(h: 0.02, r: 0.42, 0x5FAE4E, at: p, in: root)
            pad.scale = [1, 1, 0.9]
            sphere(0.07, 0xFF8FB1, at: p + [0.2, 0.05, 0.1], in: root)
        }
        for i in 0..<3 {
            let f = Interactive(id: "frog\(i)", kind: .frog, center: [pads[i].x, pads[i].z])
            f.fromAfar = true
            f.path = pads
            f.value = Float(i)
            f.phase = Float(i)
            let g = Entity()
            g.position = pads[i]
            g.orientation = rotY(Float(i) * 2)
            root.addChild(g)
            let green: UInt32 = 0x7DCB5A
            let body = sphere(0.15, green, at: [0, 0.12, 0], in: g)
            body.scale = [1.1, 0.75, 1]
            for x: Float in [-0.07, 0.07] {
                sphere(0.05, green, at: [x, 0.24, 0.06], in: g)
                sphere(0.025, 0x2E3440, at: [x, 0.26, 0.1], in: g)
                sphere(0.06, green, at: [x * 2, 0.04, -0.05], in: g)
            }
            f.parts["frog"] = g
            tappable([body], .use(f))
            interactives.append(f)
        }
    }

    // MARK: - Campfire, mushrooms, picnic

    private func buildCampfire(at p: SIMD2<Float>) {
        let fire = Interactive(id: "campfire", kind: .campfire, center: p)
        fire.standRadius = 1.3
        let g = group(Layout(origin: p, yaw: 0))
        var parts: [ModelEntity] = []
        for i in 0..<8 {
            let a = Float(i) / 8 * 2 * .pi
            parts.append(sphere(0.14, 0x9A958C, at: [0.55 * sin(a), 0.07, 0.55 * cos(a)], in: g))
        }
        for i in 0..<3 {
            let log = cylinder(h: 0.8, r: 0.07, 0x8A5A3A, at: [0, 0.1, 0], rotation: rotY(Float(i) * 1.05) * rotX(.pi / 2), in: g)
            parts.append(log)
        }
        let flames = Entity()
        flames.isEnabled = false
        g.addChild(flames)
        for (i, hex) in [UInt32(0xFF9A3C), 0xFFD45C, 0xFF6F3C].enumerated() {
            let flame = ModelEntity(mesh: .generateCone(height: 0.5 - Float(i) * 0.1, radius: 0.18 - Float(i) * 0.03),
                                    materials: [UnlitMaterial(color: UIColor(hex: hex))])
            flame.position = [Float(i - 1) * 0.08, 0.35, Float(i % 2) * 0.06]
            flames.addChild(flame)
            fire.parts["flame\(i)"] = flame
        }
        fire.parts["flames"] = flames
        let light = PointLight()
        light.light.color = UIColor(hex: 0xFFB060)
        light.light.intensity = 15000
        light.light.attenuationRadius = 5
        light.position = [0, 0.7, 0]
        light.isEnabled = false
        g.addChild(light)
        fire.light = light
        addCircle(p, 0.8)
        tappable(parts, .use(fire))
        interactives.append(fire)

        logSeat(id: "log0", at: p + [-1.7, 0.7])
        logSeat(id: "log1", at: p + [0.9, 1.6])
    }

    /// A log to sit on, facing the campfire.
    private func logSeat(id: String, at p: SIMD2<Float>) {
        let face = yawFacing(from: p, to: [-7.5, 6.5])
        let layout = Layout(origin: p, yaw: face)
        let g = group(layout)
        let seatThing = Interactive(id: id, kind: .bench, center: p)
        seatThing.spots = [layout.world([0, 0.75])]
        let log = cylinder(h: 1.4, r: 0.22, 0x9C6B4E, at: [0, 0.22, 0], rotation: rotZ(.pi / 2), in: g)
        for x: Float in [-0.7, 0.7] {
            cylinder(h: 0.02, r: 0.2, 0xE3C59B, at: [x, 0.22, 0], rotation: rotZ(.pi / 2), in: g)
        }
        let seat = Entity()
        seat.position = [0, 0.42, 0]
        g.addChild(seat)
        seatThing.seat = seat
        addRect(p, half: [0.7, 0.22], yaw: face)
        tappable([log], .use(seatThing))
        interactives.append(seatThing)
    }

    /// A giant mushroom to bounce on (it works like the beds).
    private func mushroom(id: String, at p: SIMD2<Float>, size s: Float, cap: UInt32) {
        let m = Interactive(id: id, kind: .bed, center: p)
        m.standRadius = 0.85 * s + 0.7
        let g = group(Layout(origin: p, yaw: 0))
        let stem = cylinder(h: 0.65 * s, r: 0.28 * s, 0xF4ECDC, at: [0, 0.325 * s, 0], in: g, solid: true)
        let top = sphere(0.85 * s, cap, at: [0, 0.62 * s, 0], in: g)
        top.scale = [1, 0.42, 1]
        var parts = [stem, top]
        for i in 0..<6 {
            let a = Float(i) * 1.05
            parts.append(sphere(0.1 * s, 0xFFFFFF, at: [0.5 * s * sin(a), 0.86 * s, 0.5 * s * cos(a)], in: g))
        }
        let seat = Entity()
        seat.position = [0, 0.98 * s, 0]
        g.addChild(seat)
        m.seat = seat
        // The cap is wide: keep walkers out from under its edge.
        addCircle(p, 0.82 * s)
        tappable(parts, .use(m))
        interactives.append(m)
    }

    private func buildPicnic(at p: SIMD2<Float>) {
        box([2.2, 0.02, 1.6], 0xF6B7C6, at: [p.x, 0.011, p.y], corner: 0.005, in: root)
        for i in 0..<4 {
            box([0.25, 0.022, 1.6], 0xFFFFFF, at: [p.x - 0.82 + Float(i) * 0.55, 0.013, p.y], corner: 0.005, in: root)
        }
        box([0.5, 0.3, 0.35], 0xC89B6D, at: [p.x + 0.6, 0.15, p.y - 0.3], corner: 0.05, in: root, solid: true)
        cylinder(h: 0.5, r: 0.02, 0x9C6B4E, at: [p.x + 0.6, 0.42, p.y - 0.3], rotation: rotZ(.pi / 2), in: root)
        addRect([p.x + 0.6, p.y - 0.3], half: [0.25, 0.18], yaw: 0)
        makeApple(id: "apple0", at: [p.x - 0.4, 0.1, p.y + 0.2], hex: 0xE94F64)
        makeApple(id: "apple1", at: [p.x - 0.1, 0.1, p.y + 0.4], hex: 0x9BD77A)
        makeApple(id: "apple2", at: [p.x + 0.1, 0.1, p.y + 0.1], hex: 0xE94F64)
    }

    // MARK: - Small things

    @discardableResult
    func makePinecone(id: String, at p: SIMD3<Float>) -> Prop {
        let e = ModelEntity(mesh: .generateSphere(radius: 0.1), materials: [Self.mat(0x8A5A3A)])
        e.scale = [1, 1.3, 1]
        for i in 0..<3 {
            let y = -0.05 + Float(i) * 0.05
            cylinder(h: 0.03, r: 0.105 - Float(i) * 0.02, 0x6E4528, at: [0, y, 0], in: e)
        }
        let shape = ShapeResource.generateSphere(radius: 0.11)
        e.collision = CollisionComponent(shapes: [shape])
        e.physicsBody = PhysicsBodyComponent(
            massProperties: .init(shape: shape, mass: 0.15),
            material: .generate(staticFriction: 0.8, dynamicFriction: 0.7, restitution: 0.2),
            mode: .dynamic)
        e.position = p
        root.addChild(e)
        let prop = Prop(id: id, kind: .carry, entity: e, radius: 0.14, lift: 0.13, mass: 0.15)
        prop.home = e.transform
        props.append(prop)
        tapTargets[ObjectIdentifier(e)] = .prop(prop)
        return prop
    }

    private func buildButterflies(around spots: [SIMD2<Float>]) {
        var list: [Entity] = []
        let colors: [UInt32] = [0xFFD45C, 0xFF8FB1, 0x8ED3F5, 0xFFFFFF, 0xC86FC9]
        for i in 0..<5 {
            let b = Entity()
            let c = spots[i % spots.count]
            b.position = [c.x, 0.8, c.y]
            for side: Float in [-1, 1] {
                let wingPivot = Entity()
                wingPivot.name = side < 0 ? "left" : "right"
                b.addChild(wingPivot)
                let wing = ModelEntity(mesh: .generateBox(size: [0.12, 0.01, 0.1], cornerRadius: 0.004),
                                       materials: [UnlitMaterial(color: UIColor(hex: colors[i]))])
                wing.position = [0.06 * side, 0, 0]
                wingPivot.addChild(wing)
            }
            root.addChild(b)
            list.append(b)
        }
        ambient["butterflies"] = list
        ambient["butterflyHomes"] = spots.map { s in
            let e = Entity()
            e.position = [s.x, 0, s.y]
            return e
        }
    }

    private func buildFish() {
        let fish = ModelEntity(mesh: .generateSphere(radius: 0.12), materials: [Self.mat(0xFF9A3C, rough: 0.3)])
        fish.scale = [0.6, 0.7, 1.4]
        box([0.02, 0.12, 0.1], 0xFF9A3C, at: [0, 0, -0.15], corner: 0.01, in: fish)
        fish.isEnabled = false
        root.addChild(fish)
        let splash = ModelEntity(mesh: .generateCylinder(height: 0.01, radius: 0.3), materials: [Self.water()])
        splash.isEnabled = false
        root.addChild(splash)
        ambient["fish"] = [fish, splash]
    }

    // MARK: - Trees for the pond and the snow

    func pine(at p: SIMD2<Float>, size s: Float, snowy: Bool, solid: Bool) {
        let g = Entity()
        g.position = [p.x, 0, p.y]
        root.addChild(g)
        let trunk = cylinder(h: 0.9 * s, r: 0.18 * s, 0x8A5A3A, at: [0, 0.45 * s, 0], in: g)
        let green: UInt32 = snowy ? 0x4E9A6A : 0x4FA96A
        for (r, y) in [(Float(1.25), Float(1.3)), (0.95, 2.1), (0.62, 2.8)] {
            cone(h: 1.1 * s, r: r * s, green, at: [0, y * s, 0], in: g)
            if snowy {
                cone(h: 0.45 * s, r: r * 0.55 * s, 0xFFFFFF, at: [0, (y + 0.35) * s, 0], in: g)
            }
        }
        if solid {
            Self.makeSolid(trunk, .generateBox(size: [0.4 * s, 0.9 * s, 0.4 * s]))
            let i = addCircle(p, 0.3 * s)
            obstacles[i].view = Obstacle.ViewBlock(crown: 1.3 * s, crownBottom: 0.8 * s, top: 3.4 * s)
        }
    }

    /// Trees outside the fence, so the edge of the world is never seen.
    func ringOfTrees(snowy: Bool) {
        var seed: UInt32 = snowy ? 11 : 5
        func rnd() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(seed >> 8) / Float(1 << 24)
        }
        for i in 0..<36 {
            let a = Float(i) / 36 * 2 * .pi + rnd() * 0.12
            let r = 20 + rnd() * 5
            let p = SIMD2<Float>(r * sin(a), r * cos(a))
            let s = 0.9 + rnd() * 0.5
            if snowy || i % 3 != 0 { pine(at: p, size: s * 1.2, snowy: snowy, solid: false) } else { tree(at: p, size: s, solid: false) }
        }
    }

    // MARK: - Things that move by themselves

    func updateAmbient(_ dt: Float, near: SIMD3<Float>) {
        ambientTime += dt
        let t = ambientTime
        if let flies = ambient["butterflies"], let homes = ambient["butterflyHomes"] {
            for (i, b) in flies.enumerated() {
                let home = homes[i % homes.count].position
                let a = t * (0.5 + Float(i) * 0.07) + Float(i) * 1.7
                let p = home + SIMD3<Float>(1.3 * sin(a), 0.7 + 0.25 * sin(a * 2.3), 1.0 * sin(a * 1.6))
                let ahead = home + SIMD3<Float>(1.3 * sin(a + 0.1), 0, 1.0 * sin((a + 0.1) * 1.6))
                b.position = p
                b.orientation = rotY(atan2(ahead.x - p.x, ahead.z - p.z))
                let flap = 0.9 * sin(t * 18 + Float(i))
                for wing in b.children {
                    wing.orientation = rotZ(wing.name == "left" ? -flap : flap)
                }
            }
        }
        if let fishParts = ambient["fish"], fishParts.count == 2 {
            let fish = fishParts[0], splash = fishParts[1]
            let cycle: Float = 5.5
            let u = t.truncatingRemainder(dividingBy: cycle)
            let n = Int(t / cycle)
            let a = Float(n * 7 % 11) / 11 * 2.4 - 1.2
            let base = Self.pondCenter + SIMD2<Float>(2.6 * sin(a), -2.0 - abs(cos(a)) * 1.2)
            if u < 0.9 {
                let k = u / 0.9
                fish.isEnabled = true
                let x = base.x + (k - 0.5) * 1.0
                fish.position = [x, 0.05 + 0.9 * sin(.pi * k), base.y]
                fish.orientation = rotY(.pi / 2) * rotX(-1.6 * (k - 0.5))
                splash.isEnabled = false
            } else if u < 1.5 {
                fish.isEnabled = false
                splash.isEnabled = true
                let k = (u - 0.9) / 0.6
                splash.position = [base.x + 0.5, 0.07, base.y]
                splash.scale = SIMD3<Float>(repeating: 0.5 + k * 1.5)
            } else {
                fish.isEnabled = false
                splash.isEnabled = false
            }
        }
        if let flakes = ambient["flakes"] {
            for (i, f) in flakes.enumerated() {
                var p = f.position
                p.y -= dt * (0.5 + Float(i % 5) * 0.08)
                p.x += dt * 0.15 * sin(t * 0.7 + Float(i))
                if p.y < 0 || abs(p.x - near.x) > 9 || abs(p.z - near.z) > 9 {
                    let a = Float(i) * 2.399
                    let r = 1 + Float((i * 37) % 80) / 10
                    p = SIMD3<Float>(near.x + r * sin(a + t), 5.5 + Float(i % 7) * 0.2, near.z + r * cos(a + t))
                }
                f.position = p
            }
        }
    }
}
