import RealityKit
import UIKit

/// The Cozy Village: a square with a fountain, three houses you can walk into,
/// a playground and toys. Everything is built in code from simple rounded shapes.
/// Sizes are in metres; an animal is about 0.8 m tall.
@MainActor
final class Village {
    let root = Entity()
    let scene: SceneKind
    /// Where the animal starts in this place.
    var start = SIMD2<Float>(0, 3.3)
    /// Little things that move by themselves (fish, butterflies, snowflakes), by name.
    var ambient: [String: [Entity]] = [:]
    var ambientTime: Float = 0
    var obstacles: [Obstacle] = []
    var props: [Prop] = []
    var interactives: [Interactive] = []
    var houses: [House] = []
    var tapTargets: [ObjectIdentifier: TapTarget] = [:]
    /// The two-story house (Village+BigHouse.swift).
    var bigHouseIndex: Int?
    var stairs: Stairs?
    /// Which grid cells an animal can stand on, per floor (Navigation.swift). Cleared when a door moves.
    var navCache: [[Int8]] = [[], []]
    /// The big house's walls and windows, so the ones between the camera and the animal can fade.
    var bigWalls: [BigWall] = []

    /// Upstairs floor height in the big house.
    static let floorHeight: Float = 3.2

    /// Animals stay inside this circle (the fence is at 18 m).
    static let walkRadius: Float = 17.2
    init(scene: SceneKind = .village) {
        self.scene = scene
        buildGround()
        buildFence()
        switch scene {
        case .village:
            buildTrees()
            buildSquare()
            buildHouses()
            buildPlayground()
            buildToys()
            buildBigHouse()
        case .pond:
            buildPond()
        case .snow:
            buildSnow()
        case .workshop:
            buildWorkshop()
        case .carnival:
            buildCarnival()
        }
    }

    // MARK: - Queries

    func tapTarget(for entity: Entity) -> TapTarget? {
        tapTargets[ObjectIdentifier(entity)]
    }

    func setObstacle(_ index: Int, enabled: Bool) {
        guard obstacles.indices.contains(index) else { return }
        guard obstacles[index].enabled != enabled else { return }
        obstacles[index].enabled = enabled
        navCache = [[], []]
    }

    /// Moves an animal's spot out of walls and posts and keeps it inside the fence.
    func resolve(_ p: SIMD2<Float>, radius: Float, level: Int = 0) -> SIMD2<Float> {
        var q = p
        for _ in 0..<2 {
            for o in obstacles where o.level == level { q = o.pushOut(q, radius: radius) }
        }
        return clampToWorld(q)
    }

    func clampToWorld(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let len = simd_length(p)
        if len > Self.walkRadius { return p * (Self.walkRadius / len) }
        return p
    }

    func houseIndex(containing p: SIMD2<Float>) -> Int? {
        houses.firstIndex { $0.contains(p) }
    }

    // MARK: - Shape helpers

    static func mat(_ hex: UInt32, rough: Float = 0.85) -> SimpleMaterial {
        SimpleMaterial(color: UIColor(hex: hex), roughness: .float(rough), isMetallic: false)
    }

    static func water() -> UnlitMaterial {
        var m = UnlitMaterial(color: UIColor(hex: 0x8ED3F5))
        m.blending = .transparent(opacity: .init(floatLiteral: 0.75))
        return m
    }

    /// A static (or kinematic) body that balls and blocks bounce off.
    static func makeSolid(_ e: Entity, _ shape: ShapeResource, mode: PhysicsBodyMode = .static) {
        e.components.set(CollisionComponent(shapes: [shape]))
        e.components.set(PhysicsBodyComponent(
            massProperties: .default,
            material: .generate(staticFriction: 0.8, dynamicFriction: 0.6, restitution: 0.3),
            mode: mode))
    }

    /// Makes taps on `e` mean `target`. Adds a tap-only shape when it has none.
    func tappable(_ entities: [ModelEntity], _ target: TapTarget) {
        for e in entities {
            if e.components[CollisionComponent.self] == nil, let bounds = e.model?.mesh.bounds {
                let size = simd_max(bounds.extents, SIMD3<Float>(repeating: 0.35))
                let shape = ShapeResource.generateBox(size: size).offsetBy(translation: bounds.center)
                e.components.set(CollisionComponent(shapes: [shape], mode: .trigger, filter: .default))
            }
            tapTargets[ObjectIdentifier(e)] = target
        }
    }

    @discardableResult
    func box(_ size: SIMD3<Float>, _ hex: UInt32, at p: SIMD3<Float>, corner: Float = 0.03,
                     in parent: Entity, solid: Bool = false) -> ModelEntity {
        let r = min(corner, size.min() * 0.45)
        let e = ModelEntity(mesh: .generateBox(size: size, cornerRadius: r), materials: [Self.mat(hex)])
        e.position = p
        parent.addChild(e)
        if solid { Self.makeSolid(e, .generateBox(size: size)) }
        return e
    }

