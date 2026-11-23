import RealityKit
import UIKit

/// The stairs in the big house: where to start, where they arrive, and the climbing moves
/// (in two halves, so the floor can switch in the middle of the climb).
struct Stairs {
    let bottom: SIMD2<Float>
    let top: SIMD2<Float>
    let up1: [Walker.Key]
    let up2: [Walker.Key]
    let down1: [Walker.Key]
    let down2: [Walker.Key]
}

/// A wall (or window) of the big house: faded when it stands between the camera and the animal.
struct BigWall {
    let entity: ModelEntity
    let center: SIMD2<Float>
    let half: SIMD2<Float>
    let level: Int
}

/// Where a piece goes: what you see, and the twin you bump into.
/// Downstairs they are the same entity. Upstairs they are separate, so the upstairs can be hidden
/// (while the animal is downstairs) and the toys up there still stand on something.
struct Place {
    let look: Entity
    let solid: Entity
    let level: Int
}

/// The big two-story house, just south of the square.
///
/// Downstairs: family room with a TV and sofa, kitchen (fridge, stove, sink, table), bathroom
/// (bath, toilet, sink). Upstairs: two bedrooms with wardrobes, and a playroom (ball pit,
/// rocking horse, toy box). Stairs in the back right corner. Sizes in metres, house-local
/// x -5...5 and z -4...4 (front at z -4, facing the square).
extension Village {
    static let bigOrigin = SIMD2<Float>(-0.5, 11.8)

    var bigHouse: House? { bigHouseIndex.map { houses[$0] } }

    /// A house-local spot on the ground, in the world.
    func hp(_ x: Float, _ z: Float) -> SIMD2<Float> { Self.bigOrigin + SIMD2<Float>(x, z) }

    /// A house-local point in the world, `y` above the ground.
    func hp3(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
        SIMD3<Float>(Self.bigOrigin.x + x, y, Self.bigOrigin.y + z)
    }

    /// The ball pit, when `prop` is one of its balls still lying in it.
    func pit(holding prop: Prop) -> Interactive? {
        let p = prop.entity.position(relativeTo: nil)
        return interactives.first { t in
            t.kind == .ballPit && t.contents.contains { $0 === prop }
                && simd_distance(flat(p), t.center) < 0.75 && p.y < Float(t.level) * Self.floorHeight + 0.6
        }
    }

    /// Which floor a point in the world is on.
    func level(at p: SIMD3<Float>) -> Int {
        guard p.y > 2.6, let big = bigHouse, big.contains(flat(p)) else { return 0 }
        return 1
    }

    // MARK: - Helpers

    /// A child place at house-local (x, z), turned by `yaw`.
    func place(_ local: SIMD2<Float>, yaw: Float, in parent: Place) -> Place {
        let a = Entity()
        a.position = [local.x, 0, local.y]
        a.orientation = rotY(yaw)
        parent.look.addChild(a)
        if parent.look === parent.solid { return Place(look: a, solid: a, level: parent.level) }
        let b = Entity()
        b.position = a.position
        b.orientation = a.orientation
        parent.solid.addChild(b)
        return Place(look: a, solid: b, level: parent.level)
    }

    @discardableResult
    func piece(_ size: SIMD3<Float>, _ hex: UInt32, at p: SIMD3<Float>, corner: Float = 0.03,
               in place: Place, solid: Bool = false) -> ModelEntity {
        let same = place.look === place.solid
        let e = box(size, hex, at: p, corner: corner, in: place.look, solid: solid && same)
        if solid && !same {
            let twin = Entity()
            twin.position = p
            place.solid.addChild(twin)
            Self.makeSolid(twin, .generateBox(size: size))
        }
        return e
    }

    /// A wall between house-local x0...x1 and z0...z1, `h` high from `y0`.
    @discardableResult
    func bigWall(_ place: Place, x0: Float, x1: Float, z0: Float, z1: Float, y0: Float = 0, h: Float,
                 hex: UInt32, blocks: Bool = true) -> ModelEntity {
        let size = SIMD3<Float>(x1 - x0, h, z1 - z0)
        let e = piece(size, hex, at: [(x0 + x1) / 2, y0 + h / 2, (z0 + z1) / 2], corner: 0.02, in: place, solid: true)
        bigWalls.append(BigWall(entity: e, center: hp((x0 + x1) / 2, (z0 + z1) / 2), half: [size.x / 2, size.z / 2], level: place.level))
        if blocks {
            addRect(hp((x0 + x1) / 2, (z0 + z1) / 2), half: [size.x / 2, size.z / 2], yaw: 0, level: place.level)
        }
        return e
    }

    /// A window through a wall: a pale blue pane a bit thicker than the wall, with a white sill.
    func bigWindow(_ place: Place, at p: SIMD3<Float>, acrossX: Bool) {
        let pane: SIMD3<Float> = acrossX ? [0.9, 0.8, 0.24] : [0.24, 0.8, 0.9]
        let paneEntity = box(pane, 0xCFEFFF, at: p, corner: 0.01, in: place.look)
        let sill: SIMD3<Float> = acrossX ? [1.0, 0.06, 0.3] : [0.3, 0.06, 1.0]
        let sillEntity = box(sill, 0xFFFFFF, at: p - SIMD3<Float>(0, 0.43, 0), corner: 0.01, in: place.look)
        for (e, size) in [(paneEntity, pane), (sillEntity, sill)] {
            bigWalls.append(BigWall(entity: e, center: hp(p.x, p.z), half: [size.x / 2, size.z / 2], level: place.level))
        }
    }

    // MARK: - The house

