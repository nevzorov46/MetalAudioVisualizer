import Foundation

/// Tunable parameters for audio analysis and rendering.
nonisolated enum Constants {

    // MARK: Playback

    static let extensionFormat = "m4a"

    /// Delay before playback so all stems can be scheduled first (seconds).
    static let startDelay: TimeInterval = 0.1

    // MARK: Spectrum analysis

    /// Samples per FFT. Frames are produced every half window (about 23 ms at 44.1 kHz).
    static let fftSize = 2048

    /// Frames analyzed between two hand-offs to the main thread.
    static let analysisChunkHops = 128

    /// Bands per stem. The ring is mirrored, so it shows twice as many rays.
    static let bandCount = 60

    static let minFrequency: Float = 40
    static let maxFrequency: Float = 16_000

    /// Levels (dBFS) mapped to an empty and a full band.
    static let spectrumFloor: Float = -61
    static let spectrumCeiling: Float = -13

    /// Boost in dB per octave, compensating for music's falling high-end energy.
    static let spectrumTilt: Float = 3

    /// Exponent applied to band levels; above 1 it makes peaks stand out.
    static let spectrumContrast: Float = 1.8

    // Per-stem gain applied to the analyzed band levels.
    static let vocalGain: Float = 1.0
    static let bassGain: Float = 1.0
    static let drumsGain: Float = 1.0
    static let otherInstrumentsGain: Float = 1.0

    // MARK: Beat detection

    /// How far above its running average the spectral flux must rise to count as a hit.
    static let beatSensitivity: Float = 2.0
    static let beatMinimumFlux: Float = 0.05
    static let beatAverageRate: Float = 0.1
    static let beatCooldown: TimeInterval = 0.22

    // MARK: Rendering

    static let preferredFramesPerSecond = 60

    /// Time constants (seconds) for how fast rays grow and fall back.
    static let attackTime: Float = 0.03
    static let releaseTime: Float = 0.22

    /// Number of half-resolution steps in the bloom chain.
    static let bloomMipCount = 6
    static let bloomIntensity: Float = 0.3

    /// How fast the background dust drifts: at rest, and extra at full loudness.
    static let dustDrift: Float = 0.015
    static let dustBoost: Float = 0.25
}