    @discardableResult
    func cylinder(h: Float, r: Float, _ hex: UInt32, at p: SIMD3<Float>,
                          rotation: simd_quatf = rotY(0), in parent: Entity, solid: Bool = false) -> ModelEntity {
        let e = ModelEntity(mesh: .generateCylinder(height: h, radius: r), materials: [Self.mat(hex)])
        e.position = p
        e.orientation = rotation
        parent.addChild(e)
        if solid { Self.makeSolid(e, .generateBox(size: [2 * r, h, 2 * r])) }
        return e
    }

    @discardableResult
    func sphere(_ r: Float, _ hex: UInt32, at p: SIMD3<Float>, in parent: Entity) -> ModelEntity {
        let e = ModelEntity(mesh: .generateSphere(radius: r), materials: [Self.mat(hex)])
        e.position = p
        parent.addChild(e)
        return e
    }

    @discardableResult
    func cone(h: Float, r: Float, _ hex: UInt32, at p: SIMD3<Float>, in parent: Entity) -> ModelEntity {
        let e = ModelEntity(mesh: .generateCone(height: h, radius: r), materials: [Self.mat(hex)])
        e.position = p
        parent.addChild(e)
        return e
    }

    /// A group entity standing at `layout`, turned by its yaw.
    func group(_ layout: Layout) -> Entity {
        let g = Entity()
        g.position = [layout.origin.x, 0, layout.origin.y]
        g.orientation = rotY(layout.yaw)
        root.addChild(g)
        return g
    }

    @discardableResult
    func addRect(_ center: SIMD2<Float>, half: SIMD2<Float>, yaw: Float, level: Int = 0) -> Int {
        obstacles.append(Obstacle(center: center, shape: .rect(halfX: half.x, halfZ: half.y, yaw: yaw), level: level))
        return obstacles.count - 1
    }

    @discardableResult
    func addCircle(_ center: SIMD2<Float>, _ r: Float, level: Int = 0) -> Int {
        obstacles.append(Obstacle(center: center, shape: .circle(radius: r), level: level))
        return obstacles.count - 1
    }

    func path(from a: SIMD2<Float>, to b: SIMD2<Float>, width: Float = 1.4) {
        let mid = (a + b) / 2
        let d = b - a
        let e = box([width, 0.02, simd_length(d)], 0xEADFCB, at: [mid.x, 0.011, mid.y], corner: 0.005, in: root)
        e.orientation = rotY(atan2(d.x, d.y))
    }

    // MARK: - Ground, fence, trees

    private func buildGround() {
        let groundHex: UInt32
        switch scene {
        case .snow: groundHex = 0xEEF4FA
        case .pond: groundHex = 0x8FD07A
        case .workshop: groundHex = 0xBCC3CC
        case .carnival: groundHex = 0x5F9461
        case .village: groundHex = 0x9BD77A
        }
        let grass = ModelEntity(mesh: .generateCylinder(height: 1, radius: 45), materials: [Self.mat(groundHex)])
        grass.position = [0, -0.5, 0]
        root.addChild(grass)
        Self.makeSolid(grass, .generateBox(size: [90, 1, 90]))
        tapTargets[ObjectIdentifier(grass)] = .ground

        // Soft hills far away, so the edge of the world is never seen.
        let hills: [(Float, Float, Float, UInt32)] = [
            (-30, -36, 16, 0x8CCB6E), (8, -44, 20, 0x86C766), (37, -18, 15, 0x93D277),
            (-42, 10, 18, 0x8CCB6E), (22, 39, 17, 0x86C766), (-14, 42, 14, 0x93D277), (42, 16, 14, 0x8CCB6E)
        ]
        for (x, z, r, hex) in hills {
            let shade: UInt32
            switch scene {
            case .snow: shade = hex == 0x86C766 ? 0xD9E4EF : 0xE8F0F8
            case .workshop: shade = hex == 0x86C766 ? 0xC9B49A : 0xD8C4A8
            case .carnival: shade = hex == 0x86C766 ? 0x34505A : 0x3E5C62
            default: shade = hex
            }
            sphere(r, shade, at: [x, -r * 0.55, z], in: root)
        }
    }

    private func buildFence() {
        let r: Float = 18
        let n = 40
        let step = 2 * Float.pi / Float(n)
        let postMesh = MeshResource.generateCylinder(height: 0.9, radius: 0.07)
        let wood = Self.mat(0xC89B6D)
        let segment = 2 * r * sin(step / 2)
        let inner = r * cos(step / 2)
        for i in 0..<n {
            let a = Float(i) * step
            let post = ModelEntity(mesh: postMesh, materials: [wood])
            post.position = [r * sin(a), 0.45, r * cos(a)]
            root.addChild(post)

            let mid = a + step / 2
            let c = SIMD3<Float>(inner * sin(mid), 0, inner * cos(mid))
            for y: Float in [0.35, 0.7] {
                let rail = box([segment + 0.05, 0.09, 0.05], 0xD9AE7E, at: [c.x, y, c.z], corner: 0.01, in: root)
                rail.orientation = rotY(mid)
            }
            // An invisible wall so balls stay in.
            let wall = Entity()
            wall.position = [c.x, 0.7, c.z]
            wall.orientation = rotY(mid)
            Self.makeSolid(wall, .generateBox(size: [segment + 0.1, 1.4, 0.3]))
            root.addChild(wall)
        }
    }

