@testable import AudioCapture
import Foundation
import XCTest

/// Focused seam tests for the finish → analysis wall-time handoff.
///
/// `AudioCaptureService` retains only the wall duration keyed by capture URL between the
/// synchronous `finishCapture()` and the detached `analyzeCaptureFile(at:)`; the full
/// `recordCapture`/`recordRejection` logging policy is covered separately.
final class AudioCaptureDiagnosticsLifecycleTests: XCTestCase {
    override func tearDown() {
        unsetenv("SCRAWL_CAPTURE_DIAGNOSTICS")
        super.tearDown()
    }

    func testFinishedCaptureWallTimeIsAvailableExactlyOnce() {
        setenv("SCRAWL_CAPTURE_DIAGNOSTICS", "1", 1)
        let service = AudioCaptureService()
        let url = URL(fileURLWithPath: "/tmp/capture-once.wav")

        service.storeDiagnosticWallSecondsIfEnabled(3.25, for: url)

        XCTAssertEqual(service.takeDiagnosticWallSeconds(for: url), 3.25)
        XCTAssertNil(service.takeDiagnosticWallSeconds(for: url))
    }

    func testDisabledDiagnosticsDoNotRetainFinishedCaptureMetadata() {
        unsetenv("SCRAWL_CAPTURE_DIAGNOSTICS")
        let service = AudioCaptureService()
        let url = URL(fileURLWithPath: "/tmp/capture-disabled.wav")

        service.storeDiagnosticWallSecondsIfEnabled(3.25, for: url)

        XCTAssertNil(service.takeDiagnosticWallSeconds(for: url))
    }
}
