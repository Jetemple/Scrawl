import AppKit
import XCTest

@testable import RecordingOverlay

final class PillWidthTests: XCTestCase {
    // The clamp boundaries
    private let minWidth = RecordingOverlayController.minPillWidth   // 148
    private let maxWidth = RecordingOverlayController.maxPillWidth   // 420
    private let font = NSFont.systemFont(ofSize: 12, weight: .medium)

    // MARK: - Clamp tests using injected measured width

    /// Helper that bypasses NSFont measurement so tests are deterministic in
    /// headless CI.  Computes the same formula as the production function but
    /// uses a caller-supplied measuredWidth instead.
    private func clampedWidth(measuredText: CGFloat, leadingAccessoryWidth: CGFloat) -> CGFloat {
        let padding: CGFloat = 14
        let required = padding + leadingAccessoryWidth + measuredText + padding
        return min(max(required, minWidth), maxWidth)
    }

    func testShortTextClampsToMin() {
        // A very short measured text (e.g., 10 pt) should still produce minPillWidth.
        let result = clampedWidth(measuredText: 10, leadingAccessoryWidth: 0)
        XCTAssertEqual(result, minWidth)
    }

    func testLongTextClampsToMax() {
        // A very long measured text (e.g., 600 pt) should clamp to maxPillWidth.
        let result = clampedWidth(measuredText: 600, leadingAccessoryWidth: 0)
        XCTAssertEqual(result, maxWidth)
    }

    func testMediumTextFitsExactly() {
        // measured=100, no accessory → 14+0+100+14 = 128, which is < 148 → clamps to min.
        let result = clampedWidth(measuredText: 100, leadingAccessoryWidth: 0)
        XCTAssertEqual(result, minWidth)
    }

    func testMediumTextWithAccessoryExceedsMin() {
        // measured=130, accessory=23 → 14+23+130+14 = 181, above min.
        let result = clampedWidth(measuredText: 130, leadingAccessoryWidth: 23)
        XCTAssertEqual(result, 181)
    }

    func testBoundaryExactlyAtMin() {
        // required == minWidth exactly should produce minWidth.
        // 14 + 0 + 120 + 14 = 148
        let result = clampedWidth(measuredText: 120, leadingAccessoryWidth: 0)
        XCTAssertEqual(result, minWidth)
    }

    func testBoundaryExactlyAtMax() {
        // required == maxWidth exactly should produce maxWidth.
        // 14 + 0 + 392 + 14 = 420
        let result = clampedWidth(measuredText: 392, leadingAccessoryWidth: 0)
        XCTAssertEqual(result, maxWidth)
    }

    func testJustAboveMin() {
        // 14 + 0 + 121 + 14 = 149 → just above min, not clamped.
        let result = clampedWidth(measuredText: 121, leadingAccessoryWidth: 0)
        XCTAssertEqual(result, 149)
    }

    func testJustBelowMax() {
        // 14 + 0 + 391 + 14 = 419 → just below max, not clamped.
        let result = clampedWidth(measuredText: 391, leadingAccessoryWidth: 0)
        XCTAssertEqual(result, 419)
    }

    // MARK: - Static function smoke test with real NSFont

    func testPillWidthFunctionReturnsAtLeastMin() {
        // Even an empty string should return at least minPillWidth.
        let result = RecordingOverlayController.pillWidth(
            forText: "",
            font: font,
            leadingAccessoryWidth: 0
        )
        XCTAssertGreaterThanOrEqual(result, minWidth)
    }

    func testPillWidthFunctionReturnsAtMostMax() {
        // An absurdly long string should be capped at maxPillWidth.
        let longText = String(repeating: "W", count: 500)
        let result = RecordingOverlayController.pillWidth(
            forText: longText,
            font: font,
            leadingAccessoryWidth: 0
        )
        XCTAssertLessThanOrEqual(result, maxWidth)
    }

    func testPillWidthGrowsForLongerText() {
        let shortResult = RecordingOverlayController.pillWidth(
            forText: "OK",
            font: font,
            leadingAccessoryWidth: 0
        )
        let longResult = RecordingOverlayController.pillWidth(
            forText: "That key types text — choose a modifier, Fn, or a function key.",
            font: font,
            leadingAccessoryWidth: 0
        )
        // The longer string's required width exceeds minPillWidth, so it must be larger.
        XCTAssertGreaterThan(longResult, shortResult)
    }

    func testPillWidthLeadingAccessoryIncreasesWidth() {
        let withoutAccessory = RecordingOverlayController.pillWidth(
            forText: "Recording",
            font: font,
            leadingAccessoryWidth: 0
        )
        let withAccessory = RecordingOverlayController.pillWidth(
            forText: "Recording",
            font: font,
            leadingAccessoryWidth: 16   // dot(8)+gap(8)
        )
        // With an accessory the required total is larger; both may be at min, or withAccessory > withoutAccessory.
        XCTAssertGreaterThanOrEqual(withAccessory, withoutAccessory)
    }
}
