import SwiftUI
import UIKit

// MARK: - Colors

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Palette {
    static let background = Color(uiColor: UIColor(hex: 0xFBF7F0))
    static let panel = Color.white
    static let tile = Color(uiColor: UIColor(hex: 0xF3EEE6))
    static let selected = Color(uiColor: UIColor(hex: 0xF4A259))
    static let ink = Color(uiColor: UIColor(hex: 0x3B3A48))
    /// Disabled icons: still clearly drawn on the white buttons, just lighter.
    static let inkDisabled = Color(uiColor: UIColor(hex: 0xA9A8B4))
    static let action = Color(uiColor: UIColor(hex: 0xDCEBFF))
    static let actionInk = Color(uiColor: UIColor(hex: 0x2F5DA8))
}

// MARK: - Animals and creatures

enum AnimalGroup: String, CaseIterable, Identifiable {
    case animals, dinosaurs, creatures, robots, animatronics
    var id: String { rawValue }
    var title: String {
        switch self {
        case .animals: "Animals"
        case .dinosaurs: "Dinosaurs"
        case .creatures: "Creatures"
        case .robots: "Robots"
        case .animatronics: "Animatronics"
        }
    }
}

/// Every figure on the shelf. The first six are the animals; the rest are Fedir's own
/// imaginary creatures (models/creatures, rigged by make_meshy_animal.py).
enum Animal: String, CaseIterable, Identifiable, Codable {
    case bunny, kitty, bear, penguin, frog, fox
    case mosskip, glassfin, cindermole, cloudlope, thimblebat
    case pebblenewt, bloomusk, velvetide, lanternquill, dunewisp
    case pleatbill, coilusk, siftrunk, spindlecrab, ripplemantis, tuftwhale, knotcko, cupspinner
    // Fedir's robots: each one changes into its vehicle when it runs
    case supercar, jet, motorcycle, truck, helicopter, rally, seaplane, snowmobile, excavator, speedboat
    case locomotive, submarine, tractor, citybus, forklift, cablecar, lunarrover, airship
    // Fedir's animatronics: vintage theme-park performers that move in stiff servo steps
    case raccoon, moth, crocodile, ram, pelican, armadillo, lynx, frogsinger, vulture, anteater
    case showelephant, pangolin, skateostrich, lobster, chameleon, walrus, showkangaroo, sloth
    // more animals (toy style, Meshy humanoid rig)
    case lion, zebra, ostrich, horse, tiger, beaver, raccoonkid, elephant, hippo, rhino, mouse, turtle
    case shark, mole, bee, parrot, koala, panda
    case deer, redpanda, moose, kangaroo, giraffe, capybara
    // dinosaurs: realistic, museum-style models
    case trex, triceratops, stegosaurus, velociraptor, brachiosaurus, spinosaurus, ankylosaurus, pteranodon, parasaurolophus, diplodocus, pachycephalosaurus, allosaurus

    var id: String { rawValue }

    var isAnimatronic: Bool { group == .animatronics }

    var group: AnimalGroup {
        switch self {
        case .bunny, .kitty, .bear, .penguin, .frog, .fox: .animals
        case .lion, .zebra, .ostrich, .horse, .tiger, .beaver, .raccoonkid, .elephant, .hippo, .rhino, .mouse, .turtle: .animals
        case .shark, .mole, .bee, .parrot, .koala, .panda: .animals
        case .deer, .redpanda, .moose, .kangaroo, .giraffe, .capybara: .animals
        case .trex, .triceratops, .stegosaurus, .velociraptor, .brachiosaurus, .spinosaurus, .ankylosaurus, .pteranodon, .parasaurolophus, .diplodocus, .pachycephalosaurus, .allosaurus: .dinosaurs
        case .supercar, .jet, .motorcycle, .truck, .helicopter, .rally, .seaplane, .snowmobile,
             .excavator, .speedboat,
             .locomotive, .submarine, .tractor, .citybus, .forklift, .cablecar, .lunarrover, .airship: .robots
        case .raccoon, .moth, .crocodile, .ram, .pelican, .armadillo, .lynx, .frogsinger, .vulture,
             .anteater, .showelephant, .pangolin, .skateostrich, .lobster, .chameleon, .walrus,
             .showkangaroo, .sloth: .animatronics
        default: .creatures
        }
    }

