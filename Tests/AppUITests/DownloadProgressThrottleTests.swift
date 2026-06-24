@testable import AppUI
import XCTest

final class DownloadProgressThrottleTests: XCTestCase {
    /// A multi-hundred-MB download fires `fractionCompleted` KVO thousands of times. The
    /// throttle must collapse that flood to a bounded number of forwards so progress no
    /// longer hops to the MainActor per buffer write.
    func testCollapsesThousandsOfFiresToBoundedForwards() {
        let throttle = DownloadProgressThrottle(minimumStep: 0.005)
        var forwarded = 0
        // 100_000 monotonically increasing fires across the full 0→1 range.
        for index in 0...100_000 {
            let fraction = Double(index) / 100_000.0
            if throttle.shouldForward(fraction: fraction) {
                forwarded += 1
            }
        }
        // ~1/minimumStep + the initial 0 + the terminal 1.0. Never the input count.
        XCTAssertLessThanOrEqual(forwarded, 205)
        XCTAssertGreaterThanOrEqual(forwarded, 195)
    }

    func testForwardsInitialZeroSoProgressShowsImmediately() {
        let throttle = DownloadProgressThrottle()
        XCTAssertTrue(throttle.shouldForward(fraction: 0.0))
    }

    func testSuppressesSubStepAdvances() {
        let throttle = DownloadProgressThrottle(minimumStep: 0.01)
        XCTAssertTrue(throttle.shouldForward(fraction: 0.0))
        XCTAssertFalse(throttle.shouldForward(fraction: 0.004))
        XCTAssertFalse(throttle.shouldForward(fraction: 0.009))
        XCTAssertTrue(throttle.shouldForward(fraction: 0.011))
    }

    func testTerminalCompletionAlwaysForwardsOnceEvenAfterNearbyUpdate() {
        let throttle = DownloadProgressThrottle(minimumStep: 0.005)
        XCTAssertTrue(throttle.shouldForward(fraction: 0.0))
        XCTAssertTrue(throttle.shouldForward(fraction: 0.997))
        // 1.0 must land so the UI settles on "complete"...
        XCTAssertTrue(throttle.shouldForward(fraction: 1.0))
        // ...but only once; a late duplicate KVO fire at 1.0 is dropped.
        XCTAssertFalse(throttle.shouldForward(fraction: 1.0))
    }

    func testDropsNonFiniteFractions() {
        let throttle = DownloadProgressThrottle()
        XCTAssertFalse(throttle.shouldForward(fraction: .nan))
        XCTAssertFalse(throttle.shouldForward(fraction: .infinity))
    }
}
