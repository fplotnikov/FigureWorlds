import ImageIO
import RealityKit
import UIKit

/// Loads the animated animals (models/make_bunny.py, models/make_meshy_animal.py) once,
/// keeps them as templates and hands out clones. Animals without a model file keep
/// using the shape-built figures from FigureBuilder.
final class RealModelLibrary {
    static let shared = RealModelLibrary()
    static let didLoad = Notification.Name("RealModelLibrary.didLoad")

    /// Animals that have a Blender model in Resources (file name without extension).
    /// All six are Meshy models with our own rig additions and clips (make_meshy_animal.py).
    /// The older all-Blender bunny lives in models/blender_bunny as a fallback.
    static let files: [Animal: String] = [
        .bunny: "bunny", .kitty: "kitty", .bear: "bear", .penguin: "penguin", .frog: "frog", .fox: "fox",
        .mosskip: "mosskip", .glassfin: "glassfin", .cindermole: "cindermole", .cloudlope: "cloudlope",
        .thimblebat: "thimblebat", .pebblenewt: "pebblenewt", .bloomusk: "bloomusk",
        .velvetide: "velvetide", .lanternquill: "lanternquill", .dunewisp: "dunewisp",
        .pleatbill: "pleatbill", .coilusk: "coilusk", .siftrunk: "siftrunk", .spindlecrab: "spindlecrab",
        .ripplemantis: "ripplemantis", .tuftwhale: "tuftwhale", .knotcko: "knotcko", .cupspinner: "cupspinner",
        .supercar: "supercar", .jet: "jet", .motorcycle: "motorcycle", .truck: "truck",
        .helicopter: "helicopter", .rally: "rally", .seaplane: "seaplane", .snowmobile: "snowmobile",
        .excavator: "excavator", .speedboat: "speedboat",
        .locomotive: "locomotive", .submarine: "submarine", .tractor: "tractor", .citybus: "citybus",
        .forklift: "forklift", .cablecar: "cablecar", .lunarrover: "lunarrover", .airship: "airship",
        .raccoon: "raccoon", .moth: "moth", .crocodile: "crocodile", .ram: "ram", .pelican: "pelican",
        .armadillo: "armadillo", .lynx: "lynx", .frogsinger: "frogsinger", .vulture: "vulture",
        .anteater: "anteater",
        .showelephant: "showelephant", .pangolin: "pangolin", .skateostrich: "skateostrich", .lobster: "lobster",
        .chameleon: "chameleon", .walrus: "walrus", .showkangaroo: "showkangaroo", .sloth: "sloth",
        .lion: "lion", .zebra: "zebra", .ostrich: "ostrich", .horse: "horse", .tiger: "tiger", .beaver: "beaver", .raccoonkid: "raccoonkid", .elephant: "elephant", .hippo: "hippo", .rhino: "rhino", .mouse: "mouse", .turtle: "turtle",
        .shark: "shark", .mole: "mole", .bee: "bee", .parrot: "parrot", .koala: "koala", .panda: "panda",
        .deer: "deer", .redpanda: "redpanda", .moose: "moose", .kangaroo: "kangaroo", .giraffe: "giraffe", .capybara: "capybara",
        .trex: "trex", .triceratops: "triceratops", .stegosaurus: "stegosaurus", .velociraptor: "velociraptor", .brachiosaurus: "brachiosaurus", .spinosaurus: "spinosaurus", .ankylosaurus: "ankylosaurus", .pteranodon: "pteranodon", .parasaurolophus: "parasaurolophus", .diplodocus: "diplodocus", .pachycephalosaurus: "pachycephalosaurus", .allosaurus: "allosaurus",
        .styracosaurus: "styracosaurus", .iguanodon: "iguanodon", .carnotaurus: "carnotaurus", .therizinosaurus: "therizinosaurus", .gallimimus: "gallimimus", .dilophosaurus: "dilophosaurus", .mosasaurus: "mosasaurus", .elasmosaurus: "elasmosaurus", .ichthyosaurus: "ichthyosaurus", .megalodon: "megalodon"
    ]