    /// Figures whose model is in the app (a figure still being made stays hidden).
    static func all(in group: AnimalGroup) -> [Animal] {
        allCases.filter { $0.group == group && $0.isInstalled }
    }

    var isInstalled: Bool {
        guard let file = RealModelLibrary.files[self] else { return false }
        return Bundle.main.url(forResource: file, withExtension: "usdz") != nil
    }

    var name: String {
        switch self {
        case .bunny: "Bunny"
        case .kitty: "Kitty"
        case .bear: "Bear"
        case .penguin: "Penguin"
        case .frog: "Frog"
        case .fox: "Fox"
        case .truck: "Big Truck"
        case .frogsinger: "Frog Singer"
        case .raccoonkid: "Raccoon"
        case .redpanda: "Red Panda"
        case .hippo: "Hippo"
        case .rhino: "Rhino"
        case .trex: "T. rex"
        case .showelephant: "Elephant"
        case .skateostrich: "Ostrich"
        case .showkangaroo: "Kangaroo"
        case .citybus: "City Bus"
        case .cablecar: "Cable Car"
        case .lunarrover: "Lunar Rover"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// Animals have an emoji; creatures use a small rendered picture instead.
    var emoji: String? {
        switch self {
        case .bunny: "🐰"
        case .kitty: "🐱"
        case .bear: "🐻"
        case .penguin: "🐧"
        case .frog: "🐸"
        case .fox: "🦊"
        default: nil
        }
    }

    /// The chooser picture for a creature (<name>_thumb.png, rendered in Blender).
    var thumbnail: UIImage? {
        guard emoji == nil, let path = Bundle.main.path(forResource: rawValue + "_thumb", ofType: "png") else { return nil }
        return UIImage(contentsOfFile: path)
    }

    var mainColor: UIColor {
        switch self {
        case .bunny: UIColor(hex: 0xD9C7B8)
        case .kitty: UIColor(hex: 0xF4A259)
        case .bear: UIColor(hex: 0x9C6B4E)
        case .penguin: UIColor(hex: 0x2F3A4A)
        case .frog: UIColor(hex: 0x7BC86C)
        case .fox: UIColor(hex: 0xE8743B)
        // creatures: the average painted colour of each model (clips JSON "mainColor")
        case .mosskip: UIColor(hex: 0xA79661)
        case .glassfin: UIColor(hex: 0x2E3044)
        case .cindermole: UIColor(hex: 0xBE704E)
        case .cloudlope: UIColor(hex: 0x9A8BD5)
        case .thimblebat: UIColor(hex: 0x8D3E37)
        case .pebblenewt: UIColor(hex: 0x4F78A0)
        case .bloomusk: UIColor(hex: 0x553F6D)
        case .velvetide: UIColor(hex: 0x2F4C9A)
        case .lanternquill: UIColor(hex: 0x984C28)
        case .dunewisp: UIColor(hex: 0xE6D3AE)
        case .pleatbill: UIColor(hex: 0xAD6C63)
        case .coilusk: UIColor(hex: 0xBA502C)
        case .siftrunk: UIColor(hex: 0x816C85)
        case .spindlecrab: UIColor(hex: 0x787283)
        case .ripplemantis: UIColor(hex: 0x987446)
        case .tuftwhale: UIColor(hex: 0x9C756B)
        case .knotcko: UIColor(hex: 0xC46F54)
        case .cupspinner: UIColor(hex: 0x955260)
        case .supercar: UIColor(hex: 0x2C4BB0)
        case .jet: UIColor(hex: 0xA8343F)
        case .motorcycle: UIColor(hex: 0x9ACD32)
        case .truck: UIColor(hex: 0xD9731F)
        case .helicopter: UIColor(hex: 0xE3B02A)
        case .rally: UIColor(hex: 0x7A2430)
        case .seaplane: UIColor(hex: 0x6E9E8C)
        case .snowmobile: UIColor(hex: 0x6E4BB5)
        case .excavator: UIColor(hex: 0xE09A22)
        case .speedboat: UIColor(hex: 0x2E9EA0)
        case .locomotive: UIColor(hex: 0x2E6B4A)
        case .submarine: UIColor(hex: 0xE0703A)
        case .tractor: UIColor(hex: 0x8E2A35)
        case .citybus: UIColor(hex: 0x2BA59B)
        case .forklift: UIColor(hex: 0xF2B233)
        case .cablecar: UIColor(hex: 0xA8323C)
        case .lunarrover: UIColor(hex: 0xD9C7A8)
        case .airship: UIColor(hex: 0x6B3F6E)
        case .raccoon: UIColor(hex: 0x5E8A86)
        case .moth: UIColor(hex: 0x7A5A8C)
        case .crocodile: UIColor(hex: 0x5E7A3A)
        case .ram: UIColor(hex: 0x7A2A30)
        case .pelican: UIColor(hex: 0xE8DCC8)
        case .armadillo: UIColor(hex: 0xA8683A)
        case .lynx: UIColor(hex: 0xD08A3A)
        case .frogsinger: UIColor(hex: 0x8CB89A)
        case .vulture: UIColor(hex: 0x4A4048)
        case .anteater: UIColor(hex: 0xC48A8A)
        case .showelephant: UIColor(hex: 0x6E6C93)
        case .pangolin: UIColor(hex: 0xC9A24E)
        case .skateostrich: UIColor(hex: 0xD99AAE)
        case .lobster: UIColor(hex: 0xC2453A)
        case .chameleon: UIColor(hex: 0xB9C24E)
        case .walrus: UIColor(hex: 0xA8664E)
        case .showkangaroo: UIColor(hex: 0xD9785A)
        case .sloth: UIColor(hex: 0xA8948A)
        case .lion: UIColor(hex: 0xE89A3C)
        case .zebra: UIColor(hex: 0x3A3A3A)
        case .ostrich: UIColor(hex: 0xA06260)
        case .horse: UIColor(hex: 0x8A5232)
        case .tiger: UIColor(hex: 0xE0661A)
        case .beaver: UIColor(hex: 0x7A4A2A)
        case .raccoonkid: UIColor(hex: 0x8A8F96)
        case .elephant: UIColor(hex: 0x7A90AE)
        case .hippo: UIColor(hex: 0x9C98C0)
        case .rhino: UIColor(hex: 0x6A6A6A)
        case .mouse: UIColor(hex: 0xB8B8C8)
        case .turtle: UIColor(hex: 0x6E9A34)
        case .shark: UIColor(hex: 0x7F95B5)
        case .mole: UIColor(hex: 0x5A4A44)
        case .bee: UIColor(hex: 0xF2C230)
        case .parrot: UIColor(hex: 0x6CC04A)
        case .koala: UIColor(hex: 0x9A9EA6)
        case .panda: UIColor(hex: 0x2B2B2B)
        case .deer: UIColor(hex: 0xAE7147)
        case .redpanda: UIColor(hex: 0x793317)
        case .moose: UIColor(hex: 0x5C3C29)
        case .kangaroo: UIColor(hex: 0xD48238)
        case .giraffe: UIColor(hex: 0xDFA34C)
        case .capybara: UIColor(hex: 0xB8623B)
        case .trex: UIColor(hex: 0x6B6440)
        case .triceratops: UIColor(hex: 0x7A7670)
        case .stegosaurus: UIColor(hex: 0x8A8A4A)
        case .velociraptor: UIColor(hex: 0x7A5A3A)
        case .brachiosaurus: UIColor(hex: 0x6E7A6A)
        case .spinosaurus: UIColor(hex: 0x4A5236)
        case .ankylosaurus: UIColor(hex: 0xB09A74)
        case .pteranodon: UIColor(hex: 0xB8A890)
        case .parasaurolophus: UIColor(hex: 0x8AA070)
        case .diplodocus: UIColor(hex: 0x7E7A72)
        case .pachycephalosaurus: UIColor(hex: 0x7A5A3E)
        case .allosaurus: UIColor(hex: 0xA07A3E)
        }
    }

    var bellyColor: UIColor {
        switch self {
        case .bunny: UIColor(hex: 0xFFF8F0)
        case .kitty: UIColor(hex: 0xFFF1DE)
        case .bear: UIColor(hex: 0xE8C9A9)
        case .penguin: UIColor(hex: 0xFFFFFF)
        case .frog: UIColor(hex: 0xE6F5C9)
        case .fox: UIColor(hex: 0xFFF6EC)
        case .mosskip: UIColor(hex: 0xF4A98A)
        case .glassfin: UIColor(hex: 0x6FD3C3)
        case .cindermole: UIColor(hex: 0xF2DCC0)
        case .cloudlope: UIColor(hex: 0xF3EEFF)
        case .thimblebat: UIColor(hex: 0xF6B43C)
        case .pebblenewt: UIColor(hex: 0xF0E6CC)
        case .bloomusk: UIColor(hex: 0xF7B6CF)
        case .velvetide: UIColor(hex: 0xA8F0D2)
        case .lanternquill: UIColor(hex: 0xFFC27A)
        case .dunewisp: UIColor(hex: 0x4FB8C2)
        case .pleatbill: UIColor(hex: 0xF6E2D0)
        case .coilusk: UIColor(hex: 0xFFC46B)
        case .siftrunk: UIColor(hex: 0xBFEFE6)
        case .spindlecrab: UIColor(hex: 0xEFE6D6)
        case .ripplemantis: UIColor(hex: 0xEDE48A)
        case .tuftwhale: UIColor(hex: 0xF7D2BE)
        case .knotcko: UIColor(hex: 0xF6E5CF)
        case .cupspinner: UIColor(hex: 0xF4DDE0)
        case .supercar, .jet, .motorcycle, .truck, .helicopter, .rally, .seaplane, .snowmobile,
             .excavator, .speedboat,
             .locomotive, .submarine, .tractor, .citybus, .forklift, .cablecar, .lunarrover, .airship: UIColor(hex: 0xD8DCE2)
        case .raccoon, .moth, .crocodile, .ram, .pelican, .armadillo, .lynx, .frogsinger, .vulture,
             .anteater, .showelephant, .pangolin, .skateostrich, .lobster, .chameleon, .walrus,
             .showkangaroo, .sloth: UIColor(hex: 0xEADFC8)
        case .lion, .zebra, .ostrich, .horse, .tiger, .beaver, .raccoonkid, .elephant, .hippo, .rhino, .mouse, .turtle,
             .shark, .mole, .bee, .parrot, .koala, .panda,
             .deer, .redpanda, .moose, .kangaroo, .giraffe, .capybara: UIColor(hex: 0xF4EBDD)
        case .trex, .triceratops, .stegosaurus, .velociraptor, .brachiosaurus, .spinosaurus, .ankylosaurus, .pteranodon, .parasaurolophus, .diplodocus, .pachycephalosaurus, .allosaurus: UIColor(hex: 0xD8CDB8)
        }
    }

    /// Ears, nose, beak and other small details. Stays the same for every color.
    var accentColor: UIColor {
        switch self {
        case .bunny, .kitty, .frog: UIColor(hex: 0xF7A8B8)
        case .bear: UIColor(hex: 0xE0A383)
        case .penguin: UIColor(hex: 0xF7A23B)
        case .fox: UIColor(hex: 0x3A2A2A)
        default: bellyColor
        }
    }
}

// MARK: - Colors ("skins")

enum Skin: String, CaseIterable, Identifiable, Codable {
    case natural, sunny, ocean, mint, berry, galaxy, snow

    var id: String { rawValue }

    var name: String {
        switch self {
        case .natural: "Normal"
        case .sunny: "Sunny"
        case .ocean: "Ocean"
        case .mint: "Mint"
        case .berry: "Berry"
        case .galaxy: "Night"
        case .snow: "Snow"
        }
    }

    func colors(for animal: Animal) -> (main: UIColor, belly: UIColor) {
        switch self {
        case .natural: (animal.mainColor, animal.bellyColor)
        case .sunny: (UIColor(hex: 0xFFD45C), UIColor(hex: 0xFFF4C7))
        case .ocean: (UIColor(hex: 0x5DA9E9), UIColor(hex: 0xD6ECFF))
        case .mint: (UIColor(hex: 0x7FD8BE), UIColor(hex: 0xE8FFF7))
        case .berry: (UIColor(hex: 0xC86FC9), UIColor(hex: 0xFBE3FB))
        case .galaxy: (UIColor(hex: 0x3D3A8C), UIColor(hex: 0xB9B2FF))
        case .snow: (UIColor(hex: 0xF7F7F7), UIColor(hex: 0xDDE3EA))
        }
    }
}

// MARK: - Patterns (drawn over the color, toy animals only)

enum Pattern: String, CaseIterable, Identifiable, Codable {
    case plain, dots, stripes, checks, stars, hearts

    var id: String { rawValue }

    var name: String {
        switch self {
        case .plain: "Plain"
        case .dots: "Dots"
        case .stripes: "Stripes"
        case .checks: "Checks"
        case .stars: "Stars"
        case .hearts: "Hearts"
        }
    }

    var symbol: String {
        switch self {
        case .plain: "circle"
        case .dots: "circle.grid.3x3.fill"
        case .stripes: "line.3.horizontal"
        case .checks: "checkerboard.rectangle"
        case .stars: "star.fill"
        case .hearts: "heart.fill"
        }
    }
}

// MARK: - Things to wear

/// One item per slot can be worn at the same time.
enum WearSlot: String, CaseIterable, Identifiable, Codable {
    case hat, glasses, mask, neck
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hat: "Hats"
        case .glasses: "Glasses"
        case .mask: "Masks"
        case .neck: "Neck"
        }
    }
}

