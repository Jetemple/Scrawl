import AppKit
import XCTest

@testable import RecordingOverlay

final class PillHeightTests: XCTestCase {
    private let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    private let base = RecordingOverlayController.basePillHeight       // 34
    private let lineHeight = RecordingOverlayController.pillLineHeight // 16

    func testShortTextStaysSingleLineBaseHeight() {
        let height = RecordingOverlayController.pillHeight(
            forText: "Recording",
            font: font,
            leadingAccessoryWidth: 0
        )
        XCTAssertEqual(height, base)
    }

    // A message too long for one line (even at maxPillWidth) must grow the pill
    // to a second line rather than truncate.
    func testLongTextWrapsToTwoLines() {
        let height = RecordingOverlayController.pillHeight(
            forText: "Transcription failed — the server returned an unexpected response from huggingface.co",
            font: font,
            leadingAccessoryWidth: 0
        )
        XCTAssertEqual(height, base + lineHeight)
    }

    // Text far longer than two lines must cap at two lines (the last line ellipsizes),
    // never producing a pill taller than the two-line height.
    func testVeryLongTextCapsAtTwoLines() {
        let height = RecordingOverlayController.pillHeight(
            forText: String(repeating: "wrap ", count: 80),
            font: font,
            leadingAccessoryWidth: 0
        )
        XCTAssertEqual(height, base + lineHeight)
    }

    // Regression: real status messages must be allocated enough pill height for every
    // line the actual NSTextField cell lays out (capped at maxPillLines). The bug was a
    // message measuring just under maxPillWidth reporting one line, while the real cell
    // wrapped it to two — clipping the second line. Uses the real cell layout, which is
    // the source of truth the width/height math must agree with.
    func testRealMessagesGetEnoughHeightForEveryRenderedLine() {
        let maxLines = RecordingOverlayController.maxPillLines
        let messages = [
            "No audio was captured. Check your microphone and try again.",
            "No speech was detected. Try again and speak a little longer.",
            "No audio captured. Check your mic.",
            "Recording",
            "Transcribing",
            "Transcription failed — the server returned an unexpected response from huggingface.co"
        ]
        for message in messages {
            let pillWidth = RecordingOverlayController.pillWidth(forText: message, font: font, leadingAccessoryWidth: 0)
            let pillHeight = RecordingOverlayController.pillHeight(forText: message, font: font, leadingAccessoryWidth: 0)
            let labelWidth = pillWidth - 28   // padding*2, no accessory

            let allocatedLines = Int(((pillHeight - base) / lineHeight).rounded()) + 1
            let renderedLines = min(renderedLineCount(message, width: labelWidth), maxLines)

            XCTAssertGreaterThanOrEqual(
                allocatedLines,
                renderedLines,
                "Pill allocates \(allocatedLines) line(s) but the cell renders \(renderedLines) for: \"\(message)\""
            )
        }
    }

    /// True number of lines the real NSTextField cell lays out for `text` at `width`
    /// (uncapped, so the test can compare against the pill's capped allocation).
    private func renderedLineCount(_ text: String, width: CGFloat) -> Int {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        let fitHeight = label.cell?.cellSize(forBounds: NSRect(
            x: 0, y: 0, width: width, height: .greatestFiniteMagnitude
        )).height ?? lineHeight
        return max(1, Int((fitHeight / lineHeight).rounded(.up)))
    }
}
