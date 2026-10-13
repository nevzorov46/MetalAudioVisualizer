import Foundation

/// Detects percussive hits as sudden rises in spectral energy (spectral flux).
nonisolated struct BeatDetector {
    private var previous: [Float] = []
    private var averageFlux: Float = 0
    private var lastBeat: TimeInterval = -.infinity

    /// Returns `true` when `bands` contain a new hit.
    mutating func process(_ bands: [Float], at time: TimeInterval) -> Bool {
        defer { previous = bands }
        guard previous.count == bands.count else { return false }

        // Only energy that appeared since the last frame counts; decays are ignored.
        var flux: Float = 0
        for (current, last) in zip(bands, previous) {
            flux += max(current - last, 0)
        }
        flux /= Float(bands.count)

        let threshold = averageFlux * Constants.beatSensitivity + Constants.beatMinimumFlux
        averageFlux += (flux - averageFlux) * Constants.beatAverageRate

        guard flux > threshold, time - lastBeat > Constants.beatCooldown else { return false }
        lastBeat = time
        return true
    }
}