    func tree(at p: SIMD2<Float>, size s: Float = 1, solid: Bool) {
        let g = Entity()
        g.position = [p.x, 0, p.y]
        root.addChild(g)
        let trunk = cylinder(h: 1.8 * s, r: 0.22 * s, 0x8A5A3A, at: [0, 0.9 * s, 0], in: g)
        sphere(1.1 * s, 0x6FBF5A, at: [0, 2.3 * s, 0], in: g)
        sphere(0.8 * s, 0x86CF6A, at: [0.5 * s, 2.9 * s, 0.2 * s], in: g)
        sphere(0.7 * s, 0x7CC860, at: [-0.5 * s, 2.75 * s, -0.3 * s], in: g)
        if solid {
            Self.makeSolid(trunk, .generateBox(size: [0.45 * s, 1.8 * s, 0.45 * s]))
            let i = addCircle(p, 0.3 * s)
            obstacles[i].view = Obstacle.ViewBlock(crown: 1.25 * s, crownBottom: 1.25 * s, top: 3.5 * s)
        }
    }

    private func buildTrees() {
        let inside: [SIMD2<Float>] = [[-14, 8], [14.5, -8.5], [-9.5, 13.5], [8.5, 13.8], [-15.5, -5], [-12, -12.5], [12.5, -12]]
        for p in inside { tree(at: p, size: 1, solid: true) }

        // A ring of trees outside the fence. Fixed "random" spots so the village always looks the same.
        var seed: UInt32 = 7
        func rnd() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(seed >> 8) / Float(1 << 24)
        }
        for i in 0..<34 {
            let a = Float(i) / 34 * 2 * .pi + rnd() * 0.12
            let r = 20 + rnd() * 5
            tree(at: [r * sin(a), r * cos(a)], size: 0.9 + rnd() * 0.5, solid: false)
        }
    }

    // MARK: - The square

    private func buildSquare() {
        cylinder(h: 0.03, r: 6.5, 0xEADFCB, at: [0, 0.012, 0], in: root)
        buildFountain()
        let lamps: [SIMD2<Float>] = [[4.5, 3.8], [-4.5, 3.8], [4.5, -3.8], [-4.5, -3.8]]
        for (i, p) in lamps.enumerated() { streetLamp(id: "lamp\(i)", at: p) }
        bench(id: "bench0", at: [-2.3, 4.7])
        bench(id: "bench1", at: [2.3, 4.7])
        bell(id: "bell", at: [-5.4, -1.2])
        // Paths out of the square: east to the playground, west to the blocks.
        path(from: [6.4, 0.8], to: [9.6, 1.2])
        path(from: [-6.4, 1.0], to: [-9.0, 2.0])
    }

    private func buildFountain() {
        let f = Interactive(id: "fountain", kind: .fountain, center: [0, 0])
        f.standRadius = 2.3
        let stone: UInt32 = 0xD8CFC0
        let basin = cylinder(h: 0.55, r: 1.65, stone, at: [0, 0.275, 0], in: root, solid: true)
        let water = ModelEntity(mesh: .generateCylinder(height: 0.04, radius: 1.45), materials: [Self.water()])
        water.position = [0, 0.545, 0]
        root.addChild(water)
        let column = cylinder(h: 0.8, r: 0.16, stone, at: [0, 0.95, 0], in: root)
        let bowl = cylinder(h: 0.14, r: 0.55, stone, at: [0, 1.32, 0], in: root)

        let jetPivot = Entity()
        jetPivot.position = [0, 1.39, 0]
        jetPivot.scale = [1, 0.45, 1]
        root.addChild(jetPivot)
        let jet = ModelEntity(mesh: .generateCylinder(height: 1, radius: 0.07), materials: [Self.water()])
        jet.position = [0, 0.5, 0]
        jetPivot.addChild(jet)
        f.parts["jet"] = jetPivot

        let dropMesh = MeshResource.generateSphere(radius: 0.07)
        for i in 0..<8 {
            let drop = ModelEntity(mesh: dropMesh, materials: [Self.water()])
            drop.isEnabled = false
            root.addChild(drop)
            f.parts["drop\(i)"] = drop
        }
        f.obstacle = addCircle([0, 0], 1.7)
        tappable([basin, water, column, bowl], .use(f))
        interactives.append(f)
    }

    func streetLamp(id: String, at p: SIMD2<Float>) {
        let lamp = Interactive(id: id, kind: .streetLamp, center: p)
        lamp.standRadius = 0.95
        let g = group(Layout(origin: p, yaw: 0))
        let post = cylinder(h: 2.6, r: 0.07, 0x4A5060, at: [0, 1.3, 0], in: g, solid: true)
        let cap = cone(h: 0.22, r: 0.26, 0x4A5060, at: [0, 3.0, 0], in: g)
        let bulb = sphere(0.2, 0xF2F2F2, at: [0, 2.78, 0], in: g)
        lamp.parts["bulb"] = bulb
        let o = addCircle(p, 0.15)
        obstacles[o].view = Obstacle.ViewBlock(crown: 0.3, crownBottom: 2.6, top: 3.15)
        tappable([post, cap, bulb], .use(lamp))
        interactives.append(lamp)
    }

    func bench(id: String, at p: SIMD2<Float>) {
        let layout = Layout(origin: p, yaw: yawFacing(from: p, to: .zero))
        let g = group(layout)
        let b = Interactive(id: id, kind: .bench, center: p)
        b.spots = [layout.world([0, 0.85])]
        let wood: UInt32 = 0xC89B6D
        let seatBoard = box([1.6, 0.08, 0.5], wood, at: [0, 0.45, 0], in: g, solid: true)
        let back = box([1.6, 0.45, 0.07], wood, at: [0, 0.78, -0.24], in: g, solid: true)
        var legs: [ModelEntity] = []
        for x: Float in [-0.65, 0.65] {
            legs.append(box([0.08, 0.42, 0.45], 0x6A6A72, at: [x, 0.21, 0], in: g))
        }
        let seat = Entity()
        seat.position = [0, 0.49, 0.02]
        g.addChild(seat)
        b.seat = seat
        addRect(p, half: [0.85, 0.3], yaw: layout.yaw)
        tappable([seatBoard, back] + legs, .use(b))
        interactives.append(b)
    }

    private func bell(id: String, at p: SIMD2<Float>) {
        let layout = Layout(origin: p, yaw: yawFacing(from: p, to: .zero))
        let g = group(layout)
        let b = Interactive(id: id, kind: .bell, center: p)
        b.spots = [layout.world([0, 1.0]), layout.world([0, -1.0])]
        let red: UInt32 = 0xE94F64
        var parts: [ModelEntity] = []
        for x: Float in [-0.55, 0.55] {
            parts.append(cylinder(h: 2.2, r: 0.06, red, at: [x, 1.1, 0], in: g, solid: true))
            addCircle(layout.world([x, 0]), 0.1)
        }
        parts.append(cylinder(h: 1.3, r: 0.05, red, at: [0, 2.2, 0], rotation: rotZ(.pi / 2), in: g))
        let pivot = Entity()
        pivot.position = [0, 2.15, 0]
        g.addChild(pivot)
        parts.append(sphere(0.08, 0xF5C542, at: [0, -0.04, 0], in: pivot))
        parts.append(cone(h: 0.5, r: 0.32, 0xF5C542, at: [0, -0.3, 0], in: pivot))
        sphere(0.07, 0x6A5A3A, at: [0, -0.56, 0], in: pivot)
        b.parts["pivot"] = pivot
        tappable(parts, .use(b))
        interactives.append(b)
    }

    // MARK: - Houses

    private func buildHouses() {
        let specs: [(theta: Float, wall: UInt32, roof: UInt32, flower: UInt32)] = [
            (-0.7, 0xFFE3C2, 0xE8743B, 0xFF8FB1),
            (0, 0xD7ECFF, 0x5DA9E9, 0xFFD45C),
            (0.7, 0xFFD6E0, 0xC86FC9, 0xFFFFFF)
        ]
        for (i, s) in specs.enumerated() {
            let c = SIMD2<Float>(11 * sin(s.theta), -11 * cos(s.theta))
            let layout = Layout(origin: c, yaw: -s.theta)
            house(index: i, layout: layout, wallHex: s.wall, roofHex: s.roof)
            path(from: c * (6.4 / 11), to: c * (9.1 / 11))
            for (j, x) in [Float(-1.6), 1.6].enumerated() {
                pot(id: "pot\(i)_\(j)", at: layout.world([x, 2.65]), flower: s.flower)
            }
        }
        mailbox(id: "mailbox", at: [2.9, -8.1])
    }

    private func house(index: Int, layout: Layout, wallHex: UInt32, roofHex: UInt32) {
        let g = group(layout)
        let hx: Float = 2.2, hz: Float = 2.0, h: Float = 2.4, t: Float = 0.2

        func wall(_ lx: Float, _ lz: Float, _ sx: Float, _ sz: Float) {
            box([sx, h, sz], wallHex, at: [lx, h / 2, lz], corner: 0.02, in: g, solid: true)
            addRect(layout.world([lx, lz]), half: [sx / 2, sz / 2], yaw: layout.yaw)
        }
        wall(0, -hz + t / 2, 2 * hx, t)          // back
        wall(-hx + t / 2, 0, t, 2 * hz)          // left
        wall(hx - t / 2, 0, t, 2 * hz)           // right
        let side = hx - 0.65                      // the front, either side of the door
        wall(-(0.65 + side / 2), hz - t / 2, side, t)
        wall(0.65 + side / 2, hz - t / 2, side, t)
        box([1.3, 0.4, t], wallHex, at: [0, 2.2, hz - t / 2], corner: 0.02, in: g)

        box([2 * hx - 0.1, 0.03, 2 * hz - 0.1], 0xD9B98F, at: [0, 0.015, 0], corner: 0.005, in: g)
        for x in [-hx - 0.01, hx + 0.01, -hx + t + 0.01, hx - t - 0.01] {
            box([0.04, 0.7, 0.9], 0xCFEFFF, at: [x, 1.4, 0], corner: 0.01, in: g)
        }
        let roof = cone(h: 1.7, r: 3.3, roofHex, at: [0, h + 0.85, 0], in: g)
        houses.append(House(center: layout.origin, yaw: layout.yaw, halfX: hx, halfZ: hz, roof: roof))

        // Door: swings inwards on a hinge at its left edge.
        let door = Interactive(id: "door\(index)", kind: .door, center: layout.world([0, hz - t / 2]))
        door.spots = [layout.world([0, hz + 0.9]), layout.world([0, hz - 1.0])]
        let hinge = Entity()
        hinge.position = [-0.6, 0, hz - t / 2]
        g.addChild(hinge)
        let leaf = box([1.2, 2.0, 0.08], 0x9C6B4E, at: [0.6, 1.0, 0], corner: 0.02, in: hinge)
        Self.makeSolid(leaf, .generateBox(size: [1.2, 2.0, 0.08]), mode: .kinematic)
        let knob = sphere(0.05, 0xF5C542, at: [1.05, 1.0, 0.07], in: hinge)
        door.parts["hinge"] = hinge
        door.obstacle = addRect(door.center, half: [0.6, 0.1], yaw: layout.yaw)
        tappable([leaf, knob], .use(door))
        interactives.append(door)
        houses[houses.count - 1].door = door

        buildBed(index: index, layout: layout, in: g, blanket: roofHex)
        buildLamp(index: index, layout: layout, in: g, shade: roofHex)
        buildToyBox(index: index, layout: layout, in: g)
    }

    private func buildBed(index: Int, layout: Layout, in g: Entity, blanket: UInt32) {
        let bed = Interactive(id: "bed\(index)", kind: .bed, center: layout.world([-1.3, -0.9]))
        bed.spots = [layout.world([-1.3, 0.55])]
        let frame = box([1.2, 0.35, 1.8], 0xB07A50, at: [-1.3, 0.175, -0.9], in: g, solid: true)
        let mattress = box([1.1, 0.12, 1.7], 0xF4F1EA, at: [-1.3, 0.41, -0.9], corner: 0.05, in: g, solid: true)
        let pillow = box([0.8, 0.12, 0.35], 0xFFFFFF, at: [-1.3, 0.52, -1.55], corner: 0.05, in: g)
        let cover = box([1.14, 0.05, 1.05], blanket, at: [-1.3, 0.49, -0.42], corner: 0.02, in: g)
        let top = Entity()
        top.position = [-1.3, 0.5, -0.8]
        g.addChild(top)
        bed.seat = top
        addRect(bed.center, half: [0.6, 0.9], yaw: layout.yaw)
        tappable([frame, mattress, pillow, cover], .use(bed))
        interactives.append(bed)
    }

    private func buildLamp(index: Int, layout: Layout, in g: Entity, shade: UInt32) {
        let lamp = Interactive(id: "houselamp\(index)", kind: .lamp, center: layout.world([1.4, -1.3]))
        lamp.spots = [layout.world([1.4, -0.3])]
        let table = box([0.8, 0.6, 0.8], 0xB07A50, at: [1.4, 0.3, -1.3], in: g, solid: true)
        let base = cylinder(h: 0.05, r: 0.13, 0x4A5060, at: [1.4, 0.625, -1.3], in: g)
        let stem = cylinder(h: 0.45, r: 0.025, 0x4A5060, at: [1.4, 0.875, -1.3], in: g)
        let bulb = sphere(0.08, 0xF2F2F2, at: [1.4, 1.06, -1.3], in: g)
        let hat = cone(h: 0.28, r: 0.24, shade, at: [1.4, 1.2, -1.3], in: g)
        let light = PointLight()
        light.light.color = UIColor(hex: 0xFFD9A0)
        light.light.intensity = 12000
        light.light.attenuationRadius = 4.5
        light.position = [1.4, 1.0, -1.3]
        light.isEnabled = false
        g.addChild(light)
        lamp.parts["bulb"] = bulb
        lamp.light = light
        addRect(lamp.center, half: [0.4, 0.4], yaw: layout.yaw)
        tappable([table, base, stem, bulb, hat], .use(lamp))
        interactives.append(lamp)
    }

    private func buildToyBox(index: Int, layout: Layout, in g: Entity) {
        let toy = Interactive(id: "toybox\(index)", kind: .toyBox, center: layout.world([1.4, 1.0]))
        toy.spots = [layout.world([0.45, 1.0])]
        let tb = Entity()
        tb.position = [1.4, 0, 1.0]
        g.addChild(tb)
        let red: UInt32 = 0xE94F64
        let panels = [
            box([0.9, 0.05, 0.7], red, at: [0, 0.025, 0], corner: 0.01, in: tb, solid: true),
            box([0.05, 0.55, 0.7], red, at: [-0.425, 0.3, 0], corner: 0.01, in: tb, solid: true),
            box([0.05, 0.55, 0.7], red, at: [0.425, 0.3, 0], corner: 0.01, in: tb, solid: true),
            box([0.9, 0.55, 0.05], red, at: [0, 0.3, -0.325], corner: 0.01, in: tb, solid: true),
            box([0.9, 0.55, 0.05], red, at: [0, 0.3, 0.325], corner: 0.01, in: tb, solid: true)
        ]
        let hinge = Entity()
        hinge.position = [0, 0.58, -0.35]
        tb.addChild(hinge)
        let lid = box([0.94, 0.05, 0.74], 0xFFD45C, at: [0, 0.025, 0.37], corner: 0.015, in: hinge)
        Self.makeSolid(lid, .generateBox(size: [0.94, 0.05, 0.74]), mode: .kinematic)
        toy.parts["lid"] = hinge
        addRect(toy.center, half: [0.45, 0.35], yaw: layout.yaw)
        tappable(panels + [lid], .use(toy))

        let spots: [SIMD3<Float>] = [[-0.22, 0.17, 0.0], [0.02, 0.17, 0.12], [0.24, 0.17, -0.1]]
        let colors: [UInt32] = [0x5DA9E9, 0xFFD45C, 0x7FD8BE]
        for (j, local) in spots.enumerated() {
            let ball = makeBall(id: "toyball\(index)_\(j)", radius: 0.12, hex: colors[j], kind: .carry, mass: 0.2)
            ball.entity.setPosition(local, relativeTo: tb)
            ball.home = ball.entity.transform
            toy.contents.append(ball)
        }
        interactives.append(toy)
    }

    private func mailbox(id: String, at p: SIMD2<Float>) {
        let layout = Layout(origin: p, yaw: yawFacing(from: p, to: .zero))
        let g = group(layout)
        let m = Interactive(id: id, kind: .mailbox, center: p)
        m.standRadius = 0.9
        let post = box([0.1, 1.0, 0.1], 0xC89B6D, at: [0, 0.5, 0], in: g)
        let body = box([0.38, 0.32, 0.55], 0x5DA9E9, at: [0, 1.15, 0], corner: 0.1, in: g)
        let flagPivot = Entity()
        flagPivot.position = [0.21, 1.05, 0.1]
        flagPivot.orientation = rotX(-1.5)
        g.addChild(flagPivot)
        let stick = box([0.03, 0.42, 0.03], 0xE94F64, at: [0, 0.21, 0], corner: 0.01, in: flagPivot)
        let flag = box([0.03, 0.13, 0.2], 0xE94F64, at: [0, 0.35, -0.1], corner: 0.01, in: flagPivot)
        m.parts["flag"] = flagPivot
        m.value = -1.5
        addCircle(p, 0.25)
        tappable([post, body, stick, flag], .use(m))
        interactives.append(m)
    }

    // MARK: - Playground

    private func buildPlayground() {
        buildSwing(at: [11.5, -2.5])
        buildSlide(at: [12.5, 3.8])
        buildMerry(at: [8.0, 8.6])
    }

    func buildSwing(at p: SIMD2<Float>) {
        let layout = Layout(origin: p, yaw: yawFacing(from: p, to: .zero))
        let g = group(layout)
        let sw = Interactive(id: "swing", kind: .swing, center: p)
        sw.spots = [layout.world([0, 1.25])]
        let red: UInt32 = 0xE94F64
        var frame: [ModelEntity] = []
        for x: Float in [-1.2, 1.2] {
            for s: Float in [-1, 1] {
                frame.append(cylinder(h: 2.47, r: 0.06, red, at: [x, 1.2, s * 0.3], rotation: rotX(-s * 0.245), in: g))
            }
            addRect(layout.world([x, 0]), half: [0.12, 0.7], yaw: layout.yaw)
        }
        frame.append(cylinder(h: 2.6, r: 0.06, red, at: [0, 2.4, 0], rotation: rotZ(.pi / 2), in: g))

        let pivot = Entity()
        pivot.position = [0, 2.38, 0]
        g.addChild(pivot)
        for x: Float in [-0.28, 0.28] {
            cylinder(h: 1.7, r: 0.018, 0x8A8A92, at: [x, -0.85, 0], in: pivot)
        }
        let board = box([0.7, 0.06, 0.34], 0xFFD45C, at: [0, -1.73, 0], corner: 0.02, in: pivot)
        let seat = Entity()
        seat.position = [0, -1.70, 0]
        pivot.addChild(seat)
        sw.seat = seat
        sw.parts["pivot"] = pivot
        addCircle(p, 0.4)
        tappable(frame + [board], .use(sw))
        interactives.append(sw)
    }

    private func buildSlide(at p: SIMD2<Float>) {
        let layout = Layout(origin: p, yaw: yawFacing(from: p, to: .zero))
        let g = group(layout)
        let sl = Interactive(id: "slide", kind: .slide, center: p)
        sl.spots = [layout.world([0, -2.2])]
        let blue: UInt32 = 0x5DA9E9, yellow: UInt32 = 0xFFD45C
        var parts: [ModelEntity] = []
        for x: Float in [-0.32, 0.32] {
            parts.append(cylinder(h: 1.9, r: 0.04, blue, at: [x, 0.95, -1.5], in: g))
            parts.append(cylinder(h: 1.6, r: 0.05, blue, at: [x * 1.25, 0.8, -0.7], in: g))
        }
        for k in 0..<5 {
            parts.append(box([0.64, 0.04, 0.05], blue, at: [0, 0.3 + Float(k) * 0.32, -1.5], corner: 0.01, in: g))
        }
        parts.append(box([0.9, 0.1, 0.8], yellow, at: [0, 1.6, -1.05], corner: 0.02, in: g, solid: true))
        for x: Float in [-0.45, 0.45] {
            parts.append(box([0.05, 0.35, 0.8], blue, at: [x, 1.82, -1.05], corner: 0.01, in: g))
        }
        let rampPivot = Entity()
        rampPivot.position = [0, 0.925, 0.8]
        rampPivot.orientation = rotX(0.449)
        g.addChild(rampPivot)
        let ramp = box([0.8, 0.06, 3.11], 0xE94F64, at: .zero, corner: 0.02, in: rampPivot, solid: true)
        parts.append(ramp)
        for x: Float in [-0.42, 0.42] {
            parts.append(box([0.05, 0.16, 3.11], yellow, at: [x, 0.08, 0], corner: 0.01, in: rampPivot))
        }
        sl.path = [
            layout.world3([0, 0, -1.75]),     // foot of the ladder
            layout.world3([0, 1.66, -1.2]),   // top of the ladder
            layout.world3([0, 1.66, -0.65]),  // top of the slide
            layout.world3([0, 0.3, 2.2]),     // bottom of the slide
            layout.world3([0, 0, 2.95])       // hop off
        ]
        addRect(layout.world([0, 0.35]), half: [0.5, 1.95], yaw: layout.yaw)
        tappable(parts, .use(sl))
        interactives.append(sl)
    }

    private func buildMerry(at p: SIMD2<Float>) {
        let g = group(Layout(origin: p, yaw: 0))
        let m = Interactive(id: "merry", kind: .merry, center: p)
        m.standRadius = 2.15
        cylinder(h: 0.2, r: 0.35, 0x8A8A92, at: [0, 0.1, 0], in: g)
        let platform = Entity()
        platform.position = [0, 0.25, 0]
        g.addChild(platform)
        let disc = cylinder(h: 0.2, r: 1.5, 0x6EC6FF, at: .zero, in: platform)
        let colors: [UInt32] = [0xFFD45C, 0xE94F64, 0xFFD45C, 0xE94F64]
        for k in 0..<4 {
            let a = Float(k) * .pi / 2
            let wedge = box([0.5, 0.03, 1.3], colors[k], at: [0.75 * sin(a), 0.115, 0.75 * cos(a)], corner: 0.01, in: platform)
            wedge.orientation = rotY(a)
            cylinder(h: 0.6, r: 0.03, 0x4A5060, at: [1.15 * sin(a + .pi / 4), 0.4, 1.15 * cos(a + .pi / 4)], in: platform)
        }
        let pole = cylinder(h: 1.0, r: 0.06, 0x4A5060, at: [0, 0.6, 0], in: platform)
        m.parts["platform"] = platform
        addCircle(p, 1.55)
        tappable([disc, pole], .use(m))
        interactives.append(m)
    }

    // MARK: - Toys

    private func buildToys() {
        let balls: [(SIMD2<Float>, UInt32)] = [
            ([-2.6, -2.9], 0xE94F64), ([2.8, -2.6], 0xFFD45C), ([-7.5, -1.0], 0x5DA9E9),
            ([9.0, 0.2], 0x7FD8BE), ([-3.2, 6.2], 0xC86FC9)
        ]
        for (i, b) in balls.enumerated() {
            let ball = makeBall(id: "ball\(i)", radius: 0.3, hex: b.1, kind: .kick, mass: 0.6)
            ball.entity.position = [b.0.x, 0.302, b.0.y]
            ball.home = ball.entity.transform
        }

        // Two little block towers (3 + 2 + 1) to knock over and build again.
        let woods: [UInt32] = [0xE8C9A9, 0xFFD45C, 0x7FD8BE, 0xFF8FB1, 0x6EC6FF, 0xD9B98F]
        let towers: [SIMD2<Float>] = [[-10.2, 2.4], [-8.4, 6.6]]
        var n = 0
        for c in towers {
            let rows: [[Float]] = [[-0.44, 0, 0.44], [-0.22, 0.22], [0]]
            for (level, xs) in rows.enumerated() {
                for x in xs {
                    let y = 0.212 + Float(level) * 0.424
                    makeBlock(id: "block\(n)", at: [c.x + x, y, c.y], hex: woods[n % woods.count])
                    n += 1
                }
            }
        }
    }

    @discardableResult
    func makeBall(id: String, radius r: Float, hex: UInt32, kind: Prop.Kind, mass: Float) -> Prop {
        let e = ModelEntity(mesh: .generateSphere(radius: r),
                            materials: [SimpleMaterial(color: UIColor(hex: hex), roughness: .float(0.35), isMetallic: false)])
        // A white band so you can see it roll.
        let band = ModelEntity(mesh: .generateCylinder(height: r * 0.35, radius: r * 1.01), materials: [Self.mat(0xFFFFFF, rough: 0.4)])
        e.addChild(band)
        let shape = ShapeResource.generateSphere(radius: r)
        e.collision = CollisionComponent(shapes: [shape])
        e.physicsBody = PhysicsBodyComponent(
            massProperties: .init(shape: shape, mass: mass),
            material: .generate(staticFriction: 0.6, dynamicFriction: 0.5, restitution: 0.55),
            mode: .dynamic)
        root.addChild(e)
        let prop = Prop(id: id, kind: kind, entity: e, radius: r, lift: r, mass: mass)
        props.append(prop)
        tapTargets[ObjectIdentifier(e)] = .prop(prop)
        return prop
    }

    @discardableResult
    func makeBlock(id: String, at p: SIMD3<Float>, hex: UInt32) -> Prop {
        let size: Float = 0.42
        let e = ModelEntity(mesh: .generateBox(size: size, cornerRadius: 0.04), materials: [Self.mat(hex, rough: 0.7)])
        e.position = p
        let shape = ShapeResource.generateBox(size: [size, size, size])
        e.collision = CollisionComponent(shapes: [shape])
        e.physicsBody = PhysicsBodyComponent(
            massProperties: .init(shape: shape, mass: 0.8),
            material: .generate(staticFriction: 0.9, dynamicFriction: 0.7, restitution: 0.15),
            mode: .dynamic)
        root.addChild(e)
        let prop = Prop(id: id, kind: .carry, entity: e, radius: 0.3, lift: size / 2, mass: 0.8)
        prop.home = e.transform
        props.append(prop)
        tapTargets[ObjectIdentifier(e)] = .prop(prop)
        return prop
    }

    @discardableResult
    func pot(id: String, at p: SIMD2<Float>, flower: UInt32, y: Float = 0) -> Prop {
        let e = ModelEntity(mesh: .generateCylinder(height: 0.34, radius: 0.2), materials: [Self.mat(0xD9774A)])
        e.position = [p.x, y + 0.172, p.y]
        cylinder(h: 0.06, r: 0.23, 0xC9673A, at: [0, 0.15, 0], in: e)
        sphere(0.2, 0x6FBF5A, at: [0, 0.3, 0], in: e)
        let flowers: [SIMD3<Float>] = [[0.1, 0.46, 0.02], [-0.09, 0.44, 0.08], [0.0, 0.47, -0.1]]
        for f in flowers { sphere(0.065, flower, at: f, in: e) }
        let shape = ShapeResource.generateBox(size: [0.42, 0.62, 0.42]).offsetBy(translation: [0, 0.14, 0])
        e.collision = CollisionComponent(shapes: [shape])
        e.physicsBody = PhysicsBodyComponent(
            massProperties: .init(shape: shape, mass: 1.2),
            material: .generate(staticFriction: 0.9, dynamicFriction: 0.7, restitution: 0.1),
            mode: .dynamic)
        root.addChild(e)
        let prop = Prop(id: id, kind: .carry, entity: e, radius: 0.24, lift: 0.17, mass: 1.2)
        prop.home = e.transform
        props.append(prop)
        tapTargets[ObjectIdentifier(e)] = .prop(prop)
        return prop
    }
}
