import AppKit
@testable import RecordingOverlay
import XCTest

@MainActor
final class RecordingOverlayWaveformTests: XCTestCase {
    func testRecordingLabelStillFitsMinimumPillWithWaveformAccessory() {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let width = RecordingOverlayController.pillWidth(
            forText: "Recording",
            font: font,
            leadingAccessoryWidth: RecordingOverlayController.waveformLeadingAccessoryWidth + 8
        )
        XCTAssertEqual(
            width, RecordingOverlayController.minPillWidth,
            "the wider waveform accessory must not push the Recording pill past its minimum width"
        )
    }

    func testRecordingShowsWaveformAndPollsUntilStateLeaves() {
        let controller = RecordingOverlayController()
        controller.reduceMotionOverride = false
        controller.levelProvider = { -25 }

        controller.setState(.recording)
        XCTAssertTrue(controller.isShowingWaveform)
        XCTAssertTrue(controller.isPollingLevels)

        controller.setState(.transcribing)
        XCTAssertFalse(controller.isShowingWaveform)
        XCTAssertFalse(controller.isPollingLevels)

        controller.setState(.idle)
        XCTAssertFalse(controller.isPollingLevels)
    }

    func testReduceMotionKeepsStaticDotAndNeverPolls() {
        let controller = RecordingOverlayController()
        controller.reduceMotionOverride = true
        controller.levelProvider = { 0 }

        controller.setState(.recording)
        XCTAssertFalse(controller.isShowingWaveform)
        XCTAssertFalse(controller.isPollingLevels)
        XCTAssertTrue(controller.isShowingDot, "Reduce Motion recording shows a static coral dot")
    }

    func testPollTicksDriveBarHeightsFromTheProvider() {
        let controller = RecordingOverlayController()
        controller.reduceMotionOverride = false
        var decibels: Float? = 0
        controller.levelProvider = { decibels }

        controller.setState(.recording)
        for _ in 0..<30 {
            controller.pollLevelOnce()
        }
        XCTAssertEqual(controller.barHeights[2], WaveformLevel.maxBarHeight, accuracy: 0.05)

        decibels = nil
        for _ in 0..<30 {
            controller.pollLevelOnce()
        }
        for height in controller.barHeights {
            XCTAssertEqual(height, WaveformLevel.minBarHeight, accuracy: 0.05)
        }
    }

    func testTransientMessageDuringRecordingRestoresWaveformOnDismiss() {
        let controller = RecordingOverlayController()
        controller.reduceMotionOverride = false
        controller.levelProvider = { -20 }

        controller.setState(.recording)
        controller.showTransientMessage("Stop recording before changing the hotkey")
        XCTAssertFalse(controller.isPollingLevels, "a transient message pauses live polling")
        XCTAssertFalse(controller.isShowingWaveform)

        controller.fireTransientDismiss()
        XCTAssertTrue(controller.isShowingWaveform, "dismissing a transient mid-recording restores the waveform")
        XCTAssertTrue(controller.isPollingLevels)
    }
}
