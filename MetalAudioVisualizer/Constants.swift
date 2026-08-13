import Foundation

/// Tunable parameters for audio analysis and rendering.
enum Constants {
    static let defaultAudioLevel: Float = 0

    // Per-stem gain applied to the measured RMS level.
    static let vocalGain: Float = 2.0
    static let bassGain: Float = 1.0
    static let drumsGain: Float = 1.5
    static let otherInstrumentsGain: Float = 1.0

    /// Scales raw RMS into the 0...1 range the shader expects.
    static let rmsScale: Float = 3.0

    /// Delay before playback so all stems can be scheduled first (nanoseconds).
    static let startTimeDelay: UInt64 = 100_000_000

    static let preferredFramesPerSecond = 60
    static let extensionFormat = "m4a"

    static let numberOfSpikes = 120
    static let halfWidth: Float = 0.007
}
