@testable import RecordingOverlay
import XCTest

final class WaveformLevelTests: XCTestCase {
    func testNormalizedLevelClampsTheSpeechWindow() {
        XCTAssertEqual(WaveformLevel.normalizedLevel(fromDecibels: nil), 0)
        XCTAssertEqual(WaveformLevel.normalizedLevel(fromDecibels: -160), 0)
        XCTAssertEqual(WaveformLevel.normalizedLevel(fromDecibels: -50), 0)
        // Anything at or above the loud ceiling saturates the bars.
        XCTAssertEqual(WaveformLevel.normalizedLevel(fromDecibels: -10), 1, accuracy: 0.001)
        XCTAssertEqual(WaveformLevel.normalizedLevel(fromDecibels: 0), 1, accuracy: 0.001)
        XCTAssertEqual(WaveformLevel.normalizedLevel(fromDecibels: 10), 1, accuracy: 0.001)
    }

    func testMidSpeechDrivesBarsPastTheMutedMiddle() {
        // -30 dB is the middle of the speech window; the expansion curve lifts it well
        // past the 0.5 a linear map would give, so ordinary talking reads as dramatic.
        let level = WaveformLevel.normalizedLevel(fromDecibels: -30)
        XCTAssertEqual(level, 0.637, accuracy: 0.01)
        XCTAssertGreaterThan(level, 0.6)
    }

    func testSilenceSettlesToTheFloor() {
        var heights = Array(repeating: WaveformLevel.maxBarHeight, count: WaveformLevel.barCount)
        for _ in 0 ..< 30 {
            heights = WaveformLevel.nextBarHeights(level: 0, previous: heights)
        }
        for height in heights {
            XCTAssertEqual(height, WaveformLevel.minBarHeight, accuracy: 0.05)
        }
    }

    func testFullLevelConvergesToDampedNeighborTargets() {
        var heights = Array(repeating: WaveformLevel.minBarHeight, count: WaveformLevel.barCount)
        for _ in 0 ..< 30 {
            heights = WaveformLevel.nextBarHeights(level: 1, previous: heights)
        }
        let range = WaveformLevel.maxBarHeight - WaveformLevel.minBarHeight
        for (height, fraction) in zip(heights, WaveformLevel.barFractions) {
            XCTAssertEqual(height, WaveformLevel.minBarHeight + range * fraction, accuracy: 0.05)
        }
    }

    func testBarsAreSymmetricAroundTheCenter() {
        var heights = Array(repeating: WaveformLevel.minBarHeight, count: WaveformLevel.barCount)
        for level in [0.3, 0.9, 0.1] as [CGFloat] {
            heights = WaveformLevel.nextBarHeights(level: level, previous: heights)
        }
        XCTAssertEqual(heights[0], heights[4], accuracy: 0.001)
        XCTAssertEqual(heights[1], heights[3], accuracy: 0.001)
    }

    func testWrongSizedPreviousIsTreatedAsFloorAndLevelIsClamped() {
        let heights = WaveformLevel.nextBarHeights(level: 5, previous: [])
        XCTAssertEqual(heights.count, WaveformLevel.barCount)
        for height in heights {
            XCTAssertGreaterThanOrEqual(height, WaveformLevel.minBarHeight)
            XCTAssertLessThanOrEqual(height, WaveformLevel.maxBarHeight)
        }
    }
}