    /// A robot's vehicle (models/make_vehicle.py): what it changes into when it runs.
    struct Vehicle {
        enum Kind: String, Decodable {
            case car, truck, bike, snow, digger, jet, plane, heli, boat
            case train, sub, tractor, bus, forklift, cable, rover, airship
        }
        let entity: Entity
        let kind: Kind
        let length: Float
        let height: Float
    }

    struct Template {
        let name: String
        let entity: Entity
        let clips: [String: AnimationResource]
        /// Where extras sit (from the clips JSON); nil means the Blender bunny's fit.
        let fit: HeadFit?
        /// Skins that have a pre-baked colour texture (<name>_skin_<skin>.png).
        let skinTextures: Set<String>
        /// How far the body is turned from facing the viewer (creatures stand like their
        /// picture). Running turns the figure by this so it runs head first.
        let bodyYaw: Float
        /// Robots only.
        let vehicle: Vehicle?
        /// The box the position map (<name>_pos.png) is measured in; nil = no patterns.
        let posBox: [Float]?
    }

    /// Toy animals with a position map can wear a pattern over their colour.
    static func supportsPatterns(_ animal: Animal) -> Bool {
        guard animal.group == .animals, let name = files[animal] else { return false }
        return Bundle.main.url(forResource: name + "_pos", withExtension: "png") != nil
    }

    private var maskCache: [String: PatternPainter.Mask] = [:]
    private var patternCache: [String: TextureResource] = [:]
    private var painting: Set<String> = []