    func buildBigHouse() {
        let o = Self.bigOrigin
        let wallHex: UInt32 = 0xFFE9C7
        let innerHex: UInt32 = 0xFFF8EE
        let h = Self.floorHeight

        let g0 = Entity()
        g0.position = [o.x, 0, o.y]
        root.addChild(g0)
        let down = Place(look: g0, solid: g0, level: 0)

        let upper = Entity()
        upper.position = [o.x, h, o.y]
        root.addChild(upper)
        let upperSolid = Entity()
        upperSolid.position = upper.position
        root.addChild(upperSolid)
        let up = Place(look: upper, solid: upperSolid, level: 1)

        // Outside walls, both floors. The front has the door downstairs.
        for place in [down, up] {
            bigWall(place, x0: -4.8, x1: 4.8, z0: 3.8, z1: 4.0, h: h, hex: wallHex)       // back
            bigWall(place, x0: -5.0, x1: -4.8, z0: -4.0, z1: 4.0, h: h, hex: wallHex)     // left
            bigWall(place, x0: 4.8, x1: 5.0, z0: -4.0, z1: 4.0, h: h, hex: wallHex)       // right
        }
        bigWall(down, x0: -4.8, x1: -0.6, z0: -4.0, z1: -3.8, h: h, hex: wallHex)
        bigWall(down, x0: 0.6, x1: 4.8, z0: -4.0, z1: -3.8, h: h, hex: wallHex)
        bigWall(down, x0: -0.6, x1: 0.6, z0: -4.0, z1: -3.8, y0: 2.1, h: h - 2.1, hex: wallHex, blocks: false)
        bigWall(up, x0: -4.8, x1: 4.8, z0: -4.0, z1: -3.8, h: h, hex: wallHex)

        // A stripe between the floors, outside.
        let band: UInt32 = 0xE9C79B
        box([10.2, 0.25, 0.08], band, at: [0, h, -4.04], corner: 0.01, in: g0)
        box([10.2, 0.25, 0.08], band, at: [0, h, 4.04], corner: 0.01, in: g0)
        box([0.08, 0.25, 8.2], band, at: [-5.04, h, 0], corner: 0.01, in: g0)
        box([0.08, 0.25, 8.2], band, at: [5.04, h, 0], corner: 0.01, in: g0)

        // Windows
        for (place, y) in [(down, Float(1.5)), (up, Float(1.6))] {
            for x: Float in [-3.0, 3.0] { bigWindow(place, at: [x, y, -3.9], acrossX: true) }
            for x: Float in [-3.0, 0.0, 3.0] where !(place.level == 0 && x == 3.0) {
                bigWindow(place, at: [x, y, 3.9], acrossX: true)
            }
            for z: Float in [-2.0, 2.0] {
                bigWindow(place, at: [-4.9, y, z], acrossX: false)
                if !(place.level == 0 && z == 2.0) { bigWindow(place, at: [4.9, y, z], acrossX: false) }
            }
        }
        bigWindow(up, at: [0, 1.6, -3.9], acrossX: true)

        // Floors downstairs: wood, tiles in the kitchen and bathroom, a rug by the TV.
        box([9.6, 0.03, 7.6], 0xE3C59B, at: [0, 0.015, 0], corner: 0.005, in: g0)
        box([4.0, 0.01, 3.5], 0xF3EFE4, at: [2.8, 0.034, -2.05], corner: 0.003, in: g0)
        box([4.0, 0.01, 3.0], 0xCFE8F0, at: [-2.8, 0.034, 2.3], corner: 0.003, in: g0)
        box([2.4, 0.01, 1.7], 0xF6B7C6, at: [-3.0, 0.036, -1.5], corner: 0.003, in: g0)

        // The upstairs floor, with a hole over the stairs.
        let slabs: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([7.8, 0.2, 7.6], [-0.9, -0.1, 0]),
            ([1.8, 0.2, 3.6], [3.9, -0.1, -2.0]),
            ([1.8, 0.2, 0.8], [3.9, -0.1, 3.4])
        ]
        var floorPieces: [ModelEntity] = []
        for (size, p) in slabs {
            floorPieces.append(piece(size, 0xE8CFA6, at: p, corner: 0.01, in: up, solid: true))
        }
        tappable(floorPieces, .floor(1))
        box([3.8, 0.01, 4.0], 0xCDE7FF, at: [-2.8, 0.006, -1.7], corner: 0.003, in: upper)
        box([3.8, 0.01, 3.2], 0xFFE0EC, at: [-2.8, 0.006, 2.1], corner: 0.003, in: upper)
        box([5.4, 0.01, 2.2], 0xFFF1A8, at: [2.0, 0.006, -2.6], corner: 0.003, in: upper)

        // Inside walls. Downstairs only the bathroom has walls; the rest is one big room.
        let wh: Float = 2.4
        bigWall(down, x0: -0.875, x1: -0.725, z0: 0.8, z1: 3.8, h: wh, hex: innerHex)
        bigWall(down, x0: -4.8, x1: -2.2, z0: 0.725, z1: 0.875, h: wh, hex: innerHex)
        bigWall(down, x0: -1.0, x1: -0.875, z0: 0.725, z1: 0.875, h: wh, hex: innerHex)
        // Upstairs: two bedrooms on the left, the playroom at the front right, a landing.
        bigWall(up, x0: -0.875, x1: -0.725, z0: -3.8, z1: -1.05, h: wh, hex: innerHex)
        bigWall(up, x0: -0.875, x1: -0.725, z0: 0.15, z1: 1.5, h: wh, hex: innerHex)
        bigWall(up, x0: -0.875, x1: -0.725, z0: 2.7, z1: 3.8, h: wh, hex: innerHex)
        bigWall(up, x0: -4.8, x1: -0.875, z0: 0.325, z1: 0.475, h: wh, hex: innerHex)
        bigWall(up, x0: -0.725, x1: 0.6, z0: -1.475, z1: -1.325, h: wh, hex: innerHex)
        bigWall(up, x0: 2.0, x1: 4.8, z0: -1.475, z1: -1.325, h: wh, hex: innerHex)

        // Front door (opens by itself when an animal walks through; tap to open or close it).
        let doorGroup = Entity()
        doorGroup.position = [0, 0, -3.9]
        doorGroup.orientation = rotY(.pi)
        g0.addChild(doorGroup)
        let door = Interactive(id: "bigdoor", kind: .door, center: hp(0, -3.9))
        door.spots = [hp(0, -4.9), hp(0, -2.9)]
        let hinge = Entity()
        hinge.position = [-0.6, 0, 0]
        doorGroup.addChild(hinge)
        let leaf = box([1.2, 2.05, 0.08], 0xE94F64, at: [0.6, 1.025, 0], corner: 0.02, in: hinge)
        Self.makeSolid(leaf, .generateBox(size: [1.2, 2.05, 0.08]), mode: .kinematic)
        let knob = sphere(0.05, 0xF5C542, at: [1.05, 1.0, 0.07], in: hinge)
        sphere(0.05, 0xF5C542, at: [1.05, 1.0, -0.07], in: hinge)
        door.parts["hinge"] = hinge
        door.obstacle = addRect(door.center, half: [0.6, 0.1], yaw: 0)
        tappable([leaf, knob], .use(door))
        interactives.append(door)
        door.isOn = true
        door.value = 1.7
        hinge.orientation = rotY(1.7)
        if let i = door.obstacle { obstacles[i].enabled = false }

