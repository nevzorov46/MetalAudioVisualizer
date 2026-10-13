import Accelerate
import AVFAudio

/// Turns a stream of audio buffers into frames of log-spaced frequency bands in `0...1`.
///
/// Not isolated to the main actor: each instance is owned by one background
/// analysis task and only ever touched from it.
nonisolated final class SpectrumAnalyzer {
    let bandCount: Int
    /// Samples between two consecutive frames.
    let hopSize: Int

    private let fftSize: Int
    private let dft: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    private let zeros: [Float]

    /// Fractional FFT bin at each band boundary (`bandCount + 1` values).
    private let bandEdges: [Float]
    /// Per-band correction in dB that lifts the naturally quieter high frequencies.
    private let bandTilt: [Float]

    private var mono: [Float] = []
    private var history: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var magnitudes: [Float]

    init(sampleRate: Double,
         fftSize: Int = Constants.fftSize,
         bandCount: Int = Constants.bandCount) throws {
        dft = try vDSP.DiscreteFourierTransform(count: fftSize,
                                                direction: .forward,
                                                transformType: .complexComplex,
                                                ofType: Float.self)
        self.fftSize = fftSize
        self.hopSize = fftSize / 2
        self.bandCount = bandCount

        window = vDSP.window(ofType: Float.self,
                             usingSequence: .hanningDenormalized,
                             count: fftSize,
                             isHalfWindow: false)
        zeros = [Float](repeating: 0, count: fftSize)
        history = zeros
        windowed = zeros
        real = zeros
        imaginary = zeros
        magnitudes = [Float](repeating: 0, count: fftSize / 2)

        // Bands are spaced evenly in log-frequency, which is how pitch is perceived.
        let binWidth = Float(sampleRate) / Float(fftSize)
        let octaves = log2(Constants.maxFrequency / Constants.minFrequency)
        let frequencies = (0...bandCount).map { index in
            Constants.minFrequency * pow(2, octaves * Float(index) / Float(bandCount))
        }
        bandEdges = frequencies.map { $0 / binWidth }
        bandTilt = (0..<bandCount).map { band in
            let center = (frequencies[band] * frequencies[band + 1]).squareRoot()
            return Constants.spectrumTilt * log2(center / 1_000)
        }
    }

    /// Analyzes `buffer` hop by hop, appending one frame of `bandCount` levels per hop.
    /// Frame `n` describes the audio centered on sample `n * hopSize` of the stream.
    func analyze(_ buffer: AVAudioPCMBuffer, appendingTo frames: inout [Float]) {
        let count = Int(buffer.frameLength)
        guard let channels = buffer.floatChannelData, count > 0 else { return }

        let left = UnsafeBufferPointer(start: channels[0], count: count)
        guard buffer.format.channelCount > 1 else {
            analyze(left, appendingTo: &frames)
            return
        }

        // Mix stereo down to mono so panned instruments are not missed.
        let right = UnsafeBufferPointer(start: channels[1], count: count)
        if mono.count != count {
            mono = [Float](repeating: 0, count: count)
        }
        vDSP.add(multiplication: (a: left, b: 0.5),
                 multiplication: (c: right, d: 0.5),
                 result: &mono)
        mono.withUnsafeBufferPointer { analyze($0, appendingTo: &frames) }
    }

    private func analyze(_ samples: UnsafeBufferPointer<Float>, appendingTo frames: inout [Float]) {
        guard let base = samples.baseAddress else { return }

        for offset in stride(from: 0, to: samples.count, by: hopSize) {
            append(base + offset, count: min(hopSize, samples.count - offset))
            transform()
            appendBands(to: &frames)
        }
    }

    /// Slides the analysis window forward by `count` samples.
    private func append(_ samples: UnsafePointer<Float>, count: Int) {
        let kept = fftSize - count
        history.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            base.update(from: base + count, count: kept)
            (base + kept).update(from: samples, count: count)
        }
    }

    private func transform() {
        vDSP.multiply(history, window, result: &windowed)
        dft.transform(inputReal: windowed,
                      inputImaginary: zeros,
                      outputReal: &real,
                      outputImaginary: &imaginary)

        let half = fftSize / 2
        vDSP.hypot(real[..<half], imaginary[..<half], result: &magnitudes)
    }

    private func appendBands(to frames: inout [Float]) {
        // A full-scale sine through a Hann window peaks at `fftSize / 4`.
        let fullScale = Float(fftSize) / 4
        let range = Constants.spectrumCeiling - Constants.spectrumFloor

        for band in 0..<bandCount {
            let decibels = 20 * log10(max(peak(in: band) / fullScale, 1e-9)) + bandTilt[band]
            let level = min(max((decibels - Constants.spectrumFloor) / range, 0), 1)
            frames.append(pow(level, Constants.spectrumContrast))
        }
    }

    /// Strongest magnitude inside a band. Low bands are narrower than one FFT bin,
    /// so the spectrum is also sampled between bins to keep them distinct.
    private func peak(in band: Int) -> Float {
        let lower = bandEdges[band]
        let upper = bandEdges[band + 1]
        var value = interpolatedMagnitude(at: (lower + upper) / 2)

        let first = Int(lower.rounded(.up))
        let last = min(Int(upper.rounded(.down)), magnitudes.count - 1)
        if first <= last {
            value = max(value, vDSP.maximum(magnitudes[first...last]))
        }
        return value
    }

    private func interpolatedMagnitude(at bin: Float) -> Float {
        let index = min(Int(bin), magnitudes.count - 2)
        let fraction = bin - Float(index)
        return magnitudes[index] + (magnitudes[index + 1] - magnitudes[index]) * fraction
    }
}
