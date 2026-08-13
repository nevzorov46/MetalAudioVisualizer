import AVFoundation
import Accelerate
import Combine

/// Plays four isolated stems in sync and publishes a per-stem RMS level.
final class AudioAnalyzer: ObservableObject {

    /// The four stems. `rawValue` is also the audio file name (e.g. `vocals.m4a`).
    enum Stem: String, CaseIterable {
        case vocals, drums, bass, other

        var gain: Float {
            switch self {
            case .vocals: return Constants.vocalGain
            case .drums:  return Constants.drumsGain
            case .bass:   return Constants.bassGain
            case .other:  return Constants.otherInstrumentsGain
            }
        }
    }

    private let engine = AVAudioEngine()
    private var players: [Stem: AVAudioPlayerNode] = [:]

    @Published var vocalsLevel: Float = Constants.defaultAudioLevel
    @Published var drumsLevel: Float = Constants.defaultAudioLevel
    @Published var bassLevel: Float = Constants.defaultAudioLevel
    @Published var otherLevel: Float = Constants.defaultAudioLevel

    func start(fileExtension ext: String = Constants.extensionFormat) {
        var files: [Stem: AVAudioFile] = [:]

        for stem in Stem.allCases {
            guard
                let url = Bundle.main.url(forResource: stem.rawValue, withExtension: ext),
                let file = try? AVAudioFile(forReading: url)
            else {
                print("Missing audio file for stem: \(stem.rawValue).\(ext)")
                return
            }
            files[stem] = file

            let player = AVAudioPlayerNode()
            players[stem] = player
            attach(player, format: file.processingFormat, gain: stem.gain) { [weak self] level in
                self?.setLevel(level, for: stem)
            }
        }

        do {
            try engine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
            return
        }

        // Start every stem at one shared host time so they stay sample-aligned.
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + Constants.startTimeDelay)
        for (stem, file) in files {
            guard let player = players[stem] else { continue }
            player.scheduleFile(file, at: nil)
            player.play(at: startTime)
        }
    }

    private func attach(_ player: AVAudioPlayerNode,
                        format: AVAudioFormat,
                        gain: Float,
                        onLevel: @escaping (Float) -> Void) {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        player.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }

            var rms: Float = 0
            vDSP_rmsqv(channel, 1, &rms, vDSP_Length(buffer.frameLength))

            let level = min(rms * Constants.rmsScale * gain, 1.0)
            DispatchQueue.main.async {
                onLevel(level)
            }
        }
    }

    private func setLevel(_ level: Float, for stem: Stem) {
        switch stem {
        case .vocals: vocalsLevel = level
        case .drums:  drumsLevel = level
        case .bass:   bassLevel = level
        case .other:  otherLevel = level
        }
    }
}
