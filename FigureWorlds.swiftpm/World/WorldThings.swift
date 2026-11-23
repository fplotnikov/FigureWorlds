import RealityKit
import UIKit

// MARK: - The places

/// The places he can go. All are open from the start; the map button jumps to any of them.
enum SceneKind: String, CaseIterable, Identifiable {
    case village, pond, snow, workshop, carnival
    var id: String { rawValue }

    /// The picture on the map button (no text to read).
    var emoji: String {
        switch self {
        case .village: "🏡"
        case .pond: "🦆"
        case .snow: "⛄"
        case .workshop: "🤖"
        case .carnival: "🎠"
        }
    }

    var name: String {
        switch self {
        case .village: "Cozy Village"
        case .pond: "Forest Pond"
        case .snow: "Snowy Hill"
        case .workshop: "Robot Workshop"
        case .carnival: "Night Carnival"
        }
    }

    var sky: UInt32 {
        switch self {
        case .village: 0xBFE6FF
        case .pond: 0xC9EBE0
        case .snow: 0xDCEAF6
        case .workshop: 0xFFE3C4
        case .carnival: 0x2B3263
        }
    }

    static let storageKey = "figureWorlds.scene"

    static var saved: SceneKind {
        SceneKind(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .village
    }
}

// MARK: - Small math helpers (the world is flat: x and z on the ground, y up)

/// Turns a ground vector (x, z) by `a` about +y, the same way an entity with
/// orientation `rotY(a)` turns its local x and z.
func rotateY(_ v: SIMD2<Float>, _ a: Float) -> SIMD2<Float> {
    let c = cos(a), s = sin(a)
    return SIMD2<Float>(v.x * c + v.y * s, -v.x * s + v.y * c)
}

func rotY(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 1, 0]) }
func rotX(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [1, 0, 0]) }
func rotZ(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 0, 1]) }

/// A point on the ground (x, z).
func flat(_ v: SIMD3<Float>) -> SIMD2<Float> { SIMD2<Float>(v.x, v.z) }

/// The yaw that makes something at `p` face `q` (figures face +z at yaw 0).
func yawFacing(from p: SIMD2<Float>, to q: SIMD2<Float>) -> Float {
    atan2(q.x - p.x, q.y - p.y)
}

/// The shortest signed turn from angle `a` to angle `b`.
func angleDiff(_ b: Float, _ a: Float) -> Float {
    var d = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
    if d > .pi { d -= 2 * .pi }
    if d < -.pi { d += 2 * .pi }
    return d
}

func turnToward(_ a: Float, _ b: Float, _ k: Float) -> Float {
    a + angleDiff(b, a) * min(1, max(0, k))
}

func ease(_ a: Float, _ b: Float, _ k: Float) -> Float {
    a + (b - a) * min(1, max(0, k))
}

func smoothStep(_ x: Float) -> Float {
    let c = min(max(x, 0), 1)
    return c * c * (3 - 2 * c)
}

// MARK: - Walls and posts the animals walk around

/// A rectangle or circle on the ground. Animals are circles and are pushed out of these.
struct Obstacle {
    enum Shape {
        case rect(halfX: Float, halfZ: Float, yaw: Float)
        case circle(radius: Float)
    }

    var center: SIMD2<Float>
    var shape: Shape
    var enabled = true
    /// 0 = the ground (and downstairs), 1 = upstairs in the big house.
    var level = 0
    /// Things that block the camera's view (trees, pines, lamp posts). Nil for everything else.
    var view: ViewBlock? = nil

    /// How a tall thing blocks the camera: a thin trunk, a wide crown higher up.
    struct ViewBlock {
        var crown: Float
        var crownBottom: Float
        var top: Float
        /// How wide it blocks below the crown, when not the obstacle itself (a carousel's middle pole).
        var trunk: Float? = nil
    }

    /// Pushes a circle at `p` with radius `r` out of this obstacle.
    func pushOut(_ p: SIMD2<Float>, radius r: Float) -> SIMD2<Float> {
        guard enabled else { return p }
        switch shape {
        case .circle(let radius):
            let d = p - center
            let len = simd_length(d)
            let minD = radius + r
            if len >= minD { return p }
            if len < 0.0001 { return center + SIMD2<Float>(minD, 0) }
            return center + d / len * minD

        case .rect(let hx, let hz, let yaw):
            let l = rotateY(p - center, -yaw)
            let q = SIMD2<Float>(min(max(l.x, -hx), hx), min(max(l.y, -hz), hz))
            let diff = l - q
            let dist = simd_length(diff)
            if dist >= r { return p }
            var out: SIMD2<Float>
            if dist > 0.0001 {
                out = q + diff / dist * r
            } else {
                // The middle is inside: leave by the closest side.
                let px = hx - abs(l.x)
                let pz = hz - abs(l.y)
                if px < pz {
                    out = SIMD2<Float>((l.x < 0 ? -1 : 1) * (hx + r), l.y)
                } else {
                    out = SIMD2<Float>(l.x, (l.y < 0 ? -1 : 1) * (hz + r))
                }
            }
            return center + rotateY(out, yaw)
        }
    }
}

/// Places things in a local frame (origin on the ground, local +z = `yaw`).
struct Layout {
    let origin: SIMD2<Float>
    let yaw: Float

    func world(_ l: SIMD2<Float>) -> SIMD2<Float> { origin + rotateY(l, yaw) }

    func world3(_ l: SIMD3<Float>) -> SIMD3<Float> {
        let w = world(SIMD2<Float>(l.x, l.z))
        return SIMD3<Float>(w.x, l.y, w.y)
    }
}

// MARK: - Things in the world

