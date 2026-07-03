@testable import AudioCapture
import XCTest

final class AudioCaptureMeteringTests: XCTestCase {
    func testCurrentAveragePowerIsNilWhenNotCapturing() {
        let service = AudioCaptureService()
        XCTAssertNil(service.currentAveragePower())
    }
}
