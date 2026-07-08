import AppKit
@testable import AppUI
import XCTest

final class PreferencesModelsViewTests: XCTestCase {
    @MainActor
    private func makeView() -> PreferencesModelsView {
        PreferencesModelsView(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            cancelDownload: {},
            addModel: {},
            revealModelsFolder: {},
            openModelSource: {}
        )
    }

    @MainActor
    func testModelRowContentLeftAlignsUnderColumnHeaders() throws {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 700, height: 520)
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-medium", installed: false, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        // The section label sits near the left content edge, not pushed to the right by
        // a mis-sized scroll document (regression: rows were centered at ~x=200).
        let installed = try XCTUnwrap(view.firstTextField(withValue: "Installed Models"))
        XCTAssertLessThan(view.convert(installed.bounds, from: installed).minX, 60)
    }

    @MainActor
    func testModelsTableShowsColumnHeadersAndEngine() {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 460)
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.visibleColumnHeaderTitles, ["Model", "Engine", "Status", "Action"])
        XCTAssertNotNil(view.firstTextField(withValue: "Parakeet"))
        XCTAssertNotNil(view.firstTextField(withValue: "Whisper"))
    }

    @MainActor
    func testModelsHaveFilterFieldAndCurrentModelPicker() {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 460)
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.visibleModelSearchFieldCount, 1)
        XCTAssertEqual(view.visibleModelPickerTitle, "Parakeet v3")
    }

    @MainActor
    func testModelsSplitInstalledAndAvailableSectionsWithoutInfoButtons() {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 460)
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
            modelRow(id: "ggml-medium", installed: false, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.visibleInstalledSectionTitle, "Installed Models")
        XCTAssertEqual(view.visibleAvailableSectionTitle, "Available Downloads")
        XCTAssertEqual(view.visibleModelInfoButtonCount, 0)
        XCTAssertNil(view.firstButton(withToolTip: "Model details"))
    }

    @MainActor
    func testSelectedRowKeepsItsActionButton() {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 460)
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.visibleSelectedRowHasAction)
    }

    @MainActor
    func testSelectedModelHighlightDoesNotImplicitlyAnimateDuringResize() throws {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 740, height: 460)
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        let highlightLayer = try XCTUnwrap(firstSelectionPillLayer(in: view))
        for actionKey in ["bounds", "position", "frame", "backgroundColor"] {
            XCTAssertTrue(
                highlightLayer.actions?[actionKey] is NSNull,
                "\(actionKey) should not implicitly animate while the window resizes"
            )
        }
    }

    @MainActor
    func testFilterNarrowsVisibleRows() throws {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 460)
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        XCTAssertNotNil(view.firstTextField(withValue: "Small (English)"))

        let field = try XCTUnwrap(firstSearchField(in: view))
        field.stringValue = "parakeet"
        field.sendAction(field.action, to: field.target)
        view.layoutSubtreeIfNeeded()

        XCTAssertNotNil(view.firstTextField(withValue: "Parakeet v3"))
        XCTAssertNil(view.firstTextField(withValue: "Small (English)"))
    }

    @MainActor
    func testModelsUsePinnedWorkbenchActionBar() {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 460)
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-medium", installed: false, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.usesPinnedActionBar)
    }

    @MainActor
    func testModelsPagePaintsNativeWindowBackground() {
        let view = makeView()

        XCTAssertTrue(view.subviews.first is PreferencesBackgroundView)
    }

    @MainActor
    func testActionControlsFitWhenCancelDownloadIsVisibleAtMinimumWidth() {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 560, height: 400)
        view.update(rows: [
            modelRow(id: "ggml-small.en", installed: true, selected: true),
        ], downloadableModels: [], isDownloadInProgress: true)
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.visibleActionControlsWithinBounds)
    }

    @MainActor
    func testFooterDeleteButtonAlignsWithActionColumnRightEdge() throws {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 460)
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        let rowActionButton = try XCTUnwrap(view.firstButton(titled: "Use"))
        let footerDeleteButton = try XCTUnwrap(view.firstButton(titled: "Delete Selected"))
        let rowActionColumnFrame = try view.convert(
            XCTUnwrap(rowActionButton.superview).bounds,
            from: rowActionButton.superview
        )
        let footerDeleteFrame = view.convert(footerDeleteButton.frame, from: footerDeleteButton.superview)

        XCTAssertEqual(footerDeleteFrame.maxX, rowActionColumnFrame.maxX, accuracy: 8)
    }

    @MainActor
    func testActionColumnHeaderUsesActionColumnLeftEdge() throws {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 460)
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        let actionHeader = try XCTUnwrap(view.firstTextField(withValue: "Action"))
        let rowActionButton = try XCTUnwrap(view.firstButton(titled: "Use"))
        let headerFrame = view.convert(actionHeader.frame, from: actionHeader.superview)
        let rowActionColumnFrame = try view.convert(
            XCTUnwrap(rowActionButton.superview).bounds,
            from: rowActionButton.superview
        )

        XCTAssertEqual(
            headerFrame.minX, rowActionColumnFrame.minX, accuracy: 2,
            "Action header should start at the row action column's leading edge"
        )
    }

    @MainActor
    func testRowActionControlsUseActionColumnLeftEdge() throws {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 460)
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()

        let rowActionButton = try XCTUnwrap(view.firstButton(titled: "Use"))
        let rowActionFrame = view.convert(rowActionButton.frame, from: rowActionButton.superview)
        let rowActionColumnFrame = try view.convert(
            XCTUnwrap(rowActionButton.superview).bounds,
            from: rowActionButton.superview
        )

        XCTAssertEqual(
            rowActionFrame.minX, rowActionColumnFrame.minX, accuracy: 8,
            "Row action controls should start at the action column's leading edge"
        )
    }

    @MainActor
    func testModelStatusTextStaysNeutralWhenStateHasOtherVisualIndicator() throws {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 460)
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            PreferencesModelRow(
                id: "ggml-medium",
                displayName: PreferencesModelState.displayName(forModelID: "ggml-medium"),
                descriptionText: PreferencesModelState.description(forModelID: "ggml-medium"),
                isInstalled: false,
                isSelected: false,
                isDownloading: true,
                isCancelled: false,
                downloadProgressText: "42% (630/1500 MB)"
            ),
        ], downloadableModels: [], isDownloadInProgress: true)
        view.layoutSubtreeIfNeeded()

        let recommended = try XCTUnwrap(view.firstTextField(withValue: "Recommended"))
        XCTAssertFalse(recommended.textColor?.isEqual(NSColor.systemBlue) ?? false)
    }

    @MainActor
    func testModelListHeightIsContentDrivenAndCapped() {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 560, height: 620)

        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()
        let shortHeight = view.visibleModelListHeight

        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
            modelRow(id: "ggml-medium", installed: false, selected: false),
            modelRow(id: "ggml-large-v3-turbo", installed: false, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()
        let tallHeight = view.visibleModelListHeight

        XCTAssertGreaterThan(tallHeight, shortHeight)
        XCTAssertLessThanOrEqual(tallHeight, 380)
    }

    @MainActor
    func testShortWindowScrollsTheListInsteadOfSquashingRows() {
        let view = makeView()
        view.frame = NSRect(x: 0, y: 0, width: 620, height: 400)
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
            modelRow(id: "ggml-medium", installed: false, selected: false),
            modelRow(id: "ggml-large-v3-turbo", installed: false, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        view.layoutSubtreeIfNeeded()
        let squeezedRowHeight = view.visibleFirstModelRowHeight

        view.frame = NSRect(x: 0, y: 0, width: 740, height: 512)
        view.layoutSubtreeIfNeeded()
        let naturalRowHeight = view.visibleFirstModelRowHeight

        XCTAssertNotNil(squeezedRowHeight)
        XCTAssertEqual(
            squeezedRowHeight ?? 0, naturalRowHeight ?? 0, accuracy: 1,
            "at minimum window height the list must scroll, not compress row heights"
        )
    }

    @MainActor
    func testUpdateWithUnchangedInputsSkipsListRebuild() {
        let view = makeView()
        let rows = [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
        ]

        view.update(rows: rows, downloadableModels: [], isDownloadInProgress: false)
        let rebuildsAfterFirstUpdate = view.listRebuildCount

        view.update(rows: rows, downloadableModels: [], isDownloadInProgress: false)
        view.update(rows: rows, downloadableModels: [], isDownloadInProgress: false)

        XCTAssertEqual(
            view.listRebuildCount, rebuildsAfterFirstUpdate,
            "identical snapshots must not tear down and recreate the model rows"
        )
    }

    @MainActor
    func testUpdateWithChangedSelectionStillRebuildsList() {
        let view = makeView()
        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
            modelRow(id: "ggml-small.en", installed: true, selected: false),
        ], downloadableModels: [], isDownloadInProgress: false)
        let rebuildsAfterFirstUpdate = view.listRebuildCount

        view.update(rows: [
            modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: false),
            modelRow(id: "ggml-small.en", installed: true, selected: true),
        ], downloadableModels: [], isDownloadInProgress: false)

        XCTAssertEqual(view.listRebuildCount, rebuildsAfterFirstUpdate + 1)
        XCTAssertEqual(view.visibleModelPickerTitle, PreferencesModelState.displayName(forModelID: "ggml-small.en"))
    }
}