    /// A colour texture with a pattern painted on (PatternPainter). Painting takes a moment,
    /// so it happens in the background: returns the texture when it is ready, otherwise
    /// starts painting and calls `ready` on the main thread when done.
    func patternTexture(_ template: Template, _ skin: Skin, _ pattern: Pattern,
                        ready: @escaping @MainActor (TextureResource) -> Void) -> TextureResource? {
        guard pattern != .plain, let box = template.posBox,
              template.skinTextures.contains(skin.rawValue) else { return nil }
        let key = "\(template.name)_\(skin.rawValue)_\(pattern.rawValue)"
        if let cached = patternCache[key] { return cached }
        guard !painting.contains(key),
              let posURL = Bundle.main.url(forResource: template.name + "_pos", withExtension: "png") else { return nil }
        let file = "\(template.name)_skin_\(skin.rawValue)"
        guard let skinURL = Bundle.main.url(forResource: file, withExtension: "jpg")
                ?? Bundle.main.url(forResource: file, withExtension: "png") else { return nil }
        painting.insert(key)
        let maskKey = "\(template.name)_\(pattern.rawValue)"
        let knownMask = maskCache[maskKey]
        Task.detached(priority: .userInitiated) {
            let mask = knownMask ?? PatternPainter.mask(posURL: posURL, box: box, pattern: pattern)
            var painted: CGImage?
            if let mask, let src = CGImageSourceCreateWithURL(skinURL as CFURL, nil),
               let base = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                painted = PatternPainter.paint(base: base, mask: mask, ink: PatternPainter.ink(for: skin))
            }
            let result = painted
            await MainActor.run {
                self.painting.remove(key)
                if let mask { self.maskCache[maskKey] = mask }
                guard let result,
                      let texture = try? TextureResource(image: result, withName: nil,
                                                         options: .init(semantic: .color)) else { return }
                self.patternCache[key] = texture
                ready(texture)
            }
        }
        return nil
    }

    private var textureCache: [String: TextureResource] = [:]

    /// The pre-baked colour texture for a skin, loaded on first use and kept.
    func skinTexture(_ template: Template, _ skin: Skin) -> TextureResource? {
        guard template.skinTextures.contains(skin.rawValue) else { return nil }
        let file = "\(template.name)_skin_\(skin.rawValue)"
        if let cached = textureCache[file] { return cached }
        guard let url = Bundle.main.url(forResource: file, withExtension: "jpg")
                ?? Bundle.main.url(forResource: file, withExtension: "png") else { return nil }
        let texture = MainActor.assumeIsolated {
            try? TextureResource.load(contentsOf: url, options: .init(semantic: .color))
        }
        textureCache[file] = texture
        return texture
    }

    private(set) var templates: [Animal: Template] = [:]
    private var loading: Set<Animal> = []

    func template(for animal: Animal) -> Template? { templates[animal] }

    /// Starts loading every model in the background. Safe to call more than once.
    func preloadAll() {
        for animal in Self.files.keys { load(animal) }
    }

    func load(_ animal: Animal) {
        guard let name = Self.files[animal], templates[animal] == nil, !loading.contains(animal) else { return }
        loading.insert(animal)
        Task { @MainActor in
            do {
                let template = try await Self.makeTemplate(name: name)
                self.templates[animal] = template
                NotificationCenter.default.post(name: Self.didLoad, object: nil)
            } catch {
                print("Figure Shelf: could not load \(name).usdz, using the shape figure. \(error)")
            }
            self.loading.remove(animal)
        }
    }

    private struct ClipFile: Decodable {
        struct Clip: Decodable {
            let name: String
            let startTime: Double
            let endTime: Double
        }
        let clips: [Clip]
        let fit: HeadFit?
        let skins: [String]?
        let bodyYaw: Float?
        struct VehicleInfo: Decodable {
            let file: String
            let kind: Vehicle.Kind
            let length: Float
            let height: Float
        }
        let vehicle: VehicleInfo?
        let posBox: [Float]?
    }

    @MainActor
    private static func makeTemplate(name: String) async throws -> Template {
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
              let clipsURL = Bundle.main.url(forResource: name + "_clips", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let entity = try await Entity(contentsOf: url)
        let info = try JSONDecoder().decode(ClipFile.self, from: Data(contentsOf: clipsURL))

        var clips: [String: AnimationResource] = [:]
        if let timeline = entity.availableAnimations.first {
            for clip in info.clips {
                let view = AnimationView(
                    source: timeline.definition,
                    name: clip.name,
                    repeatMode: clip.name == "idle" ? .repeat : .none,
                    fillMode: .forwards,
                    trimStart: clip.startTime,
                    trimEnd: clip.endTime
                )
                clips[clip.name] = try AnimationResource.generate(with: view)
                if clip.name == "run" {
                    // Figure Worlds: walking plays the run clip over and over.
                    let loop = AnimationView(
                        source: timeline.definition,
                        name: "run.loop",
                        repeatMode: .repeat,
                        fillMode: .forwards,
                        trimStart: clip.startTime,
                        trimEnd: clip.endTime
                    )
                    clips["run.loop"] = try AnimationResource.generate(with: loop)
                }
            }
        }
        var vehicle: Vehicle?
        if let v = info.vehicle, let vurl = Bundle.main.url(forResource: v.file, withExtension: "usdz") {
            let ventity = try await Entity(contentsOf: vurl)
            vehicle = Vehicle(entity: ventity, kind: v.kind, length: v.length, height: v.height)
        }
        return Template(name: name, entity: entity, clips: clips, fit: info.fit,
                        skinTextures: Set(info.skins ?? []), bodyYaw: info.bodyYaw ?? 0, vehicle: vehicle,
                        posBox: info.posBox)
    }
}

