import AVFoundation

/// Soft, original action sounds (Resources/Sounds, made by models/make_sounds.py).
/// Sounds only ever start from a tap: an action, "Again" repeating that action, or picking
/// an animal, colour or extra. Uses the ambient category, so the silent switch mutes them
/// and other audio keeps playing. The speaker button turns them off (remembered).
final class SoundBoard {
    static let shared = SoundBoard()
    static let storageKey = "figureShelf.sound"

    private var players: [String: AVAudioPlayer] = [:]
    private var current: AVAudioPlayer?

    /// Figure Worlds: the place the animal is in. Dancing plays that place's own little tune
    /// (sfx_dance_<place>.m4a, made by tools/make_dance_music.py).
    var danceTheme: String?

    var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.storageKey) as? Bool ?? true
    }

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let vehicles = ["car", "truck", "bike", "snow", "digger", "jet", "plane", "heli", "boat",
                        "train", "sub", "tractor", "bus", "forklift", "cable", "rover", "airship"].map { "run_" + $0 }
        let servos = ["dance", "jump", "run", "wave", "spin"].map { "anim_" + $0 }
        let dinos = ["dance", "jump", "run", "wave", "fly"].map { "dino_" + $0 }
        let places = ["village", "pond", "snow", "workshop", "carnival"].map { "dance_" + $0 }   // Figure Worlds
        for name in ["dance", "jump", "run", "spin", "wave", "pop"] + vehicles + servos + dinos + places {
            guard let url = Bundle.main.url(forResource: "sfx_" + name, withExtension: "m4a"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[name] = player
        }
    }

    /// Starts the sound for an action from the beginning (nil just fades out what plays).
    /// `vehicle`: robots run as a vehicle, with its own soft engine sound.
    /// `animatronic`: servo clicks (and a calliope for dance) instead of the soft sounds.
    /// `dinosaur`: a soft "rawr" for dance and wave, padded footsteps for run;
    /// `flyer` (Pteranodon) whooshes its wings on run instead.
    func play(_ action: FigureAction?, vehicle: String? = nil, animatronic: Bool = false,
              dinosaur: Bool = false, flyer: Bool = false) {
        fadeOutCurrent()
        guard enabled, let action else { return }
        var name = action == .run && vehicle != nil ? "run_" + vehicle!
            : (animatronic ? "anim_" + action.rawValue : action.rawValue)
        if dinosaur {
            name = action == .run && flyer ? "dino_fly" : "dino_" + action.rawValue
            if players[name] == nil { name = action.rawValue }   // spin keeps the usual whoosh
        }
        // Figure Worlds: each place has its own dance tune.
        if action == .dance, !animatronic, !dinosaur, let theme = danceTheme, players["dance_" + theme] != nil {
            name = "dance_" + theme
        }
        guard let player = players[name] else { return }
        player.currentTime = 0
        player.volume = 0
        player.play()
        player.setVolume(0.8, fadeDuration: 0.08)
        current = player
    }

    /// A very quiet pop when something is chosen.
    func pop() {
        guard enabled, let player = players["pop"] else { return }
        player.currentTime = 0
        player.volume = 0.35
        player.play()
    }

    /// Gentle interface sounds rendered from Bencho's free (MIT) recipes, see
    /// Resources/Sounds/BENCHO-LICENSE.txt and make_bencho_sounds.py. Only positive, soft sounds:
    /// nothing here means "no" or "wrong".
    enum UISound: String, CaseIterable {
        case plop, wisp, whisk, drape, glide, landed, perk, tick, step, hail, float, latch, drift
    }
    private lazy var uiPlayers: [UISound: AVAudioPlayer] = {
        var all: [UISound: AVAudioPlayer] = [:]
        for sound in UISound.allCases {
            guard let url = Bundle.main.url(forResource: "bencho_" + sound.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            all[sound] = player
        }
        return all
    }()

    /// Plays a short interface sound (after a tap) on top of whatever action sound plays.
    func ui(_ sound: UISound, volume: Float = 0.45) {
        guard enabled, let player = uiPlayers[sound] else { return }
        player.currentTime = 0
        player.volume = volume
        player.play()
    }

    /// Called when the speaker button turns sounds off.
    func stopAll() {
        fadeOutCurrent()
    }

    private func fadeOutCurrent() {
        guard let old = current else { return }
        current = nil
        old.setVolume(0, fadeDuration: 0.15)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { [weak self] in
            if self?.current !== old { old.stop() }
        }
    }
}
