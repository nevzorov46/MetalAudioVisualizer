import AVFoundation
import Combine

/// Plays four isolated stems in sync and knows the spectrum of each one at the
/// exact moment being heard.
///
/// Audio taps deliver data only about ten times a second, which is too coarse
/// to follow a beat. Instead every stem is analyzed ahead of playback into a
/// timeline of spectrum frames, and the renderer reads that timeline at the
/// playhead.
final class AudioAnalyzer: ObservableObject {

    /// The four stems, in the order they are stacked along each ray (core outward).
    /// `Scene.metal` lists the stem colors in this same order.
    nonisolated enum Stem: Int, CaseIterable {
        case other, bass, vocals, drums

        /// Audio file name without its extension (e.g. `vocals`).
        var fileName: String { String(describing: self) }

        var gain: Float {
            switch self {
            case .other:  return Constants.otherInstrumentsGain
            case .bass:   return Constants.bassGain
            case .vocals: return Constants.vocalGain
            case .drums:  return Constants.drumsGain
            }
        }
    }

    /// Number of values in a full spectrum: one set of bands per stem,
    /// laid out as `stem.rawValue * bandCount + band`.
    static let spectrumSize = Stem.allCases.count * Constants.bandCount

    private let engine = AVAudioEngine()
    private var players: [Stem: AVAudioPlayerNode] = [:]

    /// Analyzed frames of each stem, `bandCount` values per frame.
    private var timelines = [[Float]](repeating: [], count: Stem.allCases.count)
    /// Spectrum frames per second of audio.
    private var frameRate: Double = 0

    private var beatDetector = BeatDetector()
    /// Playback positions (seconds) of every drum hit found so far, in order.
    private var beats: [TimeInterval] = []

    // MARK: Playback

    func start(fileExtension ext: String = Constants.extensionFormat) {
        var files: [Stem: AVAudioFile] = [:]

        do {
            for stem in Stem.allCases {
                guard let url = Bundle.main.url(forResource: stem.fileName, withExtension: ext) else {
                    print("Missing audio file for stem: \(stem.fileName).\(ext)")
                    return
                }
                let file = try AVAudioFile(forReading: url)
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)

                files[stem] = file
                players[stem] = player
                analyze(stem, at: url)
            }
            try engine.start()
        } catch {
            print("Audio setup failed: \(error)")
            return
        }

        // Start every stem at one shared host time so they stay sample-aligned.
        let delay = AVAudioTime.hostTime(forSeconds: Constants.startDelay)
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + delay)
        for (stem, file) in files {
            guard let player = players[stem] else { continue }
            player.scheduleFile(file, at: nil)
            player.play(at: startTime)
        }
    }

    /// Position in the track (seconds) that is reaching the listener right now.
    private var playhead: TimeInterval? {
        guard let player = players[.drums],
              let renderTime = player.lastRenderTime,
              renderTime.isHostTimeValid,
              let playerTime = player.playerTime(forNodeTime: renderTime) else { return nil }

        // `lastRenderTime` only advances once per audio buffer, so extrapolate
        // from it with the host clock to get a position that moves smoothly.
        let rendered = Double(playerTime.sampleTime) / playerTime.sampleRate
        let sinceRender = AVAudioTime.seconds(forHostTime: mach_absolute_time())
                        - AVAudioTime.seconds(forHostTime: renderTime.hostTime)

        // Sound leaves the speaker (or AirPods) later than it is rendered.
        return rendered + sinceRender - engine.outputNode.presentationLatency
    }

    // MARK: Reading

    /// Fills `spectrum` with the band levels of every stem at the playhead.
    func read(into spectrum: inout [Float]) {
        let bandCount = Constants.bandCount
        let position = (playhead ?? -1) * frameRate
        let frame = Int(position.rounded(.down))
        let fraction = Float(position - Double(frame))

        for stem in Stem.allCases {
            let timeline = timelines[stem.rawValue]
            let output = stem.rawValue * bandCount
            let current = frame * bandCount
            let next = current + bandCount

            guard frame >= 0, next + bandCount <= timeline.count else {
                for band in 0..<bandCount { spectrum[output + band] = 0 }
                continue
            }
            // Blend the two nearest frames so motion stays smooth at any frame rate.
            for band in 0..<bandCount {
                let level = timeline[current + band] + (timeline[next + band] - timeline[current + band]) * fraction
                spectrum[output + band] = level * stem.gain
            }
        }
    }

    /// Seconds since each of the most recent drum hits, newest first.
    /// Slots without a hit yet hold a large value.
    func beatAges(count: Int) -> [Float] {
        var ages = [Float](repeating: 100, count: count)
        guard let playhead else { return ages }

        let recent = beats.reversed().lazy.filter { $0 <= playhead }.prefix(count)
        for (slot, beat) in recent.enumerated() {
            ages[slot] = Float(min(playhead - beat, 100))
        }
        return ages
    }

    // MARK: Analysis

    /// Analyzes a whole stem in the background. It runs far faster than
    /// playback, so frames are always ready before the playhead reaches them.
    private func analyze(_ stem: Stem, at url: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let file = try AVAudioFile(forReading: url)
                let format = file.processingFormat
                let analyzer = try SpectrumAnalyzer(sampleRate: format.sampleRate)
                let chunkSize = AVAudioFrameCount(analyzer.hopSize * Constants.analysisChunkHops)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else { return }

                let frameRate = format.sampleRate / Double(analyzer.hopSize)
                while file.framePosition < file.length {
                    try file.read(into: buffer)
                    var frames: [Float] = []
                    analyzer.analyze(buffer, appendingTo: &frames)
                    await self?.append(frames, to: stem, frameRate: frameRate)
                }
            } catch {
                print("Analysis of \(stem.fileName) failed: \(error)")
            }
        }
    }

    private func append(_ frames: [Float], to stem: Stem, frameRate: Double) {
        let bandCount = Constants.bandCount
        let firstFrame = timelines[stem.rawValue].count / bandCount
        timelines[stem.rawValue].append(contentsOf: frames)
        self.frameRate = frameRate

        guard stem == .drums else { return }
        for offset in stride(from: 0, to: frames.count, by: bandCount) {
            let time = Double(firstFrame + offset / bandCount) / frameRate
            if beatDetector.process(Array(frames[offset..<offset + bandCount]), at: time) {
                beats.append(time)
            }
        }
    }
}