/// Where extras sit on a figure, in figure space at rest (metres, y up, facing +z).
struct HeadFit: Codable {
    /// True when measured on a model (clips JSON), false for the hand-placed shape fits.
    var measured = false
    var top: Float = 0.176
    var eyeY: Float = 0.146
    var eyeX: Float = 0.017
    var faceZ: Float = 0.05
    var neckY: Float = 0.098
    var neckZ: Float = 0.044
    var neckRadius: Float = 0.043
    var flower: SIMD3<Float> = [0.03, 0.172, 0.014]
    var hatScale: Float = 1
    // Creatures (optional in the JSON, 0 for the animals): their heads sit forward and
    // may look a little to the side.
    /// Middle of the head (x, z) for hats and crowns.
    var headX: Float = 0
    var headZ: Float = 0
    /// Middle of the glasses (x) and how far the face is turned about +y.
    var faceX: Float = 0
    var faceYaw: Float = 0
    /// Bow tie (x), and the middle of the neck (x, z) for the scarf.
    var neckX: Float = 0
    var neckCX: Float = 0
    var neckCZ: Float = 0
    /// Dinosaurs: how far the neck leans forward from upright (radians); neck items tilt with it.
    var neckPitch: Float = 0
    /// Nose tip (measured by models/measure_nose.py); nil for the shape figures.
    var nose: SIMD3<Float>?

    static let shapes = HeadFit()

    enum CodingKeys: String, CodingKey {
        case top, eyeY, eyeX, faceZ, neckY, neckZ, neckRadius, flower, hatScale
        case headX, headZ, faceX, faceYaw, neckX, neckCX, neckCZ, neckPitch
        case noseX, noseY, noseZ
    }

    init(top: Float = 0.176, eyeY: Float = 0.146, eyeX: Float = 0.017, faceZ: Float = 0.05,
         neckY: Float = 0.098, neckZ: Float = 0.044, neckRadius: Float = 0.043,
         flower: SIMD3<Float> = [0.03, 0.172, 0.014], hatScale: Float = 1) {
        self.top = top; self.eyeY = eyeY; self.eyeX = eyeX; self.faceZ = faceZ
        self.neckY = neckY; self.neckZ = neckZ; self.neckRadius = neckRadius
        self.flower = flower; self.hatScale = hatScale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(top: try c.decode(Float.self, forKey: .top), eyeY: try c.decode(Float.self, forKey: .eyeY),
                  eyeX: try c.decode(Float.self, forKey: .eyeX), faceZ: try c.decode(Float.self, forKey: .faceZ),
                  neckY: try c.decode(Float.self, forKey: .neckY), neckZ: try c.decode(Float.self, forKey: .neckZ),
                  neckRadius: try c.decode(Float.self, forKey: .neckRadius),
                  flower: try c.decode(SIMD3<Float>.self, forKey: .flower),
                  hatScale: try c.decode(Float.self, forKey: .hatScale))
        headX = try c.decodeIfPresent(Float.self, forKey: .headX) ?? 0
        headZ = try c.decodeIfPresent(Float.self, forKey: .headZ) ?? 0
        faceX = try c.decodeIfPresent(Float.self, forKey: .faceX) ?? 0
        faceYaw = try c.decodeIfPresent(Float.self, forKey: .faceYaw) ?? 0
        neckX = try c.decodeIfPresent(Float.self, forKey: .neckX) ?? 0
        neckCX = try c.decodeIfPresent(Float.self, forKey: .neckCX) ?? 0
        neckCZ = try c.decodeIfPresent(Float.self, forKey: .neckCZ) ?? 0
        neckPitch = try c.decodeIfPresent(Float.self, forKey: .neckPitch) ?? 0
        if let x = try c.decodeIfPresent(Float.self, forKey: .noseX),
           let y = try c.decodeIfPresent(Float.self, forKey: .noseY),
           let z = try c.decodeIfPresent(Float.self, forKey: .noseZ) {
            nose = [x, y, z]
        }
        measured = true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(top, forKey: .top); try c.encode(eyeY, forKey: .eyeY); try c.encode(eyeX, forKey: .eyeX)
        try c.encode(faceZ, forKey: .faceZ); try c.encode(neckY, forKey: .neckY); try c.encode(neckZ, forKey: .neckZ)
        try c.encode(neckRadius, forKey: .neckRadius); try c.encode(flower, forKey: .flower)
        try c.encode(hatScale, forKey: .hatScale)
    }

