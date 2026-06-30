import AppKit
@testable import AppUI
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
            cancelDownload: {},
            addModel: {},
            revealModelsFolder: {},
            openModelSource: {}
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

    @MainActor
    func testActionControlsFitWhenCancelDownloadIsVisibleAtMinimumWidth() {
        let view = PreferencesModelsView(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            cancelDownload: {},
            addModel: {},
            revealModelsFolder: {},
            openModelSource: {}
        )
        view.frame = NSRect(x: 0, y: 0, width: 440, height: 320)
        view.update(rows: [
            PreferencesModelRow(
                id: "ggml-small.en",
                displayName: "Small (English)",
                isInstalled: true,
                isSelected: true,
                isDownloading: false,
                isCancelled: false,
                downloadProgressText: nil
            ),
        ], downloadableModels: [], isDownloadInProgress: true)
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.visibleActionControlsWithinBounds)
    }

    @MainActor
    func testSelectedIndicatorUsesCompactActionSlot() throws {
        let view = PreferencesModelsView(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            cancelDownload: {},
            addModel: {},
            revealModelsFolder: {},
            openModelSource: {}
        )
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        view.update(rows: [
            PreferencesModelRow(
                id: "ggml-small.en",
                displayName: "Small (English)",
                isInstalled: true,
                isSelected: true,
                isDownloading: false,
                isCancelled: false,
                downloadProgressText: nil
            ),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(try XCTUnwrap(view.visibleSelectedIndicatorWidth), 28, accuracy: 0.5)
    }

    @MainActor
    func testSelectedRowUsesSameActionColumnWidthAsButtonRows() throws {
        let view = PreferencesModelsView(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            cancelDownload: {},
            addModel: {},
            revealModelsFolder: {},
            openModelSource: {}
        )
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 320)
        view.update(rows: [
            modelRow(id: "parakeet-v3", installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(try XCTUnwrap(view.visibleSelectedActionSlotWidth), 86, accuracy: 0.5)
    }

    @MainActor
    func testInstalledRowActionIsVerticallyCenteredInFullRow() throws {
        let view = PreferencesModelsView(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            cancelDownload: {},
            addModel: {},
            revealModelsFolder: {},
            openModelSource: {}
        )
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 320)
        view.update(rows: [
            modelRow(id: "parakeet-v3", installed: true, selected: false),
            modelRow(id: "ggml-small.en", installed: true, selected: true),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(abs(try XCTUnwrap(view.visibleFirstActionCenterYOffset)), 2.0)
    }

    @MainActor
    func testModelRowsUseNativeContentInsetFromListEdge() throws {
        let view = PreferencesModelsView(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            cancelDownload: {},
            addModel: {},
            revealModelsFolder: {},
            openModelSource: {}
        )
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 320)
        view.update(rows: [
            modelRow(id: "parakeet-v3", installed: true, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(try XCTUnwrap(view.visibleFirstRowTextLeftInset), 18, accuracy: 0.5)
    }

    @MainActor
    func testFooterControlsAlignWithModelRowContent() throws {
        let view = PreferencesModelsView(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            cancelDownload: {},
            addModel: {},
            revealModelsFolder: {},
            openModelSource: {}
        )
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 320)
        view.update(rows: [
            modelRow(id: "parakeet-v3", installed: true, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        let rowTextMinX = try XCTUnwrap(view.visibleFirstRowTextMinX)
        XCTAssertEqual(try XCTUnwrap(view.visibleFooterControlsMinX), rowTextMinX, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(view.visibleFooterHelpMinX), rowTextMinX, accuracy: 0.5)
    }

    @MainActor
    func testFourModelRowsDoNotLeaveLargeEmptyListTail() {
        let view = PreferencesModelsView(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            cancelDownload: {},
            addModel: {},
            revealModelsFolder: {},
            openModelSource: {}
        )
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 360)
        view.update(rows: [
            modelRow(id: "parakeet-v3", installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
            modelRow(id: "ggml-medium", installed: false, selected: false),
            modelRow(id: "ggml-large-v3-turbo", installed: false, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(view.visibleModelListHeight, 228)
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

private func modelRow(id: String, installed: Bool, selected: Bool) -> PreferencesModelRow {
    PreferencesModelRow(
        id: id,
        displayName: PreferencesModelState.displayName(forModelID: id),
        descriptionText: PreferencesModelState.description(forModelID: id),
        isInstalled: installed,
        isSelected: selected,
        isDefault: selected,
        isDownloading: false,
        isCancelled: false,
        downloadProgressText: nil
    )
}
