@testable import AppUI
import XCTest

final class CaptureStopDecisionTests: XCTestCase {
    /// Push-to-talk release is the one case a trailing word can still be in flight, so it
    /// alone earns the grace window.
    func testHoldReleaseFinalizesAfterGrace() {
        XCTAssertEqual(
            CaptureStopDecision.decide(hasActiveCapture: true, isFinishing: false, isHoldRelease: true),
            .finalizeAfterGrace
        )
    }

    /// Deliberate (manual, toggle) and forced (sleep, safety timeout) stops finalize at once:
    /// the grace window would only add latency, and lingering past a sleep-driven stop keeps
    /// the mic live exactly when it must not be.
    func testNonHoldStopFinalizesImmediately() {
        XCTAssertEqual(
            CaptureStopDecision.decide(hasActiveCapture: true, isFinishing: false, isHoldRelease: false),
            .finalizeNow
        )
    }

    /// A stop with nothing recording is a no-op.
    func testNoActiveCaptureIsIgnored() {
        XCTAssertEqual(
            CaptureStopDecision.decide(hasActiveCapture: false, isFinishing: false, isHoldRelease: true),
            .ignore
        )
    }

    /// A second stop that arrives while the grace window is already finalizing must not
    /// schedule another finalize.
    func testStopWhileFinishingIsIgnored() {
        XCTAssertEqual(
            CaptureStopDecision.decide(hasActiveCapture: true, isFinishing: true, isHoldRelease: true),
            .ignore
        )
        XCTAssertEqual(
            CaptureStopDecision.decide(hasActiveCapture: true, isFinishing: true, isHoldRelease: false),
            .ignore
        )
    }

    /// A new capture may start only from a fully idle state.
    func testCanBeginOnlyWhenIdle() {
        XCTAssertTrue(CaptureStopDecision.canBeginCapture(hasActiveCapture: false, isFinishing: false))
    }

    /// Starting again while recording, or while the grace window is finalizing the previous
    /// take, would race the in-flight recorder teardown.
    func testCannotBeginWhileActiveOrFinishing() {
        XCTAssertFalse(CaptureStopDecision.canBeginCapture(hasActiveCapture: true, isFinishing: false))
        XCTAssertFalse(CaptureStopDecision.canBeginCapture(hasActiveCapture: false, isFinishing: true))
        XCTAssertFalse(CaptureStopDecision.canBeginCapture(hasActiveCapture: true, isFinishing: true))
    }
}