    /// Measured from the Blender bunny's rest pose (make_bunny.py, S = 0.2 / 2.45).
    static let realBunny = HeadFit(
        top: 0.146, eyeY: 0.1165, eyeX: 0.0172, faceZ: 0.0425,
        neckY: 0.079, neckZ: 0.026, neckRadius: 0.027,
        flower: [0.03, 0.138, 0.016], hatScale: 0.8
    )
}

/// One clone of a Blender model, with recoloring, extras that follow the head,
/// and clip playback.
final class RealFigure {
    let animal: Animal
    let body = Entity()
    private let model: Entity
    private let clips: [String: AnimationResource]
    private let template: RealModelLibrary.Template
    private var skin: Skin?
    private var pattern: Pattern = .plain

    private let headAnchor = Entity()
    private let neckAnchor = Entity()
    private var extras: [Entity] = []
    private var wear: [Wearable]?

    private var headPin: GeometricPin?
    private var neckPin: GeometricPin?
    private var headRest: (SIMD3<Float>, simd_quatf)?
    private var neckRest: (SIMD3<Float>, simd_quatf)?
    private var currentClip: String?

    init(template: RealModelLibrary.Template, look: Look) {
        animal = look.animal
        model = template.entity.clone(recursive: true)
        clips = template.clips
        self.template = template
        body.name = "figure"
        body.addChild(model)
        body.addChild(headAnchor)
        body.addChild(neckAnchor)

        if let skinned = Self.descendants(of: model).first(where: {
            ($0 as? ModelEntity)?.jointNames.isEmpty == false
        }) as? ModelEntity {
            // Joint paths look like "root/hips/spine/head" (Blender bunny) or
            // "root/Hips/Spine02/Spine01/Spine/neck/Head" (Meshy rigs).
            let names = skinned.jointNames
            func joint(_ last: String) -> String? {
                names.first { $0.lowercased().hasSuffix("/" + last) }
            }
            MainActor.assumeIsolated {
                if let head = joint("head") {
                    headPin = skinned.pins.set(named: "figureshelf.head", skeletalJointName: head)
                }
                if let neck = joint("neck") ?? joint("spine") {
                    neckPin = skinned.pins.set(named: "figureshelf.neck", skeletalJointName: neck)
                }
            }
        }
        headRest = pose(of: headPin)
        neckRest = pose(of: neckPin)
        // Realistic dinosaurs have thin one-sided parts (frills, sails, wings): draw both sides.
        if animal.group == .dinosaurs { showBackFaces() }
        apply(look)
    }

    private func showBackFaces() {
        for entity in Self.descendants(of: model) {
            guard var component = entity.components[ModelComponent.self] else { continue }
            component.materials = component.materials.map { material -> any Material in
                guard var pbr = material as? PhysicallyBasedMaterial else { return material }
                pbr.faceCulling = .none
                return pbr
            }
            entity.components.set(component)
        }
    }

    func hasClip(_ name: String) -> Bool { clips[name] != nil }

    var bodyYaw: Float { template.bodyYaw }
    var vehicleInfo: RealModelLibrary.Vehicle? { template.vehicle }

    /// Recolors (flat Main / Belly materials, or a pre-baked texture for painted
    /// models) and swaps the extra. Keeps the running animation.
    func apply(_ look: Look) {
        let wantPattern: Pattern = RealModelLibrary.supportsPatterns(animal) ? look.pattern : .plain
        if look.skin != skin || wantPattern != pattern {
            skin = look.skin
            pattern = wantPattern
            let lookSkin = look.skin
            if let painted = RealModelLibrary.shared.patternTexture(template, lookSkin, wantPattern, ready: { [weak self] texture in
                // still the same colour and pattern once painting is done
                guard let self, self.skin == lookSkin, self.pattern == wantPattern else { return }
                self.retexture(texture)
            }) {
                retexture(painted)
            } else if let texture = RealModelLibrary.shared.skinTexture(template, look.skin) {
                retexture(texture)       // the plain colour until the pattern is painted
            } else {
                let (main, belly) = look.skin.colors(for: animal)
                recolor(main: main, belly: belly)
            }
        }
        if look.visibleWear != wear {
            wear = look.visibleWear
            extras.forEach { $0.removeFromParent() }
            let head = Entity(), neck = Entity()
            headAnchor.addChild(head)
            neckAnchor.addChild(neck)
            extras = [head, neck]
            FigureBuilder.addWear(look.visibleWear, animal: animal, fit: template.fit ?? .realBunny,
                                  head: head, neck: neck)
        }
    }

