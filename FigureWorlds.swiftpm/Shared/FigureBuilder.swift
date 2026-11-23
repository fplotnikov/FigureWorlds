import RealityKit
import UIKit

/// The pieces of a built figure that the animator moves.
struct FigureParts {
    let body: Entity
    let legL: Entity
    let legR: Entity
    let armL: Entity
    let armR: Entity
}

/// Builds original, toy-like animals out of simple rounded shapes.
/// Every figure is about 20 cm tall at scale 1, stands on y = 0 and faces +z.
enum FigureBuilder {

    // MARK: Shape helpers

    static func material(_ color: UIColor, shiny: Bool = false) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: .float(shiny ? 0.2 : 0.65), isMetallic: shiny)
    }

    @discardableResult
    static func ball(_ radius: Float, _ color: UIColor, at position: SIMD3<Float>,
                     scale: SIMD3<Float> = [1, 1, 1], in parent: Entity) -> ModelEntity {
        let e = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material(color)])
        e.position = position
        e.scale = scale
        parent.addChild(e)
        return e
    }

    /// A cone whose tip points along local +y before `rotation` is applied.
    @discardableResult
    static func cone(height: Float, radius: Float, _ color: UIColor, at position: SIMD3<Float>,
                     rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]),
                     scale: SIMD3<Float> = [1, 1, 1], in parent: Entity) -> ModelEntity {
        let e = ModelEntity(mesh: .generateCone(height: height, radius: radius), materials: [material(color)])
        e.position = position
        e.orientation = rotation
        e.scale = scale
        parent.addChild(e)
        return e
    }

    @discardableResult
    static func cylinder(height: Float, radius: Float, _ color: UIColor, at position: SIMD3<Float>,
                         shiny: Bool = false, in parent: Entity) -> ModelEntity {
        let e = ModelEntity(mesh: .generateCylinder(height: height, radius: radius),
                            materials: [material(color, shiny: shiny)])
        e.position = position
        parent.addChild(e)
        return e
    }

    @discardableResult
    static func box(_ size: SIMD3<Float>, corner: Float, _ color: UIColor, at position: SIMD3<Float>,
                    rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]),
                    in parent: Entity) -> ModelEntity {
        let e = ModelEntity(mesh: .generateBox(size: size, cornerRadius: corner), materials: [material(color)])
        e.position = position
        e.orientation = rotation
        parent.addChild(e)
        return e
    }

    static func pivot(at position: SIMD3<Float>, angleZ: Float = 0, in parent: Entity) -> Entity {
        let e = Entity()
        e.position = position
        e.orientation = simd_quatf(angle: angleZ, axis: [0, 0, 1])
        parent.addChild(e)
        return e
    }

    static func rotX(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [1, 0, 0]) }
    static func rotZ(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 0, 1]) }

    static let dark = UIColor(hex: 0x2B2B33)
    static let white = UIColor.white
    static let cheek = UIColor(hex: 0xFFB3C1)

    // MARK: Figure

    static func build(_ look: Look) -> FigureParts {
        let animal = look.animal
        let (main, belly) = look.skin.colors(for: animal)
        let accent = animal.accentColor
        let root = Entity()
        root.name = "figure"

        // Body and tummy
        ball(0.05, main, at: [0, 0.065, 0], scale: [1, 1.1, 0.9], in: root)
        if animal == .penguin {
            ball(0.042, belly, at: [0, 0.062, 0.014], scale: [1, 1.15, 0.8], in: root)
        } else {
            ball(0.036, belly, at: [0, 0.06, 0.024], scale: [1, 1.1, 0.7], in: root)
        }

        // Head
        let headScale: SIMD3<Float> = animal == .frog ? [1.2, 0.9, 1] : [1, 1, 1]
        ball(0.045, main, at: [0, 0.135, 0], scale: headScale, in: root)

        // Feet on hip pivots so they can swing
        let feetColor: UIColor = switch animal {
        case .penguin, .fox: accent
        case .frog: main
        default: belly
        }
        let legL = pivot(at: [-0.022, 0.03, 0], in: root)
        let legR = pivot(at: [0.022, 0.03, 0], in: root)
        for leg in [legL, legR] {
            ball(0.017, feetColor, at: [0, -0.018, 0.008], scale: [1, 0.6, 1.4], in: leg)
        }

        // Arms (flippers for the penguin) on shoulder pivots
        let armL = pivot(at: [-0.046, 0.088, 0], in: root)
        let armR = pivot(at: [0.046, 0.088, 0], in: root)
        let armScale: SIMD3<Float> = animal == .penguin ? [0.45, 2.0, 0.9] : [0.8, 1.5, 0.8]
        ball(0.014, main, at: [-0.006, -0.02, 0], scale: armScale, in: armL)
        ball(0.014, main, at: [0.006, -0.02, 0], scale: armScale, in: armR)

        // Face
        if animal == .frog {
            for s: Float in [-1, 1] {
                ball(0.016, white, at: [s * 0.024, 0.168, 0.016], in: root)
                ball(0.008, dark, at: [s * 0.024, 0.17, 0.03], in: root)
                ball(0.0025, white, at: [s * 0.024 + 0.003, 0.173, 0.037], in: root)
            }
        } else {
            for s: Float in [-1, 1] {
                ball(0.0075, dark, at: [s * 0.017, 0.145, 0.041], in: root)
                ball(0.0025, white, at: [s * 0.017 + 0.003, 0.148, 0.047], in: root)
            }
        }
        for s: Float in [-1, 1] {
            ball(0.007, cheek, at: [s * 0.029, 0.127, 0.033], scale: [1, 0.7, 0.5], in: root)
        }

        addFeatures(for: animal, main: main, belly: belly, accent: accent, to: root)
        addWear(look.visibleWear, animal: animal, fit: .shapes, head: root, neck: root)

        return FigureParts(body: root, legL: legL, legR: legR, armL: armL, armR: armR)
    }

    // MARK: Animal details

    static func addFeatures(for animal: Animal, main: UIColor, belly: UIColor, accent: UIColor, to root: Entity) {
        switch animal {
        case .bunny:
            for s: Float in [-1, 1] {
                let ear = pivot(at: [s * 0.018, 0.17, 0], angleZ: -s * 0.15, in: root)
                ball(0.013, main, at: [0, 0.035, 0], scale: [1, 3, 0.6], in: ear)
                ball(0.008, accent, at: [0, 0.035, 0.005], scale: [1, 3.2, 0.4], in: ear)
            }
            ball(0.005, accent, at: [0, 0.131, 0.045], in: root)
            ball(0.015, belly, at: [0, 0.045, -0.048], in: root)

        case .kitty:
            for s: Float in [-1, 1] {
                let ear = pivot(at: [s * 0.026, 0.166, 0], angleZ: -s * 0.3, in: root)
                cone(height: 0.03, radius: 0.014, main, at: [0, 0.012, 0], in: ear)
                cone(height: 0.02, radius: 0.008, accent, at: [0, 0.009, 0.005], in: ear)
                for (i, tilt) in [Float(0.12), -0.12].enumerated() {
                    box([0.024, 0.0012, 0.0012], corner: 0, dark,
                        at: [s * 0.03, 0.129 - Float(i) * 0.005, 0.04],
                        rotation: rotZ(s * tilt), in: root)
                }
            }
            ball(0.005, accent, at: [0, 0.131, 0.045], in: root)
            // Curly tail made of small balls
            for i in 0...7 {
                let t = Float(i) / 7
                ball(0.0085, main,
                     at: [0.02 * t, 0.035 + 0.075 * t, -0.05 - 0.025 * sin(t * .pi)], in: root)
            }

        case .bear:
            for s: Float in [-1, 1] {
                ball(0.015, main, at: [s * 0.033, 0.17, 0], in: root)
                ball(0.009, accent, at: [s * 0.033, 0.17, 0.009], scale: [1, 1, 0.5], in: root)
            }
            ball(0.019, belly, at: [0, 0.124, 0.034], scale: [1.1, 0.85, 0.8], in: root)
            ball(0.007, dark, at: [0, 0.131, 0.05], scale: [1.2, 0.9, 1], in: root)
            ball(0.012, main, at: [0, 0.045, -0.048], in: root)

        case .penguin:
            // White face patch and an orange beak
            ball(0.032, belly, at: [0, 0.134, 0.02], scale: [1.15, 0.9, 0.65], in: root)
            cone(height: 0.022, radius: 0.009, accent, at: [0, 0.13, 0.05], rotation: rotX(.pi / 2), in: root)

        case .frog:
            box([0.026, 0.003, 0.003], corner: 0.0015, dark, at: [0, 0.118, 0.042], in: root)

        case .fox:
            for s: Float in [-1, 1] {
                let ear = pivot(at: [s * 0.025, 0.166, 0], angleZ: -s * 0.25, in: root)
                cone(height: 0.038, radius: 0.015, main, at: [0, 0.019, 0], in: ear)
                cone(height: 0.014, radius: 0.0062, accent, at: [0, 0.031, 0.001], in: ear)
            }
            cone(height: 0.03, radius: 0.017, belly, at: [0, 0.124, 0.045], rotation: rotX(.pi / 2), in: root)
            ball(0.006, accent, at: [0, 0.124, 0.061], in: root)
            // Big fluffy tail with a white tip
            ball(0.022, main, at: [0, 0.07, -0.07], scale: [0.8, 0.8, 1.8], rotation: rotX(0.6), in: root)
            ball(0.012, belly, at: [0, 0.088, -0.097], in: root)

        default:
            // Creatures only show this plain stand-in if their model file fails to load.
            ball(0.012, belly, at: [0, 0.045, -0.048], in: root)
        }
    }

    // MARK: Things to wear

    /// Puts every worn item on the figure. Head items go on `head`, neck items on `neck`
    /// (the same entity for shape figures; bone-following anchors for models). `fit` says
    /// where the head, eyes and neck are; creatures' faces may be turned (fit.faceYaw).
    static func addWear(_ items: [Wearable], animal: Animal, fit: HeadFit, head: Entity, neck: Entity) {
        guard !items.isEmpty else { return }
        let turn = simd_quatf(angle: fit.faceYaw, axis: [0, 1, 0])

        // Hat anchor: on top of the head, turned with the face, sized to the head.
        let hat = Entity()
        hat.position = [fit.headX, fit.top, fit.headZ]
        hat.orientation = turn
        hat.scale = .init(repeating: fit.hatScale)
        head.addChild(hat)

        // Face anchor: between the eyes, just in front of them.
        let frog = animal == .frog && !fit.measured
        let face = Entity()
        face.position = frog ? [0, 0.168, 0.044] : [fit.faceX, fit.eyeY, fit.faceZ]
        face.orientation = turn
        head.addChild(face)
        let ex: Float = frog ? 0.024 : fit.eyeX
        let g: Float = frog ? 1.25 : (fit.measured ? min(1.6, max(0.9, fit.eyeX / 0.017)) : 1)

        // Neck anchor: the middle of the neck; its front is `front` along +z.
        let ring = Entity()
        ring.position = [fit.neckCX, fit.neckY, fit.neckCZ]
        ring.orientation = turn * simd_quatf(angle: fit.neckPitch, axis: [1, 0, 0])
        neck.addChild(ring)
        let r = fit.neckRadius
        let front = max(r * 0.9, simd_length(SIMD2<Float>(fit.neckX - fit.neckCX, fit.neckZ - fit.neckCZ)))

        for item in items {
            switch item.slot {
            case .hat: addHat(item, on: hat, head: head, fit: fit)
            case .glasses: addGlasses(item, on: face, ex: ex, g: g, frog: frog)
            case .mask:
                if [.clownNose, .moustache, .beard, .whiskers, .pigSnout].contains(item) {
                    addNoseItem(item, fit: fit, frog: frog, g: g, turn: turn, head: head)
                } else {
                    addMask(item, on: face, ex: ex, g: g)
                }
            case .neck: addNeckItem(item, on: ring, r: r, front: front)
            }
        }
    }

    private static let red = UIColor(hex: 0xE94F64)
    private static let gold = UIColor(hex: 0xF5C542)
    private static let lensBlue = UIColor(hex: 0xBFE3F5)

    private static func disc(_ radius: Float, _ color: UIColor, at p: SIMD3<Float>, shiny: Bool = false,
                             in parent: Entity) {
        let e = cylinder(height: 0.002, radius: radius, color, at: p, shiny: shiny, in: parent)
        e.orientation = rotX(.pi / 2)
    }

    private static func addHat(_ item: Wearable, on hat: Entity, head: Entity, fit: HeadFit) {
        switch item {
        case .partyHat:
            let p = pivot(at: .zero, angleZ: -0.2, in: hat)
            cone(height: 0.05, radius: 0.022, UIColor(hex: 0x6EC6FF), at: [0, 0.025, 0], in: p)
            ball(0.008, UIColor(hex: 0xFFD45C), at: [0, 0.052, 0], in: p)
        case .crown:
            cylinder(height: 0.016, radius: 0.022, gold, at: [0, 0.008, 0], shiny: true, in: hat)
            for i in 0..<6 {
                let a = Float(i) / 6 * 2 * .pi
                ball(0.0045, gold, at: [0.02 * sin(a), 0.019, 0.02 * cos(a)], in: hat)
            }
            ball(0.0045, red, at: [0, 0.008, 0.023], in: hat)
        case .topHat:
            cylinder(height: 0.003, radius: 0.031, dark, at: [0, 0.0015, 0], in: hat)
            cylinder(height: 0.036, radius: 0.019, dark, at: [0, 0.02, 0], in: hat)
            cylinder(height: 0.006, radius: 0.0195, red, at: [0, 0.007, 0], in: hat)
        case .cowboyHat:
            let brown = UIColor(hex: 0xB07A4A)
            ball(0.037, brown, at: [0, 0.002, 0], scale: [1, 0.08, 1], in: hat)
            cylinder(height: 0.022, radius: 0.017, brown, at: [0, 0.012, 0], in: hat)
            ball(0.017, brown, at: [0, 0.023, 0], scale: [1, 0.35, 1], in: hat)
            cylinder(height: 0.004, radius: 0.0175, UIColor(hex: 0x6B4426), at: [0, 0.005, 0], in: hat)
        case .beanie:
            let teal = UIColor(hex: 0x4FB3A9)
            ball(0.025, teal, at: [0, 0.0, 0], scale: [1, 0.8, 1], in: hat)
            cylinder(height: 0.008, radius: 0.0255, UIColor(hex: 0x3E978E), at: [0, 0.001, 0], in: hat)
            ball(0.009, .white, at: [0, 0.022, 0], in: hat)
        case .cap:
            ball(0.024, red, at: [0, -0.002, 0], scale: [1, 0.65, 1], in: hat)
            box([0.03, 0.003, 0.024], corner: 0.0015, red, at: [0, 0.0, 0.03], in: hat)
            ball(0.004, .white, at: [0, 0.014, 0], in: hat)
        case .wizardHat:
            let purple = UIColor(hex: 0x6C5BD4)
            cylinder(height: 0.003, radius: 0.03, purple, at: [0, 0.0015, 0], in: hat)
            let p = pivot(at: .zero, angleZ: 0.15, in: hat)
            cone(height: 0.06, radius: 0.02, purple, at: [0, 0.031, 0], in: p)
            for (x, y, z) in [(Float(0.008), Float(0.018), Float(0.014)), (-0.006, 0.032, 0.009), (0.003, 0.045, 0.006)] {
                ball(0.0035, UIColor(hex: 0xFFD45C), at: [x, y, z], in: p)
            }
        case .pirateHat:
            ball(0.03, dark, at: [0, 0.01, 0], scale: [1.35, 0.55, 0.75], in: hat)
            ball(0.0055, .white, at: [0, 0.012, 0.022], in: hat)
            box([0.008, 0.002, 0.001], corner: 0, .white, at: [0, 0.006, 0.0225], in: hat)
        case .chefHat:
            cylinder(height: 0.024, radius: 0.019, .white, at: [0, 0.012, 0], in: hat)
            for (x, z) in [(Float(-0.009), Float(0)), (0.009, 0), (0, -0.009), (0, 0.009)] {
                ball(0.013, .white, at: [x, 0.028, z], in: hat)
            }
            ball(0.015, .white, at: [0, 0.033, 0], in: hat)
        case .flowerCrown:
            let colors = [UIColor(hex: 0xFF8FB1), UIColor(hex: 0xFFD45C), .white]
            for i in 0..<8 {
                let a = Float(i) / 8 * 2 * .pi
                let p: SIMD3<Float> = [0.024 * sin(a), 0.002, 0.024 * cos(a)]
                ball(0.0065, colors[i % 3], at: p, scale: [1, 0.7, 1], in: hat)
                ball(0.0028, UIColor(hex: 0xF4A259), at: p + [0, 0.004, 0], in: hat)
                ball(0.004, UIColor(hex: 0x7BC86C), at: [0.025 * sin(a + 0.4), 0.0, 0.025 * cos(a + 0.4)],
                     scale: [1, 0.5, 1], in: hat)
            }
        case .vikingHelmet:
            let silver = UIColor(hex: 0xC9CED6)
            let dome = ball(0.026, silver, at: [0, -0.002, 0], scale: [1, 0.8, 1], in: hat)
            dome.model?.materials = [material(silver, shiny: true)]
            cylinder(height: 0.006, radius: 0.0265, gold, at: [0, 0.0, 0], shiny: true, in: hat)
            for side: Float in [-1, 1] {
                cone(height: 0.026, radius: 0.006, UIColor(hex: 0xFFF1D6), at: [side * 0.028, 0.012, 0],
                     rotation: rotZ(-side * 0.85), in: hat)
            }
        case .propellerCap:
            ball(0.024, UIColor(hex: 0xFFD45C), at: [0, -0.002, 0], scale: [1, 0.65, 1], in: hat)
            cylinder(height: 0.01, radius: 0.0018, dark, at: [0, 0.018, 0], in: hat)
            box([0.042, 0.002, 0.007], corner: 0.001, red, at: [0, 0.024, 0], in: hat)
            box([0.007, 0.002, 0.042], corner: 0.001, UIColor(hex: 0x5DA9E9), at: [0, 0.0245, 0], in: hat)
        case .flower:
            let flower = pivot(at: fit.flower, angleZ: -0.5, in: head)
            for i in 0..<5 {
                let a = Float(i) / 5 * 2 * .pi
                ball(0.006, UIColor(hex: 0xFF8FB1), at: [0.008 * cos(a), 0.008 * sin(a), 0],
                     scale: [1, 1, 0.5], in: flower)
            }
            ball(0.0055, UIColor(hex: 0xFFD45C), at: [0, 0, 0.002], in: flower)
        case .santaHat:
            cylinder(height: 0.009, radius: 0.026, .white, at: [0, 0.004, 0], in: hat)
            let p = pivot(at: [0, 0.008, 0], angleZ: -0.3, in: hat)
            cone(height: 0.054, radius: 0.023, UIColor(hex: 0xD6283B), at: [0, 0.027, 0], in: p)
            ball(0.008, .white, at: [0, 0.055, 0], in: p)
        case .strawHat:
            let straw = UIColor(hex: 0xE8C77A)
            ball(0.042, straw, at: [0, 0.001, 0], scale: [1, 0.07, 1], in: hat)
            cylinder(height: 0.016, radius: 0.019, straw, at: [0, 0.009, 0], in: hat)
            ball(0.019, straw, at: [0, 0.017, 0], scale: [1, 0.3, 1], in: hat)
            cylinder(height: 0.005, radius: 0.0195, UIColor(hex: 0xFF8FB1), at: [0, 0.004, 0], in: hat)
            ball(0.005, UIColor(hex: 0xFFD45C), at: [0.014, 0.005, 0.013], in: hat)
        case .unicornHorn:
            let horn = cone(height: 0.042, radius: 0.0075, UIColor(hex: 0xFFE7A8), at: [0, 0.018, 0.012],
                            rotation: rotX(0.3), in: hat)
            horn.model?.materials = [material(UIColor(hex: 0xFFE7A8), shiny: true)]
            for k in 0..<3 {   // pink stripes round the horn
                let y = 0.006 + Float(k) * 0.009
                let t = y / 0.042
                cylinder(height: 0.0016, radius: 0.0075 * (1 - t) + 0.0006, UIColor(hex: 0xFF8FB1),
                         at: [0, 0.003 + y * 0.95, 0.012 + y * 0.3], in: hat).orientation = rotX(0.3)
            }
            for s: Float in [-1, 1] { ball(0.0055, UIColor(hex: 0xC8A2F0), at: [s * 0.01, 0.002, 0.01], in: hat) }
        case .bunnyEars:
            let pink = UIColor(hex: 0xFF8FB1)
            box([0.05, 0.004, 0.008], corner: 0.002, pink, at: [0, 0.001, 0], in: hat)
            for s: Float in [-1, 1] {
                ball(0.011, .white, at: [s * 0.012, 0.022, 0], scale: [0.55, 1.9, 0.35], rotation: rotZ(-s * 0.18), in: hat)
                ball(0.007, pink, at: [s * 0.0122, 0.022, 0.0025], scale: [0.5, 1.8, 0.3], rotation: rotZ(-s * 0.18), in: hat)
            }
        case .hardHat:
            let yellow = UIColor(hex: 0xFFC83D)
            let dome = ball(0.026, yellow, at: [0, -0.002, 0], scale: [1, 0.78, 1], in: hat)
            dome.model?.materials = [SimpleMaterial(color: yellow, roughness: .float(0.3), isMetallic: false)]   // glossy plastic, not gold
            ball(0.032, yellow, at: [0, -0.001, 0.004], scale: [1, 0.08, 1], in: hat)
            box([0.006, 0.006, 0.042], corner: 0.002, UIColor(hex: 0xF0B020), at: [0, 0.017, 0], in: hat)
        default:
            break
        }
    }

    private static func addGlasses(_ item: Wearable, on face: Entity, ex x: Float, g: Float, frog: Bool) {
        let bridge = { (color: UIColor, width: Float) in
            box([max(0.004, x * 2 - width + 0.004), 0.003, 0.003], corner: 0.001, color, at: [0, 0.004, 0], in: face)
        }
        switch item {
        case .sunglasses:
            let lens: SIMD3<Float> = frog ? [0.03, 0.022, 0.004] : [0.024 * g, 0.016 * g, 0.004]
            for s: Float in [-1, 1] { box(lens, corner: 0.0035, dark, at: [s * x, 0, 0], in: face) }
            bridge(dark, lens.x)
        case .roundGlasses:
            for s: Float in [-1, 1] {
                disc(0.011 * g, dark, at: [s * x, 0, 0], in: face)
                disc(0.009 * g, lensBlue, at: [s * x, 0, 0.0008], in: face)
            }
            bridge(dark, 0.022 * g)
        case .heartGlasses:
            let pink = UIColor(hex: 0xFF5C8A)
            for s: Float in [-1, 1] {
                let c: SIMD3<Float> = [s * x, 0, 0]
                for dx: Float in [-1, 1] {
                    ball(0.0065 * g, pink, at: c + [dx * 0.0045 * g, 0.003 * g, 0], scale: [1, 1, 0.35], in: face)
                }
                cone(height: 0.012 * g, radius: 0.0088 * g, pink, at: c + [0, -0.0045 * g, 0],
                     rotation: rotZ(.pi), scale: [1, 1, 0.35], in: face)
            }
            bridge(pink, 0.022 * g)
        case .starGlasses:
            let yellow = UIColor(hex: 0xFFC83D)
            for s: Float in [-1, 1] {
                let c: SIMD3<Float> = [s * x, 0, 0]
                ball(0.0065 * g, yellow, at: c, scale: [1, 1, 0.4], in: face)
                for k in 0..<5 {
                    let a = Float.pi / 2 + Float(k) * 2 * .pi / 5
                    cone(height: 0.008 * g, radius: 0.004 * g, yellow,
                         at: c + [cos(a), sin(a), 0] * (0.008 * g), rotation: rotZ(a - .pi / 2),
                         scale: [1, 1, 0.4], in: face)
                }
            }
            bridge(yellow, 0.026 * g)
        case .goggles:
            let orange = UIColor(hex: 0xF4A259)
            for s: Float in [-1, 1] {
                box([0.022 * g, 0.017 * g, 0.006], corner: 0.004, orange, at: [s * x, 0, 0], in: face)
                box([0.017 * g, 0.012 * g, 0.002], corner: 0.003, lensBlue, at: [s * x, 0, 0.003], in: face)
                box([0.006, 0.005, 0.014], corner: 0.002, dark, at: [s * (x + 0.012 * g), 0, -0.006], in: face)
            }
            bridge(orange, 0.022 * g)
        case .glasses3D:
            for s: Float in [-1, 1] {
                box([0.024 * g, 0.016 * g, 0.004], corner: 0.002, .white, at: [s * x, 0, 0], in: face)
                box([0.019 * g, 0.011 * g, 0.002], corner: 0.001,
                    s < 0 ? UIColor(hex: 0xE94F4F) : UIColor(hex: 0x4FC3E9), at: [s * x, 0, 0.002], in: face)
            }
            bridge(.white, 0.024 * g)
        case .monocle:
            disc(0.012 * g, gold, at: [x, 0, 0], shiny: true, in: face)
            disc(0.0098 * g, lensBlue, at: [x, 0, 0.0008], in: face)
            for i in 1...5 {
                ball(0.0012, gold, at: [x + 0.009 * g + Float(i) * 0.0015, -0.006 * g - Float(i) * 0.0035, -0.001], in: face)
            }
        case .googlyEyes:
            for s: Float in [-1, 1] {
                disc(0.012 * g, dark, at: [s * x, 0, 0], in: face)
                disc(0.011 * g, .white, at: [s * x, 0, 0.0008], in: face)
                ball(0.0048 * g, dark, at: [s * x + s * 0.002 * g, -0.0045 * g, 0.0015], scale: [1, 1, 0.4], in: face)
            }
            bridge(dark, 0.024 * g)
        case .visor:
            let w = x * 2 + 0.032 * g
            box([w + 0.004, 0.017 * g, 0.004], corner: 0.004, UIColor(hex: 0x4A5060), at: [0, 0, -0.001], in: face)
            let glass = box([w, 0.012 * g, 0.004], corner: 0.004, UIColor(hex: 0x52E0FF), at: [0, 0, 0.0015], in: face)
            glass.model?.materials = [material(UIColor(hex: 0x52E0FF), shiny: true)]
            box([w * 0.35, 0.002 * g, 0.001], corner: 0.0005, .white, at: [-w * 0.18, 0.003 * g, 0.004], in: face)
        case .pixelShades:
            let u = 0.004 * g    // one "pixel"
            for s: Float in [-1, 1] {
                box([u * 6, u * 2, 0.004], corner: 0, dark, at: [s * x, u * 0.5, 0], in: face)
                box([u * 4, u, 0.004], corner: 0, dark, at: [s * x, -u, 0], in: face)
                box([u * 2, u, 0.004], corner: 0, dark, at: [s * x, -u * 2, 0], in: face)
                box([u, u, 0.001], corner: 0, .white, at: [s * x - u * 1.5, u, 0.0025], in: face)
            }
            box([x * 2 + u * 6, u, 0.004], corner: 0, dark, at: [0, u * 1.5, 0], in: face)
        case .catEyeGlasses:
            let pink = UIColor(hex: 0xE85A9B)
            for s: Float in [-1, 1] {
                ball(0.0115 * g, pink, at: [s * x, 0, 0], scale: [1.35, 0.9, 0.3], in: face)
                ball(0.0088 * g, lensBlue, at: [s * x, 0, 0.002], scale: [1.35, 0.85, 0.25], in: face)
                cone(height: 0.011 * g, radius: 0.004 * g, pink, at: [s * (x + 0.013 * g), 0.007 * g, 0],
                     rotation: rotZ(-s * 0.9), scale: [1, 1, 0.4], in: face)
            }
            bridge(pink, 0.03 * g)
        default:
            break
        }
    }

    /// Red nose and moustache go on the measured nose tip (models/measure_nose.py),
    /// turned with the face. Shape figures fall back to a spot below the eyes.
    private static func addNoseItem(_ item: Wearable, fit: HeadFit, frog: Bool, g: Float,
                                    turn: simd_quatf, head: Entity) {
        let tip: SIMD3<Float> = fit.nose ?? (frog ? [0, 0.15, 0.05] : [fit.faceX, fit.eyeY - 0.012, fit.faceZ])
        let anchor = Entity()
        anchor.position = tip
        anchor.orientation = turn
        head.addChild(anchor)
        let s = min(1.2, max(0.75, g))
        switch item {
        case .clownNose:
            let r: Float = 0.0065 * s
            let nose = ball(r, red, at: [0, 0, r * 0.35], in: anchor)   // a little sunk into the snout
            nose.model?.materials = [material(red, shiny: true)]
        case .moustache:
            let brown = UIColor(hex: 0x5A3A28)
            for side: Float in [-1, 1] {
                ball(0.0042 * s, brown, at: [side * 0.0062 * s, -0.0062 * s, -0.0012],
                     scale: [1.9, 0.55, 0.6], rotation: rotZ(side * 0.32), in: anchor)
                ball(0.0025 * s, brown, at: [side * 0.0128 * s, -0.0036 * s, -0.003],
                     scale: [1.3, 0.6, 0.6], rotation: rotZ(side * 0.9), in: anchor)
            }
        case .beard:
            let white = UIColor(hex: 0xF7F4EE)
            ball(0.016 * s, white, at: [0, -0.02 * s, -0.006], scale: [1.15, 1.0, 0.55], in: anchor)
            ball(0.009 * s, white, at: [0, -0.033 * s, -0.004], scale: [1, 1.1, 0.5], in: anchor)
            for side: Float in [-1, 1] {
                ball(0.0055 * s, white, at: [side * 0.007 * s, -0.006 * s, -0.001],
                     scale: [1.8, 0.7, 0.6], rotation: rotZ(side * 0.3), in: anchor)
            }
        case .whiskers:
            ball(0.0042 * s, UIColor(hex: 0xFF8FB1), at: [0, 0, 0.0015], scale: [1.2, 0.9, 0.8], in: anchor)
            for side: Float in [-1, 1] {
                for k in -1...1 {
                    box([0.022 * s, 0.0011, 0.0011], corner: 0, dark,
                        at: [side * 0.016 * s, -0.004 * s + Float(k) * 0.0035 * s, -0.002],
                        rotation: rotZ(side * Float(k) * 0.18), in: anchor)
                }
            }
        case .pigSnout:
            let pink = UIColor(hex: 0xFFA6C1)
            ball(0.0085 * s, pink, at: [0, -0.001, 0.002], scale: [1.25, 0.9, 0.6], in: anchor)
            for side: Float in [-1, 1] {
                ball(0.0022 * s, UIColor(hex: 0xB8506E), at: [side * 0.0042 * s, -0.001, 0.0068 * s], scale: [0.8, 1.2, 0.4], in: anchor)
            }
        default:
            break
        }
    }

    private static func addMask(_ item: Wearable, on face: Entity, ex x: Float, g: Float) {
        switch item {
        case .heroMask:
            for s: Float in [-1, 1] {
                ball(0.012 * g, red, at: [s * x, 0, 0.001], scale: [1.35, 0.9, 0.35], in: face)
                ball(0.0055 * g, dark, at: [s * x, 0, 0.0045], scale: [1.3, 0.9, 0.3], in: face)
            }
            box([x * 2, 0.008 * g, 0.006], corner: 0.002, red, at: [0, 0.001, 0], in: face)
        case .butterflyMask:
            let wing = UIColor(hex: 0xB57EDC), spot = UIColor(hex: 0xFF9ED2)
            for s: Float in [-1, 1] {
                ball(0.013 * g, wing, at: [s * (x + 0.003 * g), 0.004 * g, 0.001], scale: [1.25, 0.95, 0.3], in: face)
                ball(0.0085 * g, spot, at: [s * (x + 0.004 * g), -0.008 * g, 0.0], scale: [1.2, 0.9, 0.3], in: face)
                ball(0.005 * g, dark, at: [s * x, 0.002 * g, 0.004], scale: [1.3, 0.9, 0.3], in: face)
                ball(0.0018, gold, at: [s * (x + 0.013 * g), 0.012 * g, 0.003], in: face)
            }
        case .clownNose:
            let nose = ball(0.008 * g, red, at: [0, -0.014 * g, 0.012], in: face)
            nose.model?.materials = [material(red, shiny: true)]
        case .moustache:
            for s: Float in [-1, 1] {
                ball(0.0045 * g, UIColor(hex: 0x5A3A28), at: [s * 0.0065 * g, -0.019 * g, 0.009],
                     scale: [1.8, 0.55, 0.5], rotation: rotZ(s * 0.35), in: face)
            }
        case .ninjaWrap:
            box([x * 2 + 0.032 * g, 0.015 * g, 0.006], corner: 0.003, UIColor(hex: 0x3A3F55), at: [0, 0, 0], in: face)
            for s: Float in [-1, 1] {
                ball(0.0045 * g, .white, at: [s * x, 0, 0.0035], scale: [1.3, 0.9, 0.3], in: face)
                ball(0.002 * g, dark, at: [s * x, 0, 0.005], in: face)
            }
            box([0.004, 0.012, 0.003], corner: 0.001, UIColor(hex: 0x3A3F55),
                at: [x + 0.018 * g, -0.008, -0.004], rotation: rotZ(0.4), in: face)
        case .snorkel:
            box([x * 2 + 0.022 * g, 0.019 * g, 0.007], corner: 0.005, UIColor(hex: 0x3A8DDE), at: [0, 0, 0], in: face)
            box([x * 2 + 0.014 * g, 0.013 * g, 0.002], corner: 0.004, lensBlue, at: [0, 0, 0.0038], in: face)
            cylinder(height: 0.05, radius: 0.0028, UIColor(hex: 0xFFD45C), at: [x + 0.016 * g, 0.012, -0.004], in: face)
            ball(0.004, UIColor(hex: 0xF4A259), at: [x + 0.016 * g, 0.037, -0.004], in: face)
        default:
            break
        }
    }

    private static func addNeckItem(_ item: Wearable, on ring: Entity, r: Float, front: Float) {
        switch item {
        case .bowTie:
            cone(height: 0.02, radius: 0.01, red, at: [-0.011, 0, front], rotation: rotZ(-.pi / 2), scale: [1, 1, 0.5], in: ring)
            cone(height: 0.02, radius: 0.01, red, at: [0.011, 0, front], rotation: rotZ(.pi / 2), scale: [1, 1, 0.5], in: ring)
            ball(0.005, UIColor(hex: 0xC93A50), at: [0, 0, front + 0.002], in: ring)
        case .scarf:
            cylinder(height: 0.016, radius: r, red, at: [0, 0.002, 0], in: ring)
            box([0.016, 0.035, 0.006], corner: 0.003, red, at: [0.018, -0.018, r - 0.001], rotation: rotZ(0.15), in: ring)
        case .cape:
            let capeRed = UIColor(hex: 0xD6455D)
            let p = Entity()
            p.position = [0, 0.004, -r * 0.85]
            p.orientation = rotX(0.35)
            ring.addChild(p)
            box([r * 2.0, 0.05, 0.003], corner: 0.001, capeRed, at: [0, -0.025, 0], in: p)
            cylinder(height: 0.006, radius: r * 1.02, capeRed, at: [0, 0.002, 0], in: ring)
            ball(0.0045, gold, at: [0, 0.002, front + 0.001], in: ring)
        case .flowerNecklace:
            let colors = [UIColor(hex: 0xFF8FB1), UIColor(hex: 0xFFD45C), UIColor(hex: 0xFF6F61), .white]
            for i in 0..<12 {
                let a = Float(i) / 12 * 2 * .pi
                ball(0.0055, colors[i % 4], at: [(r + 0.002) * sin(a), -0.002, (r + 0.002) * cos(a)],
                     scale: [1, 0.75, 1], in: ring)
            }
        case .medal:
            let blue = UIColor(hex: 0x3A6FD8)
            for s: Float in [-1, 1] {
                box([0.005, 0.02, 0.002], corner: 0.001, blue, at: [s * 0.004, -0.006, front + 0.001],
                    rotation: rotZ(s * 0.35), in: ring)
            }
            disc(0.008, gold, at: [0, -0.019, front + 0.003], shiny: true, in: ring)
            ball(0.003, UIColor(hex: 0xFFE38A), at: [0, -0.019, front + 0.005], scale: [1, 1, 0.4], in: ring)
        case .necktie:
            let blue = UIColor(hex: 0x3A6FD8)
            ball(0.0045, blue, at: [0, -0.002, front + 0.001], scale: [1.2, 1, 0.6], in: ring)
            box([0.009, 0.03, 0.003], corner: 0.002, blue, at: [0, -0.02, front + 0.001], in: ring)
            cone(height: 0.007, radius: 0.0062, blue, at: [0, -0.0375, front + 0.001], rotation: rotZ(.pi),
                 scale: [1, 1, 0.35], in: ring)
            for k in 0..<2 {
                box([0.009, 0.002, 0.001], corner: 0, UIColor(hex: 0xFFD45C), at: [0, -0.012 - Float(k) * 0.01, front + 0.003],
                    rotation: rotZ(0.4), in: ring)
            }
        case .pearls:
            for i in 0..<18 {
                let a = Float(i) / 18 * 2 * .pi
                let pearl = ball(0.0032, UIColor(hex: 0xFBF6EE),
                                 at: [(r + 0.0015) * sin(a), -0.004 - 0.003 * cos(a), (r + 0.0015) * cos(a)], in: ring)
                pearl.model?.materials = [material(UIColor(hex: 0xFBF6EE), shiny: true)]
            }
        case .bellCollar:
            cylinder(height: 0.006, radius: r * 1.02, red, at: [0, 0, 0], in: ring)
            let bell = ball(0.0058, gold, at: [0, -0.007, front + 0.004], in: ring)
            bell.model?.materials = [material(gold, shiny: true)]
            box([0.006, 0.0012, 0.001], corner: 0, dark, at: [0, -0.009, front + 0.0095], in: ring)
        case .fairyWings:
            let p = Entity()
            p.position = [0, -0.004, -r * 0.95]
            ring.addChild(p)
            let wing = UIColor(hex: 0xEEF6FF), edge = UIColor(hex: 0xD9C4F7)
            for s: Float in [-1, 1] {
                // big upper wing spreading up and out, smaller lower wing below it
                ball(0.021, wing, at: [s * 0.024, 0.014, -0.004], scale: [0.95, 1.45, 0.14],
                     rotation: rotZ(-s * 0.6), in: p)
                ball(0.0135, edge, at: [s * 0.018, -0.012, -0.003], scale: [0.95, 1.25, 0.14],
                     rotation: rotZ(-s * 0.3), in: p)
                ball(0.003, UIColor(hex: 0xFFD45C), at: [s * 0.03, 0.026, -0.001], in: p)   // a little sparkle
            }
        case .backpack:
            let orange = UIColor(hex: 0xF28C38)
            box([r * 1.5, 0.036, 0.018], corner: 0.006, orange, at: [0, -0.024, -r - 0.008], in: ring)
            box([r * 1.1, 0.014, 0.006], corner: 0.003, UIColor(hex: 0xE06A1C), at: [0, -0.031, -r - 0.019], in: ring)
            for s: Float in [-1, 1] {
                box([0.004, 0.003, r * 1.6], corner: 0.001, UIColor(hex: 0x3B4252), at: [s * r * 0.45, 0.002, 0], in: ring)
            }
        default:
            break
        }
    }
}

private extension FigureBuilder {
    @discardableResult
    static func ball(_ radius: Float, _ color: UIColor, at position: SIMD3<Float>,
                     scale: SIMD3<Float>, rotation: simd_quatf, in parent: Entity) -> ModelEntity {
        let e = ball(radius, color, at: position, scale: scale, in: parent)
        e.orientation = rotation
        return e
    }
}
