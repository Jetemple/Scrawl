@testable import AppUI
import AppKit
import XCTest

final class PreferencesModelsViewTests: XCTestCase {
    // Regression: the per-row status label used a fixed 72pt width, which clipped
    // "Download cancelled" down to "Download can…". The status label must be wide
    // enough to render its longest status string without truncation.
    @MainActor
    func testCancelledStatusLabelIsNotTruncated() throws {
        let view = PreferencesModelsView(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            cancelDownload: {}
        )
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 320)

        let row = PreferencesModelRow(
            id: "ggml-medium",
            displayName: "medium — multilingual, 1.5 GB",
            isInstalled: false,
            isSelected: false,
            isDownloading: false,
            isCancelled: true,
            downloadProgressText: nil
        )
        view.update(rows: [row], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        let statusLabel = try XCTUnwrap(view.firstTextField(withValue: "Download cancelled"))
        XCTAssertGreaterThanOrEqual(
            statusLabel.frame.width.rounded(),
            statusLabel.intrinsicContentSize.width.rounded(),
            "Status label must be wide enough to show 'Download cancelled' without truncation"
        )
    }
}

private extension NSView {
    func firstTextField(withValue value: String) -> NSTextField? {
        if let field = self as? NSTextField, field.stringValue == value {
            return field
        }
        return subviews.lazy.compactMap { $0.firstTextField(withValue: value) }.first
    }
}