enum Wearable: String, CaseIterable, Identifiable, Codable {
    // hats (and the flower clip, which also sits on the head)
    case partyHat, crown, topHat, cowboyHat, beanie, cap, wizardHat, pirateHat, chefHat
    case flowerCrown, vikingHelmet, propellerCap, flower
    case santaHat, strawHat, unicornHorn, bunnyEars, hardHat
    // glasses
    case sunglasses, roundGlasses, heartGlasses, starGlasses, goggles, glasses3D, monocle
    case googlyEyes, visor, pixelShades, catEyeGlasses
    // masks
    case heroMask, butterflyMask, clownNose, moustache, ninjaWrap, snorkel
    case beard, whiskers, pigSnout
    // neck
    case bowTie, scarf, cape, flowerNecklace, medal
    case necktie, pearls, bellCollar, fairyWings, backpack

    var id: String { rawValue }

    var slot: WearSlot {
        switch self {
        case .partyHat, .crown, .topHat, .cowboyHat, .beanie, .cap, .wizardHat, .pirateHat, .chefHat,
             .flowerCrown, .vikingHelmet, .propellerCap, .flower,
             .santaHat, .strawHat, .unicornHorn, .bunnyEars, .hardHat: .hat
        case .sunglasses, .roundGlasses, .heartGlasses, .starGlasses, .goggles, .glasses3D, .monocle,
             .googlyEyes, .visor, .pixelShades, .catEyeGlasses: .glasses
        case .heroMask, .butterflyMask, .clownNose, .moustache, .ninjaWrap, .snorkel,
             .beard, .whiskers, .pigSnout: .mask
        case .bowTie, .scarf, .cape, .flowerNecklace, .medal,
             .necktie, .pearls, .bellCollar, .fairyWings, .backpack: .neck
        }
    }