/// Something the animals can move: kicked (big balls) or carried (blocks, pots, small balls).
final class Prop {
    enum Kind { case kick, carry }

    let id: String
    let kind: Kind
    let entity: ModelEntity
    /// Footprint on the ground, for pushing.
    let radius: Float
    /// How far the middle sits above the head when carried (half its height).
    let lift: Float
    let mass: Float
    /// Where it starts, and where "Tidy up" puts it back.
    var home = Transform()
    /// A snowball that gets bigger as it rolls.
    var grows = false

    init(id: String, kind: Kind, entity: ModelEntity, radius: Float, lift: Float, mass: Float) {
        self.id = id
        self.kind = kind
        self.entity = entity
        self.radius = radius
        self.lift = lift
        self.mass = mass
    }
}

/// Something the animal walks to and uses: doors, lamps, the bell, seats, the slide...
final class Interactive {
    enum Kind {
        case door, lamp, streetLamp, bell, mailbox, fountain, bench, swing, slide, merry, bed, toyBox
        // The big house
        case tv, fridge, stove, sink, bathtub, toilet, wardrobe, rocker, ballPit
        // Forest Pond
        case stones, boat, duck, frog, campfire
        // Snowy Hill
        case sled, ice, snowman
        // Robot Workshop
        case conveyor, crane, marbleRun, robot, gears, bigButton
        // Night Carnival
        case ferris, lightButton, popcorn
    }

    let id: String
    let kind: Kind
    /// Its middle on the ground; the animal faces it when using it.
    let center: SIMD2<Float>
    /// Which floor it is on (1 = upstairs in the big house).
    var level = 0
    /// Used from where the animal stands, without walking over (ducks and frogs on the water).
    var fromAfar = false
    /// Where the animal stands: the nearest of these...
    var spots: [SIMD2<Float>] = []
    /// ...or anywhere on a circle this far from the middle.
    var standRadius: Float = 1

    /// Door open, lamp on, flag up, lid open, or someone riding.
    var isOn = false
    /// Eased animation value (door angle, swing size, merry-go-round speed...).
    var value: Float = 0
    var phase: Float = 0
    /// Seconds since it was last used (bell, fountain).
    var time: Float = 100

    var parts: [String: Entity] = [:]
    var obstacle: Int?
    var light: PointLight?
    /// Seat for the bench, swing and merry-go-round; the top of the bed.
    var seat: Entity?
    /// The slide's climb and slide path, in world space.
    var path: [SIMD3<Float>] = []
    /// The toy box's small balls.
    var contents: [Prop] = []
    /// Where the animal stood when it started (it hops back there).
    var lastSpot: SIMD2<Float> = .zero
    /// Merry-go-round and carousel: how far out the seats are, and how fast it turns.
    var ringRadius: Float = 1.05
    var spinSpeed: Float = 1.3
    /// Ducks: the oval they swim round (about `center`) and the water height.
    var orbit = SIMD2<Float>(1.7, 1.2)
    var floatY: Float = 0.04
    /// Extra numbers some things need (gear sizes, a light's color...).
    var numbers: [Float] = []

    init(id: String, kind: Kind, center: SIMD2<Float>) {
        self.id = id
        self.kind = kind
        self.center = center
    }

    func spot(from p: SIMD2<Float>) -> SIMD2<Float> {
        if let nearest = spots.min(by: { simd_distance($0, p) < simd_distance($1, p) }) {
            return nearest
        }
        var d = p - center
        if simd_length(d) < 0.001 { d = SIMD2<Float>(0, 1) }
        return center + simd_normalize(d) * standRadius
    }
}

struct House {
    let center: SIMD2<Float>
    let yaw: Float
    let halfX: Float
    let halfZ: Float
    let roof: Entity
    /// The big house: everything upstairs (hidden while the animal is downstairs).
    var upper: Entity? = nil
    /// Height of the roof top, so the camera stays out of the house.
    var top: Float = 4.2
    /// The front door: it opens by itself when an animal walks in or out.
    var door: Interactive? = nil
    /// Where to walk when the outside (the igloo's dome) is tapped from behind.
    var entrance: SIMD2<Float>? = nil
    /// A small extra bit that also counts as inside (the igloo's tunnel), in house-local axes.
    var annex: (center: SIMD2<Float>, half: SIMD2<Float>)? = nil

    func contains(_ p: SIMD2<Float>, margin: Float = 0) -> Bool {
        let l = rotateY(p - center, -yaw)
        if abs(l.x) < halfX + margin && abs(l.y) < halfZ + margin { return true }
        guard let annex else { return false }
        let a = l - annex.center
        return abs(a.x) < annex.half.x + margin && abs(a.y) < annex.half.y + margin
    }
}

/// What a tap on an entity means.
enum TapTarget {
    case ground
    /// A floor inside the big house (1 = upstairs).
    case floor(Int)
    /// The big house's stairs: go up (or down).
    case stairs
    case prop(Prop)
    case use(Interactive)
}

// MARK: - Saving the world as it was left

struct WorldSave: Codable {
    struct Item: Codable {
        var p: [Float]
        var q: [Float]
    }
    var props: [String: Item] = [:]
    var toggles: [String: Bool] = [:]
}

enum WorldStore {
    static func key(for scene: SceneKind) -> String { "figureWorlds.\(scene.rawValue).v1" }

    static func load(_ scene: SceneKind) -> WorldSave? {
        let key = key(for: scene)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WorldSave.self, from: data)
    }

    static func save(_ save: WorldSave, for scene: SceneKind) {
        if let data = try? JSONEncoder().encode(save) {
            UserDefaults.standard.set(data, forKey: key(for: scene))
        }
    }
}
