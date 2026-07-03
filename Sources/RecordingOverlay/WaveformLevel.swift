import Foundation

/// Pure math for the recording pill's live level waveform. Free of AppKit so it
/// stays deterministic and unit-testable.
enum WaveformLevel {
    static let barCount = 5
    /// Silence floor: bars rest here so a quiet mic still reads "live, hearing nothing".
    static let minBarHeight: CGFloat = 3
    static let maxBarHeight: CGFloat = 14
    /// Neighbor damping: the center bar tracks the level fully, outer bars follow at fractions.
    static let barFractions: [CGFloat] = [0.45, 0.75, 1.0, 0.75, 0.45]
    /// Per-tick easing toward the target (0 = frozen, 1 = instant) so silence settles
    /// instead of snapping.
    static let smoothing: CGFloat = 0.45

    /// Maps `AVAudioRecorder.averagePower(forChannel:)` decibels (typically -160...0)
    /// to 0...1, clamped to the -50...0 dB window. nil (not capturing) is silence.
    static func normalizedLevel(fromDecibels decibels: Float?) -> CGFloat {
        guard let decibels else { return 0 }
        let clamped = min(max(CGFloat(decibels), -50), 0)
        return (clamped + 50) / 50
    }

    /// Returns the next five bar heights for `level` given the previous heights.
    /// A `previous` of the wrong size (first tick) is treated as all-floor.
    static func nextBarHeights(level: CGFloat, previous: [CGFloat]) -> [CGFloat] {
        let clampedLevel = min(max(level, 0), 1)
        let base = previous.count == barCount
            ? previous
            : Array(repeating: minBarHeight, count: barCount)
        return zip(base, barFractions).map { current, fraction in
            let target = minBarHeight + (maxBarHeight - minBarHeight) * clampedLevel * fraction
            let next = current + (target - current) * smoothing
            return min(max(next, minBarHeight), maxBarHeight)
        }
    }
}
