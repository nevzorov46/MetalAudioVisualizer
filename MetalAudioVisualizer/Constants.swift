import Foundation

struct Constants {
    static let defaultAudioLevel: Float = 0
    static let vocalGain: Float = 2.0
    static let bassGain: Float = 1.0
    static let drumsGain: Float = 0.085
    static let otherInstrumentsGain: Float = 1.0
    static let startTimeDelay: UInt64 = 100_000_000
    static let preferredFramesPerSecond = 60
    static let diskScale = 0.25
    static let disSkaleFactor = 0.04
    static let vocalsTrackName = "vocals"
    static let bassTrackName = "bass"
    static let drumsTrackName = "drums"
    static let otherInstrumentsTrackName = "other"
    static let extensionFormat = "m4a"
    static let numberOfSpikes = 120
    static let halfWidth: Float = 0.007
}