private extension NSView {
    func firstButton(titled title: String) -> NSButton? {
        if let button = self as? NSButton, button.title == title, !button.isEffectivelyHidden {
            return button
        }
        return subviews.lazy.compactMap { $0.firstButton(titled: title) }.first
    }

    func firstButton(withToolTip toolTip: String) -> NSButton? {
        if let button = self as? NSButton, button.toolTip == toolTip, !button.isEffectivelyHidden {
            return button
        }
        return subviews.lazy.compactMap { $0.firstButton(withToolTip: toolTip) }.first
    }

    func firstTextField(withValue value: String) -> NSTextField? {
        if let field = self as? NSTextField, field.stringValue == value, !field.isEffectivelyHidden {
            return field
        }
        return subviews.lazy.compactMap { $0.firstTextField(withValue: value) }.first
    }

    var isEffectivelyHidden: Bool {
        isHidden || superview?.isEffectivelyHidden == true
    }
}

@MainActor
private func firstSelectionPillLayer(in view: NSView) -> CALayer? {
    if let layer = view.layer?.sublayers?.first(where: { $0.cornerRadius == 9 && !$0.frame.isEmpty }) {
        return layer
    }
    for subview in view.subviews {
        if let found = firstSelectionPillLayer(in: subview) {
            return found
        }
    }
    return nil
}

@MainActor
private func firstSearchField(in view: NSView) -> NSSearchField? {
    if let field = view as? NSSearchField {
        return field
    }
    for subview in view.subviews {
        if let found = firstSearchField(in: subview) {
            return found
        }
    }
    return nil
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