    func play(_ name: String, transition: TimeInterval = 0.25) {
        guard let clip = clips[name] else { return }
        currentClip = name
        model.playAnimation(clip, transitionDuration: transition, startsPaused: false)
    }

    func playIdle(transition: TimeInterval = 0.25) {
        guard currentClip != "idle" else { return }
        play("idle", transition: transition)
    }

    /// Figure Worlds: plays a clip on a loop (walking uses "run").
    func playLoop(_ name: String, transition: TimeInterval = 0.2) {
        let key = name + ".loop"
        guard currentClip != key else { return }
        guard clips[key] != nil else { play(name, transition: transition); return }
        play(key, transition: transition)
    }

    /// Moves the extras with the head and neck bones. Call once per frame.
    func followBones() {
        if headRest == nil { headRest = pose(of: headPin) }
        if neckRest == nil { neckRest = pose(of: neckPin) }
        follow(headAnchor, pin: headPin, rest: headRest)
        follow(neckAnchor, pin: neckPin, rest: neckRest)
    }

    // MARK: - Private

    private func pose(of pin: GeometricPin?) -> (SIMD3<Float>, simd_quatf)? {
        guard let pin else { return nil }
        let body = self.body
        return MainActor.assumeIsolated {
            guard let p = pin.position(relativeTo: body),
                  let q = pin.orientation(relativeTo: body) else { return nil }
            return (p, q)
        }
    }

    private func follow(_ anchor: Entity, pin: GeometricPin?, rest: (SIMD3<Float>, simd_quatf)?) {
        guard let rest, let now = pose(of: pin) else { return }
        // Map the rest-pose frame onto the current frame.
        let q = now.1 * rest.1.inverse
        anchor.orientation = q
        anchor.position = now.0 - q.act(rest.0)
    }

    /// RealityKit merges the USD meshes into one skinned model, but keeps the
    /// material names from Blender ("Main", "Belly", "Accent", "Eyes").
    private func recolor(main: UIColor, belly: UIColor) {
        for entity in Self.descendants(of: model) {
            guard var component = entity.components[ModelComponent.self] else { continue }
            var partNames: [Int: String] = [:]
            for m in component.mesh.contents.models {
                for part in m.parts { partNames[part.materialIndex] = part.id }
            }
            component.materials = component.materials.enumerated().map { index, material -> any Material in
                guard var pbr = material as? PhysicallyBasedMaterial else { return material }
                switch pbr.name ?? partNames[index] {
                case "Main": pbr.baseColor = .init(tint: main)
                case "Belly": pbr.baseColor = .init(tint: belly)
                default: return material
                }
                return pbr
            }
            entity.components.set(component)
        }
    }

    /// Painted (Meshy) models have one textured material named "Skin".
    private func retexture(_ texture: TextureResource) {
        for entity in Self.descendants(of: model) {
            guard var component = entity.components[ModelComponent.self] else { continue }
            component.materials = component.materials.map { material -> any Material in
                guard var pbr = material as? PhysicallyBasedMaterial,
                      pbr.name?.hasPrefix("Skin") == true else { return material }
                pbr.baseColor = .init(tint: .white, texture: .init(texture))
                return pbr
            }
            entity.components.set(component)
        }
    }

    private static func descendants(of entity: Entity) -> [Entity] {
        var out: [Entity] = [entity]
        for child in entity.children { out += descendants(of: child) }
        return out
    }
}