    static func all(in slot: WearSlot) -> [Wearable] { allCases.filter { $0.slot == slot } }

    var name: String {
        switch self {
        case .partyHat: "Party hat"
        case .crown: "Crown"
        case .topHat: "Top hat"
        case .cowboyHat: "Cowboy"
        case .beanie: "Beanie"
        case .cap: "Cap"
        case .wizardHat: "Wizard"
        case .pirateHat: "Pirate"
        case .chefHat: "Chef"
        case .flowerCrown: "Flowers"
        case .vikingHelmet: "Viking"
        case .propellerCap: "Propeller"
        case .flower: "Flower"
        case .sunglasses: "Sunglasses"
        case .roundGlasses: "Round"
        case .heartGlasses: "Hearts"
        case .starGlasses: "Stars"
        case .goggles: "Goggles"
        case .glasses3D: "3D"
        case .monocle: "Monocle"
        case .heroMask: "Hero"
        case .butterflyMask: "Butterfly"
        case .clownNose: "Red nose"
        case .moustache: "Moustache"
        case .ninjaWrap: "Ninja"
        case .snorkel: "Snorkel"
        case .bowTie: "Bow tie"
        case .scarf: "Scarf"
        case .cape: "Cape"
        case .flowerNecklace: "Lei"
        case .medal: "Medal"
        case .santaHat: "Santa"
        case .strawHat: "Sun hat"
        case .unicornHorn: "Unicorn"
        case .bunnyEars: "Bunny ears"
        case .hardHat: "Builder"
        case .googlyEyes: "Googly"
        case .visor: "Visor"
        case .pixelShades: "Pixel"
        case .catEyeGlasses: "Cat-eye"
        case .beard: "Beard"
        case .whiskers: "Whiskers"
        case .pigSnout: "Piggy"
        case .necktie: "Tie"
        case .pearls: "Pearls"
        case .bellCollar: "Bell"
        case .fairyWings: "Wings"
        case .backpack: "Backpack"
        }
    }

