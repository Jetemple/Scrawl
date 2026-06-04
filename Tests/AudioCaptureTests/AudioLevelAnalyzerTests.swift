import AudioCapture
import XCTest

final class AudioLevelAnalyzerTests: XCTestCase {
    func testSilentSamplesAreBelowThreshold() {
        XCTAssertTrue(AudioLevelAnalyzer.isLikelySilent(samples: [0, 0, 0, 0], minimumRMS: 0.001))
    }

    func testAudibleSamplesAreAboveThreshold() {
        XCTAssertFalse(AudioLevelAnalyzer.isLikelySilent(samples: [0, 800, -800, 0], minimumRMS: 0.001))
    }
}