        let roof = cone(h: 2.8, r: 1, 0x4FB3A9, at: [0, 2 * h + 1.4, 0], in: g0)
        roof.scale = [7.2, 1, 5.8]
        houses.append(House(center: o, yaw: 0, halfX: 5, halfZ: 4, roof: roof, upper: upper, top: 2 * h + 2.8, door: door))
        bigHouseIndex = houses.count - 1

        // A path from the square and two flower pots by the door.
        path(from: [-0.5, 6.4], to: [-0.5, 7.75])
        pot(id: "bigpot0", at: hp(-1.6, -4.6), flower: 0xFF8FB1)
        pot(id: "bigpot1", at: hp(1.6, -4.6), flower: 0xFFD45C)

        buildStairs(down: down, up: up)
        buildFamilyRoom(down)
        buildKitchen(down)
        buildBathroom(down)
        buildBedrooms(up)
        buildPlayroom(up)
        pot(id: "bigpot2", at: hp(0.6, 3.3), flower: 0xC86FC9)
        pot(id: "bigpot3", at: hp(0.2, 3.3), flower: 0xFFFFFF, y: h)
    }

    // MARK: - Stairs

    private func buildStairs(down: Place, up: Place) {
        var steps: [ModelEntity] = []
        for i in 0..<10 {
            let top = Float(i + 1) * 0.32
            let z1 = 3.0 - Float(i) * 0.32
            steps.append(piece([1.8, top, 0.32], i % 2 == 0 ? 0xC99A6B : 0xD8AD7E, at: [3.9, top / 2, z1 - 0.16],
                               corner: 0.01, in: down, solid: true))
        }
        tappable(steps, .stairs)
        addRect(hp(3.875, 1.4), half: [0.925, 1.6], yaw: 0, level: 0)

        // A railing around the hole upstairs.
        let rail: UInt32 = 0xFFFFFF
        box([0.1, 0.08, 3.25], rail, at: [3.0, 0.9, 1.4], corner: 0.02, in: up.look)
        box([1.85, 0.08, 0.1], rail, at: [3.9, 0.9, 3.0], corner: 0.02, in: up.look)
        var z: Float = -0.15
        while z < 3.0 {
            box([0.05, 0.9, 0.05], rail, at: [3.0, 0.45, z], corner: 0.01, in: up.look)
            z += 0.35
        }
        for x: Float in [3.35, 3.75, 4.15, 4.55] {
            box([0.05, 0.9, 0.05], rail, at: [x, 0.45, 3.0], corner: 0.01, in: up.look)
        }
        for (size, p) in [(SIMD3<Float>(0.1, 0.95, 3.25), SIMD3<Float>(3.0, 0.475, 1.4)),
                          (SIMD3<Float>(1.85, 0.95, 0.1), SIMD3<Float>(3.9, 0.475, 3.0))] {
            let twin = Entity()
            twin.position = p
            up.solid.addChild(twin)
            Self.makeSolid(twin, .generateBox(size: size))
        }
        addRect(hp(3.875, 1.4), half: [0.925, 1.6], yaw: 0, level: 1)

        let fh = Self.floorHeight
        stairs = Stairs(
            bottom: hp(2.45, 3.3),
            top: hp(3.9, -0.75),
            up1: [
                Walker.Key(position: hp3(3.9, 0, 3.4), yaw: .pi / 2, duration: 0.5),
                Walker.Key(position: hp3(3.9, 0.3, 3.0), yaw: .pi, duration: 0.35, linear: true),
                Walker.Key(position: hp3(3.9, 1.75, 1.45), yaw: .pi, duration: 1.0, linear: true)
            ],
            up2: [
                Walker.Key(position: hp3(3.9, fh, -0.1), yaw: .pi, duration: 1.0, linear: true),
                Walker.Key(position: hp3(3.9, fh, -0.75), yaw: .pi, duration: 0.35)
            ],
            down1: [
                Walker.Key(position: hp3(3.9, fh, -0.1), yaw: 0, duration: 0.4),
                Walker.Key(position: hp3(3.9, 1.75, 1.45), yaw: 0, duration: 1.0, linear: true)
            ],
            down2: [
                Walker.Key(position: hp3(3.9, 0.3, 3.0), yaw: 0, duration: 1.0, linear: true),
                Walker.Key(position: hp3(3.9, 0, 3.4), yaw: 0, duration: 0.3),
                Walker.Key(position: hp3(2.45, 0, 3.3), yaw: -.pi / 2, duration: 0.5)
            ])
    }

    // MARK: - Downstairs

    private func buildFamilyRoom(_ down: Place) {
        // TV on the bathroom wall, facing the sofa.
        let tvLayout = Layout(origin: hp(-3.0, 0.45), yaw: .pi)
        let tvPlace = place([-3.0, 0.45], yaw: .pi, in: down)
        let tv = Interactive(id: "tv", kind: .tv, center: tvLayout.origin)
        tv.spots = [tvLayout.world([0, 1.1])]
        let stand = piece([1.6, 0.5, 0.45], 0x9C6B4E, at: [0, 0.25, 0], in: tvPlace, solid: true)
        let frame = piece([1.4, 0.85, 0.08], 0x2E3440, at: [0, 1.0, -0.08], corner: 0.03, in: tvPlace)
        let screen = box([1.26, 0.72, 0.02], 0x3B4252, at: [0, 1.0, -0.035], corner: 0.01, in: tvPlace.look)
        let dot = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [UnlitMaterial(color: UIColor(hex: 0xFFD45C))])
        dot.position = [0, 1.0, 0.0]
        dot.isEnabled = false
        tvPlace.look.addChild(dot)
        tv.parts["screen"] = screen
        tv.parts["dot"] = dot
        addRect(tv.center, half: [0.8, 0.25], yaw: .pi)
        tappable([stand, frame, screen], .use(tv))
        interactives.append(tv)

        // Sofa against the front wall, facing the TV.
        let sofaLayout = Layout(origin: hp(-3.0, -3.35), yaw: 0)
        let sp = place([-3.0, -3.35], yaw: 0, in: down)
        let sofa = Interactive(id: "sofa", kind: .bench, center: sofaLayout.origin)
        sofa.spots = [sofaLayout.world([0, 0.95])]
        let blue: UInt32 = 0x7FB7E6
        var parts = [
            piece([1.9, 0.42, 0.8], blue, at: [0, 0.21, 0], corner: 0.08, in: sp, solid: true),
            piece([1.9, 0.5, 0.2], blue, at: [0, 0.67, -0.3], corner: 0.08, in: sp, solid: true)
        ]
        for x: Float in [-0.85, 0.85] {
            parts.append(piece([0.2, 0.3, 0.8], blue, at: [x, 0.57, 0], corner: 0.08, in: sp))
        }
        for x: Float in [-0.42, 0.42] {
            parts.append(piece([0.8, 0.1, 0.55], 0xA9D2F2, at: [x, 0.47, 0.08], corner: 0.04, in: sp))
        }
        let seat = Entity()
        seat.position = [0, 0.47, 0.1]
        sp.look.addChild(seat)
        sofa.seat = seat
        addRect(sofa.center, half: [0.95, 0.4], yaw: 0)
        tappable(parts, .use(sofa))
        interactives.append(sofa)

        bigLamp(id: "biglamp0", at: [-4.4, -3.4], spot: [-4.3, -2.5], in: down, shade: 0xFFD45C, table: 0.6)

        let ball = makeBall(id: "ball5", radius: 0.3, hex: 0xFF8FB1, kind: .kick, mass: 0.6)
        ball.entity.position = hp3(-1.5, 0.302, -1.0)
        ball.home = ball.entity.transform
    }

    private func buildKitchen(_ down: Place) {
        let face: Float = -.pi / 2   // along the right wall, facing into the room

        // Fridge: the door opens and closes; food inside.
        let fl = Layout(origin: hp(4.4, -3.2), yaw: face)
        let fp = place([4.4, -3.2], yaw: face, in: down)
        let fridge = Interactive(id: "fridge", kind: .fridge, center: fl.origin)
        fridge.spots = [fl.world([0.2, 1.25])]
        let white: UInt32 = 0xF4F6F8
        let body = piece([0.75, 1.8, 0.6], white, at: [0, 0.9, -0.05], corner: 0.05, in: fp, solid: true)
        var fparts = [body]
        box([0.65, 1.6, 0.02], 0xE6F6FF, at: [0, 0.9, 0.26], corner: 0.005, in: fp.look)
        for (size, p) in [(SIMD3<Float>(0.05, 1.8, 0.1), SIMD3<Float>(-0.35, 0.9, 0.3)),
                          (SIMD3<Float>(0.05, 1.8, 0.1), SIMD3<Float>(0.35, 0.9, 0.3)),
                          (SIMD3<Float>(0.75, 0.05, 0.1), SIMD3<Float>(0, 1.775, 0.3)),
                          (SIMD3<Float>(0.75, 0.1, 0.1), SIMD3<Float>(0, 0.05, 0.3)),
                          (SIMD3<Float>(0.65, 0.02, 0.1), SIMD3<Float>(0, 1.05, 0.3))] {
            fparts.append(box(size, white, at: p, corner: 0.005, in: fp.look))
        }
        sphere(0.07, 0xE94F64, at: [-0.15, 1.15, 0.3], in: fp.look)
        sphere(0.06, 0x7FD8BE, at: [0.0, 1.14, 0.3], in: fp.look)
        box([0.12, 0.24, 0.08], 0xFFFFFF, at: [0.18, 1.2, 0.3], corner: 0.02, in: fp.look)
        box([0.22, 0.1, 0.08], 0xFFD45C, at: [-0.1, 0.4, 0.3], corner: 0.02, in: fp.look)
        sphere(0.06, 0xFF8FB1, at: [0.15, 0.4, 0.3], in: fp.look)
        let fhinge = Entity()
        fhinge.position = [-0.375, 0, 0.35]
        fp.look.addChild(fhinge)
        let fleaf = box([0.75, 1.75, 0.05], 0xFBFCFD, at: [0.375, 0.9, 0.025], corner: 0.03, in: fhinge)
        let handle = box([0.04, 0.5, 0.04], 0xB0B8C0, at: [0.65, 1.0, 0.07], corner: 0.015, in: fhinge)
        fparts += [fleaf, handle]
        fridge.parts["hinge"] = fhinge
        addRect(fridge.center, half: [0.375, 0.375], yaw: face)
        tappable(fparts, .use(fridge))
        interactives.append(fridge)

        // Stove: the pot bubbles and steams.
        let sl = Layout(origin: hp(4.45, -2.25), yaw: face)
        let stp = place([4.45, -2.25], yaw: face, in: down)
        let stove = Interactive(id: "stove", kind: .stove, center: sl.origin)
        stove.spots = [sl.world([0, 0.9])]
        var sparts = [
            piece([0.7, 0.9, 0.65], 0xF0F0F0, at: [0, 0.45, 0], corner: 0.04, in: stp, solid: true),
            box([0.72, 0.03, 0.67], 0x4A5060, at: [0, 0.915, 0], corner: 0.01, in: stp.look),
            box([0.45, 0.3, 0.02], 0x3B4252, at: [0, 0.45, 0.33], corner: 0.02, in: stp.look)
        ]
        for x: Float in [-0.17, 0.17] {
            sparts.append(cylinder(h: 0.02, r: 0.1, 0x2E3440, at: [x, 0.94, 0], in: stp.look))
        }
        for k in 0..<3 {
            sparts.append(sphere(0.03, 0xE94F64, at: [-0.2 + 0.2 * Float(k), 0.8, 0.33], in: stp.look))
        }
        sparts.append(cylinder(h: 0.22, r: 0.15, 0xE94F64, at: [-0.17, 1.05, 0], in: stp.look))
        let lid = Entity()
        lid.position = [-0.17, 1.16, 0]
        stp.look.addChild(lid)
        sparts.append(cylinder(h: 0.03, r: 0.16, 0xC9D3DC, at: [0, 0.015, 0], in: lid))
        sphere(0.03, 0x4A5060, at: [0, 0.05, 0], in: lid)
        stove.parts["lid"] = lid
        for i in 0..<4 {
            let puff = ModelEntity(mesh: .generateSphere(radius: 0.07), materials: [UnlitMaterial(color: .white)])
            puff.isEnabled = false
            stp.look.addChild(puff)
            stove.parts["puff\(i)"] = puff
        }
        addRect(stove.center, half: [0.35, 0.325], yaw: face)
        tappable(sparts, .use(stove))
        interactives.append(stove)

        // Sink: water runs for a moment.
        bigSink(id: "kitchensink", at: [4.45, -1.4], yaw: face, in: down, counter: 0xBFE3D0, width: 0.8)

        // Table with two chairs and apples.
        let tp = place([2.0, -2.3], yaw: 0, in: down)
        piece([1.2, 0.06, 0.9], 0xD9A066, at: [0, 0.7, 0], corner: 0.02, in: tp, solid: true)
        for x: Float in [-0.52, 0.52] {
            for z: Float in [-0.37, 0.37] {
                piece([0.07, 0.67, 0.07], 0xC08A52, at: [x, 0.335, z], corner: 0.01, in: tp)
            }
        }
        addRect(hp(2.0, -2.3), half: [0.6, 0.45], yaw: 0)
        bigChair(id: "chair0", at: [2.0, -3.25], yaw: 0, spot: [1.2, -3.3], in: down)
        bigChair(id: "chair1", at: [2.0, -1.35], yaw: .pi, spot: [1.2, -1.3], in: down)
        makeApple(id: "apple0", at: hp3(1.8, 0.82, -2.3), hex: 0xE94F64)
        makeApple(id: "apple1", at: hp3(2.2, 0.82, -2.15), hex: 0x9BD77A)
        makeApple(id: "apple2", at: hp3(2.05, 0.82, -2.5), hex: 0xE94F64)
    }

    private func buildBathroom(_ down: Place) {
        // Bath: get in and there are bubbles.
        let bl = Layout(origin: hp(-3.6, 3.25), yaw: .pi)
        let bp = place([-3.6, 3.25], yaw: .pi, in: down)
        let tub = Interactive(id: "bathtub", kind: .bathtub, center: bl.origin)
        tub.spots = [bl.world([0, 1.0])]
        let white: UInt32 = 0xFFFFFF
        var parts = [piece([1.8, 0.1, 0.9], white, at: [0, 0.05, 0], corner: 0.03, in: bp, solid: true)]
        for z: Float in [-0.41, 0.41] {
            parts.append(piece([1.8, 0.55, 0.08], white, at: [0, 0.275, z], corner: 0.03, in: bp, solid: true))
        }
        for x: Float in [-0.86, 0.86] {
            parts.append(piece([0.08, 0.55, 0.9], white, at: [x, 0.275, 0], corner: 0.03, in: bp, solid: true))
        }
        let water = ModelEntity(mesh: .generateBox(size: [1.64, 0.02, 0.74]), materials: [Self.water()])
        water.position = [0, 0.42, 0]
        bp.look.addChild(water)
        parts.append(water)
        cylinder(h: 0.15, r: 0.025, 0xB0B8C0, at: [0.75, 0.62, 0], in: bp.look)
        for i in 0..<7 {
            let r = 0.07 + Float(i % 3) * 0.025
            let bubble = ModelEntity(mesh: .generateSphere(radius: r), materials: [Self.mat(0xFFFFFF, rough: 0.3)])
            bubble.position = [-0.6 + Float(i) * 0.2, 0.45, (i % 2 == 0 ? 0.15 : -0.15)]
            bubble.isEnabled = false
            bp.look.addChild(bubble)
            tub.parts["bubble\(i)"] = bubble
        }
        let seat = Entity()
        seat.position = [0, 0.12, 0]
        bp.look.addChild(seat)
        tub.seat = seat
        addRect(tub.center, half: [0.9, 0.45], yaw: .pi)
        tappable(parts, .use(tub))
        interactives.append(tub)

        // Toilet: flush!
        let tl = Layout(origin: hp(-4.4, 1.6), yaw: .pi / 2)
        let tp = place([-4.4, 1.6], yaw: .pi / 2, in: down)
        let toilet = Interactive(id: "toilet", kind: .toilet, center: tl.origin)
        toilet.spots = [tl.world([0, 0.95])]
        var tparts = [
            piece([0.5, 0.5, 0.22], white, at: [0, 0.65, -0.28], corner: 0.05, in: tp, solid: true),
            cylinder(h: 0.38, r: 0.2, white, at: [0, 0.19, 0], in: tp.look),
            cylinder(h: 0.06, r: 0.24, white, at: [0, 0.41, 0.02], in: tp.look),
            box([0.12, 0.03, 0.04], 0xB0B8C0, at: [0.18, 0.82, -0.16], corner: 0.01, in: tp.look)
        ]
        let swirl = ModelEntity(mesh: .generateBox(size: [0.3, 0.01, 0.08]), materials: [Self.water()])
        swirl.position = [0, 0.445, 0.02]
        tp.look.addChild(swirl)
        cylinder(h: 0.01, r: 0.17, 0x8ED3F5, at: [0, 0.44, 0.02], in: tp.look)
        toilet.parts["swirl"] = swirl
        let lidHinge = Entity()
        lidHinge.position = [0, 0.45, -0.2]
        tp.look.addChild(lidHinge)
        tparts.append(cylinder(h: 0.04, r: 0.23, 0xCFE8F0, at: [0, 0.02, 0.22], in: lidHinge))
        toilet.parts["lid"] = lidHinge
        addRect(tl.world([0, -0.08]), half: [0.27, 0.32], yaw: .pi / 2)
        tappable(tparts, .use(toilet))
        interactives.append(toilet)

        // Sink with a mirror.
        bigSink(id: "bathsink", at: [-1.6, 3.5], yaw: .pi, in: down, counter: 0xFFFFFF, width: 0.6)
        box([0.55, 0.6, 0.03], 0xDDF3FF, at: [-1.6, 1.5, 3.77], corner: 0.05, in: down.look)

        makeDuck(id: "duck0", at: hp3(-2.0, 0.11, 2.3))
        makeDuck(id: "duck1", at: hp3(-2.5, 0.11, 1.8))
    }

    // MARK: - Upstairs

    private func buildBedrooms(_ up: Place) {
        bigBed(id: "bigbed0", at: [-3.8, -2.6], yaw: .pi / 2, in: up, blanket: 0x5DA9E9)
        bigWardrobe(id: "wardrobe0", at: [-1.8, -3.45], yaw: 0, in: up, hex: 0xF5D3A0)
        bigBed(id: "bigbed1", at: [-3.8, 2.9], yaw: .pi / 2, in: up, blanket: 0xFF8FB1)
        bigWardrobe(id: "wardrobe1", at: [-1.6, 3.45], yaw: .pi, in: up, hex: 0xD7ECFF)
        bigLamp(id: "biglamp1", at: [-4.45, 1.85], spot: [-3.65, 1.5], in: up, shade: 0xFF8FB1, table: 0.5)
    }

    private func buildPlayroom(_ up: Place) {
        let h = Self.floorHeight
        bigToyBox(id: "bigtoybox", at: [4.25, -2.0], yaw: -.pi / 2, in: up)

        // Ball pit: jump in!
        let pitPlace = place([2.3, -2.9], yaw: 0, in: up)
        let pit = Interactive(id: "ballpit", kind: .ballPit, center: hp(2.3, -2.9))
        pit.level = 1
        pit.spots = [hp(2.3, -1.85)]
        var parts = [piece([1.3, 0.03, 1.3], 0xFFFFFF, at: [0, 0.015, 0], corner: 0.01, in: pitPlace, solid: true)]
        for z: Float in [-0.66, 0.66] {
            parts.append(piece([1.4, 0.35, 0.08], 0x6EC6FF, at: [0, 0.175, z], corner: 0.03, in: pitPlace, solid: true))
        }
        for x: Float in [-0.66, 0.66] {
            parts.append(piece([0.08, 0.35, 1.4], 0xFF8FB1, at: [x, 0.175, 0], corner: 0.03, in: pitPlace, solid: true))
        }
        let pitSeat = Entity()
        pitSeat.position = [0, 0.12, 0]
        pitPlace.look.addChild(pitSeat)
        pit.seat = pitSeat
        let colors: [UInt32] = [0xE94F64, 0xFFD45C, 0x5DA9E9, 0x7FD8BE, 0xC86FC9]
        for i in 0..<24 {
            let gx = Float(i % 5), gz = Float(i / 5)
            let ball = makeBall(id: "pit\(i)", radius: 0.1, hex: colors[i % colors.count], kind: .carry, mass: 0.1)
            ball.entity.position = hp3(2.3 - 0.44 + gx * 0.22, h + 0.14, -2.9 - 0.44 + gz * 0.22)
            ball.home = ball.entity.transform
            pit.contents.append(ball)
        }
        addRect(pit.center, half: [0.7, 0.7], yaw: 0, level: 1)
        tappable(parts, .use(pit))
        interactives.append(pit)

        // Rocking horse.
        let rl = Layout(origin: hp(0.35, -2.7), yaw: .pi / 2)
        let rp = place([0.35, -2.7], yaw: .pi / 2, in: up)
        let horse = Interactive(id: "rocker", kind: .rocker, center: rl.origin)
        horse.level = 1
        horse.spots = [hp(0.35, -1.85)]
        let pivot = Entity()
        rp.look.addChild(pivot)
        let wood: UInt32 = 0xC89B6D, coat: UInt32 = 0xF5D3A0, mane: UInt32 = 0x8A5A3A
        var hparts: [ModelEntity] = []
        for x: Float in [-0.18, 0.18] {
            hparts.append(box([0.06, 0.06, 1.1], wood, at: [x, 0.04, 0], corner: 0.02, in: pivot))
            for z: Float in [-0.3, 0.3] {
                hparts.append(cylinder(h: 0.3, r: 0.03, coat, at: [x * 0.8, 0.22, z], in: pivot))
            }
        }
        hparts.append(box([0.3, 0.28, 0.7], coat, at: [0, 0.48, 0], corner: 0.1, in: pivot))
        let head = box([0.22, 0.34, 0.28], coat, at: [0, 0.78, 0.42], corner: 0.08, in: pivot)
        head.orientation = rotX(-0.35)
        hparts.append(head)
        hparts.append(box([0.06, 0.32, 0.16], mane, at: [0, 0.8, 0.3], corner: 0.03, in: pivot))
        hparts.append(box([0.06, 0.25, 0.08], mane, at: [0, 0.5, -0.38], corner: 0.03, in: pivot))
        hparts.append(box([0.32, 0.04, 0.26], 0xE94F64, at: [0, 0.63, -0.05], corner: 0.02, in: pivot))
        sphere(0.025, 0x2E3440, at: [0.1, 0.86, 0.48], in: pivot)
        sphere(0.025, 0x2E3440, at: [-0.1, 0.86, 0.48], in: pivot)
        let saddle = Entity()
        saddle.position = [0, 0.64, -0.05]
        pivot.addChild(saddle)
        horse.seat = saddle
        horse.parts["pivot"] = pivot
        addRect(horse.center, half: [0.25, 0.6], yaw: .pi / 2, level: 1)
        tappable(hparts, .use(horse))
        interactives.append(horse)

        // Three blocks and a ball.
        let blockColors: [UInt32] = [0xFF8FB1, 0x6EC6FF, 0xFFD45C]
        makeBlock(id: "block12", at: hp3(3.6, h + 0.212, -3.4), hex: blockColors[0])
        makeBlock(id: "block13", at: hp3(4.05, h + 0.212, -3.4), hex: blockColors[1])
        makeBlock(id: "block14", at: hp3(3.825, h + 0.636, -3.4), hex: blockColors[2])
        let ball = makeBall(id: "ball6", radius: 0.22, hex: 0x7FD8BE, kind: .kick, mass: 0.4)
        ball.entity.position = hp3(1.2, h + 0.222, -3.3)
        ball.home = ball.entity.transform
    }

    // MARK: - Furniture

    private func bigLamp(id: String, at local: SIMD2<Float>, spot: SIMD2<Float>, in parent: Place,
                         shade: UInt32, table: Float) {
        let lamp = Interactive(id: id, kind: .lamp, center: hp(local.x, local.y))
        lamp.level = parent.level
        lamp.spots = [hp(spot.x, spot.y)]
        let p = place(local, yaw: 0, in: parent)
        let t = piece([table, 0.6, table], 0xB07A50, at: [0, 0.3, 0], in: p, solid: true)
        let base = cylinder(h: 0.05, r: 0.13, 0x4A5060, at: [0, 0.625, 0], in: p.look)
        let stem = cylinder(h: 0.45, r: 0.025, 0x4A5060, at: [0, 0.875, 0], in: p.look)
        let bulb = sphere(0.08, 0xF2F2F2, at: [0, 1.06, 0], in: p.look)
        let hat = cone(h: 0.28, r: 0.24, shade, at: [0, 1.2, 0], in: p.look)
        let light = PointLight()
        light.light.color = UIColor(hex: 0xFFD9A0)
        light.light.intensity = 12000
        light.light.attenuationRadius = 4.5
        light.position = [0, 1.0, 0]
        light.isEnabled = false
        p.look.addChild(light)
        lamp.parts["bulb"] = bulb
        lamp.light = light
        addRect(lamp.center, half: [table / 2, table / 2], yaw: 0, level: parent.level)
        tappable([t, base, stem, bulb, hat], .use(lamp))
        interactives.append(lamp)
    }

    private func bigSink(id: String, at local: SIMD2<Float>, yaw: Float, in parent: Place, counter: UInt32, width: Float) {
        let l = Layout(origin: hp(local.x, local.y), yaw: yaw)
        let p = place(local, yaw: yaw, in: parent)
        let sink = Interactive(id: id, kind: .sink, center: l.origin)
        sink.level = parent.level
        sink.spots = [l.world([0, 0.9])]
        let steel: UInt32 = 0xB0B8C0
        var parts = [
            piece([width, 0.9, 0.5], counter, at: [0, 0.45, 0], corner: 0.04, in: p, solid: true),
            box([width + 0.02, 0.04, 0.52], 0xF4F1EA, at: [0, 0.92, 0], corner: 0.01, in: p.look),
            box([width * 0.55, 0.03, 0.28], 0x9AA4AE, at: [0, 0.935, 0.04], corner: 0.01, in: p.look),
            cylinder(h: 0.3, r: 0.025, steel, at: [0, 1.09, -0.18], in: p.look),
            box([0.04, 0.04, 0.16], steel, at: [0, 1.23, -0.11], corner: 0.015, in: p.look)
        ]
        parts.append(sphere(0.035, 0x5DA9E9, at: [0.12, 0.98, -0.18], in: p.look))
        let jet = ModelEntity(mesh: .generateCylinder(height: 0.27, radius: 0.02), materials: [Self.water()])
        jet.position = [0, 1.08, -0.04]
        jet.isEnabled = false
        p.look.addChild(jet)
        sink.parts["jet"] = jet
        addRect(sink.center, half: [width / 2, 0.25], yaw: yaw, level: parent.level)
        tappable(parts, .use(sink))
        interactives.append(sink)
    }

    private func bigChair(id: String, at local: SIMD2<Float>, yaw: Float, spot: SIMD2<Float>, in parent: Place) {
        let l = Layout(origin: hp(local.x, local.y), yaw: yaw)
        let p = place(local, yaw: yaw, in: parent)
        let chair = Interactive(id: id, kind: .bench, center: l.origin)
        chair.level = parent.level
        chair.spots = [hp(spot.x, spot.y)]
        let wood: UInt32 = 0xE8A86B
        var parts = [
            piece([0.45, 0.06, 0.45], wood, at: [0, 0.45, 0], corner: 0.02, in: p, solid: true),
            piece([0.45, 0.5, 0.06], wood, at: [0, 0.72, -0.2], corner: 0.02, in: p)
        ]
        for x: Float in [-0.18, 0.18] {
            for z: Float in [-0.18, 0.18] {
                parts.append(piece([0.05, 0.42, 0.05], wood, at: [x, 0.21, z], corner: 0.01, in: p))
            }
        }
        let seat = Entity()
        seat.position = [0, 0.48, 0.02]
        p.look.addChild(seat)
        chair.seat = seat
        addRect(chair.center, half: [0.25, 0.25], yaw: yaw, level: parent.level)
        tappable(parts, .use(chair))
        interactives.append(chair)
    }

    private func bigBed(id: String, at local: SIMD2<Float>, yaw: Float, in parent: Place, blanket: UInt32) {
        let l = Layout(origin: hp(local.x, local.y), yaw: yaw)
        let p = place(local, yaw: yaw, in: parent)
        let bed = Interactive(id: id, kind: .bed, center: l.origin)
        bed.level = parent.level
        bed.spots = [l.world([0, 1.45])]
        let parts = [
            piece([1.2, 0.35, 1.8], 0xB07A50, at: [0, 0.175, 0], in: p, solid: true),
            piece([1.1, 0.12, 1.7], 0xF4F1EA, at: [0, 0.41, 0], corner: 0.05, in: p, solid: true),
            piece([0.8, 0.12, 0.35], 0xFFFFFF, at: [0, 0.52, -0.65], corner: 0.05, in: p),
            piece([1.14, 0.05, 1.05], blanket, at: [0, 0.49, 0.38], corner: 0.02, in: p),
            piece([1.2, 0.75, 0.08], 0x9C6B4E, at: [0, 0.375, -0.88], corner: 0.03, in: p, solid: true)
        ]
        let top = Entity()
        top.position = [0, 0.5, 0.1]
        p.look.addChild(top)
        bed.seat = top
        addRect(bed.center, half: [0.6, 0.9], yaw: yaw, level: parent.level)
        tappable(parts, .use(bed))
        interactives.append(bed)
    }

    /// Opens its doors and the outfit chooser.
    private func bigWardrobe(id: String, at local: SIMD2<Float>, yaw: Float, in parent: Place, hex: UInt32) {
        let l = Layout(origin: hp(local.x, local.y), yaw: yaw)
        let p = place(local, yaw: yaw, in: parent)
        let w = Interactive(id: id, kind: .wardrobe, center: l.origin)
        w.level = parent.level
        w.spots = [l.world([0, 1.15])]
        var parts = [piece([1.2, 2.0, 0.45], hex, at: [0, 1.0, -0.075], corner: 0.04, in: p, solid: true)]
        box([1.1, 1.85, 0.02], 0x8A5A3A, at: [0, 1.0, 0.16], corner: 0.005, in: p.look)
        for (size, c) in [(SIMD3<Float>(0.05, 2.0, 0.14), SIMD3<Float>(-0.575, 1.0, 0.21)),
                          (SIMD3<Float>(0.05, 2.0, 0.14), SIMD3<Float>(0.575, 1.0, 0.21)),
                          (SIMD3<Float>(1.2, 0.05, 0.14), SIMD3<Float>(0, 1.975, 0.21)),
                          (SIMD3<Float>(1.2, 0.1, 0.14), SIMD3<Float>(0, 0.05, 0.21))] {
            parts.append(box(size, hex, at: c, corner: 0.01, in: p.look))
        }
        cylinder(h: 1.05, r: 0.012, 0xB0B8C0, at: [0, 1.72, 0.2], rotation: rotZ(.pi / 2), in: p.look)
        let clothes: [UInt32] = [0xE94F64, 0xFFD45C, 0x7FD8BE, 0xC86FC9]
        for (i, c) in clothes.enumerated() {
            box([0.22, 0.42, 0.06], c, at: [-0.36 + 0.24 * Float(i), 1.46, 0.2], corner: 0.03, in: p.look)
        }
        box([1.1, 0.03, 0.12], 0x9C6B4E, at: [0, 0.7, 0.2], corner: 0.01, in: p.look)
        box([0.3, 0.1, 0.1], 0x5DA9E9, at: [-0.3, 0.765, 0.2], corner: 0.02, in: p.look)
        cylinder(h: 0.02, r: 0.13, 0xFF8FB1, at: [0.25, 0.73, 0.2], in: p.look)
        cylinder(h: 0.1, r: 0.07, 0xFF8FB1, at: [0.25, 0.79, 0.2], in: p.look)

        for side: Float in [-1, 1] {
            let hinge = Entity()
            hinge.position = [0.575 * side, 0, 0.3]
            p.look.addChild(hinge)
            parts.append(box([0.575, 1.9, 0.04], hex, at: [-0.2875 * side, 1.0, 0], corner: 0.02, in: hinge))
            parts.append(sphere(0.03, 0xF5C542, at: [-0.5 * side, 1.0, 0.03], in: hinge))
            w.parts[side < 0 ? "left" : "right"] = hinge
        }
        addRect(w.center, half: [0.6, 0.3], yaw: yaw, level: parent.level)
        tappable(parts, .use(w))
        interactives.append(w)
    }

    private func bigToyBox(id: String, at local: SIMD2<Float>, yaw: Float, in parent: Place) {
        let l = Layout(origin: hp(local.x, local.y), yaw: yaw)
        let p = place(local, yaw: yaw, in: parent)
        let toy = Interactive(id: id, kind: .toyBox, center: l.origin)
        toy.level = parent.level
        toy.spots = [l.world([0, 0.85])]
        let blue: UInt32 = 0x5DA9E9
        let panels = [
            piece([0.9, 0.05, 0.7], blue, at: [0, 0.025, 0], corner: 0.01, in: p, solid: true),
            piece([0.05, 0.55, 0.7], blue, at: [-0.425, 0.3, 0], corner: 0.01, in: p, solid: true),
            piece([0.05, 0.55, 0.7], blue, at: [0.425, 0.3, 0], corner: 0.01, in: p, solid: true),
            piece([0.9, 0.55, 0.05], blue, at: [0, 0.3, -0.325], corner: 0.01, in: p, solid: true),
            piece([0.9, 0.55, 0.05], blue, at: [0, 0.3, 0.325], corner: 0.01, in: p, solid: true)
        ]
        let hinge = Entity()
        hinge.position = [0, 0.58, -0.35]
        p.look.addChild(hinge)
        let lid = box([0.94, 0.05, 0.74], 0xFF8FB1, at: [0, 0.025, 0.37], corner: 0.015, in: hinge)
        toy.parts["lid"] = hinge
        addRect(toy.center, half: [0.45, 0.35], yaw: yaw, level: parent.level)
        tappable(panels + [lid], .use(toy))
        let spots: [SIMD3<Float>] = [[-0.22, 0.17, 0.0], [0.02, 0.17, 0.12], [0.24, 0.17, -0.1]]
        let colors: [UInt32] = [0xE94F64, 0xFFD45C, 0x7FD8BE]
        for (j, s) in spots.enumerated() {
            let ball = makeBall(id: "\(id)ball\(j)", radius: 0.12, hex: colors[j], kind: .carry, mass: 0.2)
            ball.entity.setPosition(s, relativeTo: p.look)
            ball.home = ball.entity.transform
            toy.contents.append(ball)
        }
        interactives.append(toy)
    }

    // MARK: - Small toys

    @discardableResult
    func makeApple(id: String, at p: SIMD3<Float>, hex: UInt32) -> Prop {
        let r: Float = 0.09
        let e = ModelEntity(mesh: .generateSphere(radius: r),
                            materials: [SimpleMaterial(color: UIColor(hex: hex), roughness: .float(0.35), isMetallic: false)])
        cylinder(h: 0.05, r: 0.012, 0x8A5A3A, at: [0, r + 0.015, 0], in: e)
        box([0.05, 0.01, 0.03], 0x6FBF5A, at: [0.025, r + 0.03, 0], corner: 0.004, in: e)
        let shape = ShapeResource.generateSphere(radius: r)
        e.collision = CollisionComponent(shapes: [shape])
        e.physicsBody = PhysicsBodyComponent(
            massProperties: .init(shape: shape, mass: 0.15),
            material: .generate(staticFriction: 0.7, dynamicFriction: 0.6, restitution: 0.3),
            mode: .dynamic)
        e.position = p
        root.addChild(e)
        let prop = Prop(id: id, kind: .carry, entity: e, radius: 0.12, lift: r, mass: 0.15)
        prop.home = e.transform
        props.append(prop)
        tapTargets[ObjectIdentifier(e)] = .prop(prop)
        return prop
    }

    @discardableResult
    func makeDuck(id: String, at p: SIMD3<Float>) -> Prop {
        let e = ModelEntity(mesh: .generateSphere(radius: 0.1), materials: [Self.mat(0xFFD45C, rough: 0.35)])
        sphere(0.04, 0xFFD45C, at: [0, 0.03, -0.08], in: e)   // little tail
        sphere(0.065, 0xFFD45C, at: [0, 0.09, 0.06], in: e)
        box([0.05, 0.025, 0.06], 0xF28C38, at: [0, 0.085, 0.13], corner: 0.01, in: e)
        sphere(0.012, 0x2E3440, at: [0.035, 0.11, 0.1], in: e)
        sphere(0.012, 0x2E3440, at: [-0.035, 0.11, 0.1], in: e)
        let shape = ShapeResource.generateSphere(radius: 0.11)
        e.collision = CollisionComponent(shapes: [shape])
        e.physicsBody = PhysicsBodyComponent(
            massProperties: .init(shape: shape, mass: 0.15),
            material: .generate(staticFriction: 0.8, dynamicFriction: 0.7, restitution: 0.3),
            mode: .dynamic)
        e.position = p
        root.addChild(e)
        let prop = Prop(id: id, kind: .carry, entity: e, radius: 0.14, lift: 0.11, mass: 0.15)
        prop.home = e.transform
        props.append(prop)
        tapTargets[ObjectIdentifier(e)] = .prop(prop)
        return prop
    }
}