    var emoji: String {
        switch self {
        case .partyHat: "🥳"
        case .crown: "👑"
        case .topHat: "🎩"
        case .cowboyHat: "🤠"
        case .beanie: "🧶"
        case .cap: "🧢"
        case .wizardHat: "🧙"
        case .pirateHat: "🏴‍☠️"
        case .chefHat: "👨‍🍳"
        case .flowerCrown: "🌼"
        case .vikingHelmet: "🛡️"
        case .propellerCap: "🚁"
        case .flower: "🌸"
        case .sunglasses: "🕶️"
        case .roundGlasses: "👓"
        case .heartGlasses: "❤️"
        case .starGlasses: "⭐️"
        case .goggles: "🥽"
        case .glasses3D: "🎬"
        case .monocle: "🧐"
        case .heroMask: "🦸"
        case .butterflyMask: "🦋"
        case .clownNose: "🔴"
        case .moustache: "🥸"
        case .ninjaWrap: "🥷"
        case .snorkel: "🤿"
        case .bowTie: "🎀"
        case .scarf: "🧣"
        case .cape: "🦹"
        case .flowerNecklace: "💐"
        case .medal: "🏅"
        case .santaHat: "🎅"
        case .strawHat: "👒"
        case .unicornHorn: "🦄"
        case .bunnyEars: "🐰"
        case .hardHat: "👷"
        case .googlyEyes: "👀"
        case .visor: "🤖"
        case .pixelShades: "😎"
        case .catEyeGlasses: "😺"
        case .beard: "🧔"
        case .whiskers: "🐱"
        case .pigSnout: "🐷"
        case .necktie: "👔"
        case .pearls: "📿"
        case .bellCollar: "🔔"
        case .fairyWings: "🧚"
        case .backpack: "🎒"
        }
    }
}

