@testable import AppUI
import XCTest

final class CaptureStopDecisionTests: XCTestCase {
    /// Push-to-talk release is the one case a trailing word can still be in flight, so it
    /// alone earns the grace window.
    func testHoldReleaseFinalizesAfterGrace() {
        XCTAssertEqual(
            CaptureStopDecision.decide(
                hasActiveCapture: true, isFinishing: false, isHoldRelease: true, isForced: false
            ),
            .finalizeAfterGrace
        )
    }

    /// Deliberate (manual, toggle) and forced (sleep, safety timeout) stops finalize at once:
    /// the grace window would only add latency, and lingering past a sleep-driven stop keeps
    /// the mic live exactly when it must not be.
    func testNonHoldStopFinalizesImmediately() {
        XCTAssertEqual(
            CaptureStopDecision.decide(
                hasActiveCapture: true, isFinishing: false, isHoldRelease: false, isForced: false
            ),
            .finalizeNow
        )
    }

    /// A forced stop of a hold recording (sleep or safety timeout while the key is still down)
    /// is not a key release, so it finalizes now rather than opening a grace window that would
    /// hold the mic past the moment it must close.
    func testForcedStopOfHoldRecordingFinalizesImmediately() {
        XCTAssertEqual(
            CaptureStopDecision.decide(
                hasActiveCapture: true, isFinishing: false, isHoldRelease: false, isForced: true
            ),
            .finalizeNow
        )
    }

    /// A stop with nothing recording is a no-op.
    func testNoActiveCaptureIsIgnored() {
        XCTAssertEqual(
            CaptureStopDecision.decide(
                hasActiveCapture: false, isFinishing: false, isHoldRelease: true, isForced: false
            ),
            .ignore
        )
    }

    /// A second deliberate stop that arrives while the grace window is already finalizing must
    /// not schedule another finalize.
    func testStopWhileFinishingIsIgnored() {
        XCTAssertEqual(
            CaptureStopDecision.decide(
                hasActiveCapture: true, isFinishing: true, isHoldRelease: true, isForced: false
            ),
            .ignore
        )
        XCTAssertEqual(
            CaptureStopDecision.decide(
                hasActiveCapture: true, isFinishing: true, isHoldRelease: false, isForced: false
            ),
            .ignore
        )
    }

    /// A forced stop that lands *inside* the grace window preempts it: the sleep/timeout must
    /// finalize now rather than be swallowed, or the mic would stay live into sleep — the exact
    /// case the sleep handler exists to prevent.
    func testForcedStopPreemptsGraceWindow() {
        XCTAssertEqual(
            CaptureStopDecision.decide(
                hasActiveCapture: true, isFinishing: true, isHoldRelease: false, isForced: true
            ),
            .finalizeNow
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
