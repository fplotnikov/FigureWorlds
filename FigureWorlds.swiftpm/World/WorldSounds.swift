import AVFoundation

/// Soft sounds for things in the world (bell, splash, door click...). They are made in code
/// when the app starts, so there are no sound files. They only play after a tap, and the
/// speaker button turns them off together with the Figure Shelf action sounds.
final class WorldSounds {
    static let shared = WorldSounds()

    enum Sound: CaseIterable {
        case ding, splash, boing, click, whoosh, thud, quack, ribbit, beep
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private init() {
        _ = SoundBoard.shared   // sets up the calm "ambient" audio session
        for _ in 0..<4 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        for sound in Sound.allCases {
            buffers[sound] = Self.make(sound, format: format)
        }
        try? engine.start()
    }

    func play(_ sound: Sound, volume: Float = 0.7) {
        guard SoundBoard.shared.enabled, let buffer = buffers[sound] else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let node = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        node.volume = volume
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        node.play()
    }

    // MARK: - Making the sounds

    private static func make(_ sound: Sound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var seed: UInt32 = 12345
        var low: Double = 0
        func noise() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed >> 8) / Double(1 << 23) - 1
        }
        let twoPi = 2 * Double.pi

        switch sound {
        case .ding:
            return render(1.4, format) { t in
                let env = exp(-t * 3.2) * min(1, t / 0.004)
                let tone = sin(twoPi * 1046 * t) + 0.4 * sin(twoPi * 2093 * t) + 0.15 * sin(twoPi * 3136 * t)
                return 0.22 * env * tone
            }
        case .splash:
            return render(0.7, format) { t in
                low += (noise() - low) * 0.18
                let env = min(1, t / 0.01) * exp(-t * 5.5)
                return 0.5 * env * low
            }
        case .boing:
            return render(0.5, format) { t in
                let f = 220 + 300 * (1 - exp(-t * 9)) + 18 * sin(twoPi * 9 * t)
                let env = min(1, t / 0.005) * exp(-t * 5)
                return 0.28 * env * sin(twoPi * f * t)
            }
        case .click:
            return render(0.08, format) { t in
                let env = min(1, t / 0.002) * exp(-t * 70)
                return 0.3 * env * sin(twoPi * 1800 * t)
            }
        case .whoosh:
            return render(0.8, format) { t in
                low += (noise() - low) * 0.06
                let env = sin(Double.pi * min(1, t / 0.8))
                return 0.6 * env * env * low
            }
        case .quack:
            return render(0.32, format) { t in
                // A soft nasal "quack": a buzzy tone that bends down.
                let f = 520 - 260 * t
                let saw = (t * f).truncatingRemainder(dividingBy: 1) * 2 - 1
                let env = min(1, t / 0.01) * exp(-t * 7)
                return 0.16 * env * (saw * 0.6 + sin(twoPi * f * 2 * t) * 0.4)
            }
        case .ribbit:
            return render(0.36, format) { t in
                // Two quick low croaks.
                let gate: Double = (t < 0.12 || (t > 0.18 && t < 0.3)) ? 1 : 0
                let pulse = sin(twoPi * 32 * t) > 0 ? 1.0 : 0.3
                return 0.22 * gate * pulse * sin(twoPi * (180 + 40 * sin(twoPi * 4 * t)) * t)
            }
        case .thud:
            return render(0.25, format) { t in
                let env = min(1, t / 0.003) * exp(-t * 18)
                return 0.45 * env * sin(twoPi * (95 - 30 * t) * t)
            }
        case .beep:
            return render(0.42, format) { t in
                // A soft robot "boo-bip": two gentle tones.
                let first = t < 0.16
                let local = first ? t : t - 0.2
                guard local >= 0 else { return 0 }
                let env = min(1, local / 0.01) * exp(-local * 9)
                let f: Double = first ? 523 : 784
                return 0.18 * env * sin(twoPi * f * local)
            }
        }
    }

    private static func render(_ seconds: Double, _ format: AVAudioFormat, _ sample: (Double) -> Double) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(seconds * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            data[i] = Float(sample(Double(i) / rate))
        }
        return buffer
    }
}