// MARK: - Actions

enum FigureAction: String, CaseIterable, Identifiable, Codable {
    case dance, jump, run, spin, wave

    var id: String { rawValue }

    var name: String {
        switch self {
        case .dance: "Dance"
        case .jump: "Jump"
        case .run: "Run"
        case .spin: "Spin"
        case .wave: "Wave"
        }
    }

    var symbol: String {
        switch self {
        case .dance: "music.note"
        case .jump: "arrow.up"
        case .run: "figure.run"
        case .spin: "arrow.triangle.2.circlepath"
        case .wave: "hand.wave"
        }
    }

    /// Seconds for one full play of the action.
    var duration: Double {
        switch self {
        case .dance: 4.0
        case .jump: 2.4
        case .run: 4.0
        case .spin: 1.6
        case .wave: 2.4
        }
    }
}

// MARK: - State

struct Look: Codable, Equatable {
    var animal: Animal = .bunny
    var skin: Skin = .natural
    var pattern: Pattern = .plain
    /// What is worn, one item per slot (missing slot = nothing there).
    var worn: [WearSlot: Wearable] = [:]

    init() {}

    func wearing(_ slot: WearSlot) -> Wearable? { worn[slot] }

    /// Everything worn, in slot order. A snorkel mask covers the eyes, so glasses hide.
    var visibleWear: [Wearable] {
        WearSlot.allCases.compactMap { slot -> Wearable? in
            if slot == .glasses, worn[.mask] == .snorkel { return nil }
            return worn[slot]
        }
    }

