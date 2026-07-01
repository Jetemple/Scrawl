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
    func testModelsTableShowsColumnHeadersAndEngine() throws {
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
    func testModelsSplitInstalledAndAvailableSectionsWithKebabs() {
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
        XCTAssertEqual(view.visibleModelKebabButtonCount, 3)
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
}

private extension NSView {
    func firstTextField(withValue value: String) -> NSTextField? {
        if let field = self as? NSTextField, field.stringValue == value {
            return field
        }
        return subviews.lazy.compactMap { $0.firstTextField(withValue: value) }.first
    }
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