    enum CodingKeys: String, CodingKey { case animal, skin, pattern, worn, accessory }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        animal = (try? c.decode(Animal.self, forKey: .animal)) ?? .bunny
        skin = (try? c.decode(Skin.self, forKey: .skin)) ?? .natural
        pattern = (try? c.decode(Pattern.self, forKey: .pattern)) ?? .plain
        if let list = try? c.decode([Wearable].self, forKey: .worn) {
            for item in list { worn[item.slot] = item }
        } else if let old = try? c.decode(String.self, forKey: .accessory),
                  let item = Wearable(rawValue: old) {
            worn[item.slot] = item          // saved by the older one-extra version
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(animal, forKey: .animal)
        try c.encode(skin, forKey: .skin)
        try c.encode(pattern, forKey: .pattern)
        try c.encode(WearSlot.allCases.compactMap { worn[$0] }, forKey: .worn)
    }
}

/// A request to turn the figure in the room by an angle (radians, about +y).
struct TurnRequest: Equatable {
    let id = UUID()
    let angle: Float
}

struct ActionRequest: Equatable {
    let id = UUID()
    /// nil means "stop and stand still".
    let action: FigureAction?
}

@MainActor
final class ShelfState: ObservableObject {
    @Published private(set) var look: Look {
        didSet { save() }
    }
    @Published private(set) var history: [Look] = []
    @Published private(set) var actionRequest: ActionRequest?
    @Published private(set) var turnRequest: TurnRequest?

    func turn(by angle: Float) { turnRequest = TurnRequest(angle: angle) }
    @Published var keepGoing = false
    @Published var showingRoom = false

    private let storageKey: String

    /// Figure Worlds keeps two of these (the player's animal and the friend), each saved under its own key.
    init(storageKey: String = "figureShelf.look", defaultLook: Look = Look()) {
        self.storageKey = storageKey
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Look.self, from: data) {
            look = saved
        } else {
            look = defaultLook
        }
    }

    var canUndo: Bool { !history.isEmpty }

    func choose(animal: Animal) { change(sound: .plop) { $0.animal = animal } }
    func choose(skin: Skin) { change(sound: .wisp) { $0.skin = skin } }
    func choose(pattern: Pattern) { change(sound: .wisp) { $0.pattern = pattern } }
    /// Tapping a worn item again takes it off.
    func toggle(_ item: Wearable) {
        change(sound: .wisp) { $0.worn[item.slot] = $0.worn[item.slot] == item ? nil : item }
    }
    func takeOff(_ slot: WearSlot) { change(sound: .wisp) { $0.worn[slot] = nil } }

    /// Changes the shelf view's turning angle back to the default (StageView watches it).
    @Published private(set) var resetViewID = UUID()
    /// True after the figure was turned by dragging on the shelf.
    @Published var viewTurned = false

    /// Nothing worn, Normal color, default angle: the Reset button has nothing to do.
    var isDefault: Bool { look.skin == .natural && look.pattern == .plain && look.worn.isEmpty && !viewTurned }

    /// Reset: take everything off, Normal color, stop moving, turn back to the default
    /// angle. Keeps the chosen animal. One undo step brings the look back.
    func reset() {
        let wasDefaultLook = look.skin == .natural && look.pattern == .plain && look.worn.isEmpty
        change(sound: .whisk) { $0.skin = .natural; $0.pattern = .plain; $0.worn = [:] }
        if wasDefaultLook { SoundBoard.shared.ui(.whisk) }   // change() plays only when the look changed
        stop()
        viewTurned = false
        resetViewID = UUID()
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        SoundBoard.shared.ui(.whisk)
        look = previous
    }

    func play(_ action: FigureAction) {
        actionRequest = ActionRequest(action: action)
    }

    func stop() {
        keepGoing = false
        actionRequest = ActionRequest(action: nil)
    }

    private func change(sound: SoundBoard.UISound? = nil, _ edit: (inout Look) -> Void) {
        var next = look
        edit(&next)
        guard next != look else { return }
        if let sound { SoundBoard.shared.ui(sound) } else { SoundBoard.shared.pop() }
        history.append(look)
        if history.count > 50 { history.removeFirst() }
        look = next
    }

    private func save() {
        if let data = try? JSONEncoder().encode(look) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
