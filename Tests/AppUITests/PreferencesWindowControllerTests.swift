import AppKit
import DictionaryStore
@testable import AppUI
import SettingsStore
import TranscriptHistoryStore
import XCTest

final class PreferencesWindowControllerTests: XCTestCase {
    @MainActor
    func testSidebarContainsExpectedSections() {
        XCTAssertEqual(
            PreferencesWindowController.Section.allCases.map(\.title),
            ["General", "Models", "Keyboard", "History", "Dictionary", "About"]
        )
    }

    @MainActor
    func testWindowUsesCompactResizableConfiguration() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertEqual(window.title, "Scrawl")
        XCTAssertEqual(contentView.frame.size, NSSize(width: 680, height: 460))
        XCTAssertEqual(window.minSize, NSSize(width: 620, height: 400))
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.resizable))
    }

    @MainActor
    func testSidebarSelectionSwitchesPagesAndPersists() {
        let controller = PreferencesWindowController(actions: makeActions())

        XCTAssertFalse(controller.hasDraggableSidebarDivider)
        controller.selectSection(.models)
        XCTAssertEqual(controller.visibleSection, .models)

        controller.window?.orderOut(nil)
        controller.showWindow(nil)
        XCTAssertEqual(controller.visibleSection, .models)
    }

    @MainActor
    func testModelsPageHasUnambiguousLayoutAtMinimumWindowSize() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        window.setFrame(NSRect(origin: .zero, size: window.minSize), display: false)
        controller.selectSection(.models)
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertFalse(controller.visibleSectionHasAmbiguousLayout)
        XCTAssertTrue(controller.isVisibleSectionWithinContentBounds)
        XCTAssertTrue(controller.isVisibleSectionCriticalContentWithinBounds)
    }

    @MainActor
    func testPreferencesBackgroundsUpdateForAppearanceChanges() {
        for view in [
            PreferencesPageSupport.makeRoundedBackground(),
            PreferencesPageSupport.makeContentBackground()
        ] {
            let background = view as? PreferencesBackgroundView
            XCTAssertNotNil(background)

            background?.appearance = NSAppearance(named: .aqua)
            background?.updateLayer()
            let lightComponents = background?.layer?.backgroundColor?.components

            background?.appearance = NSAppearance(named: .darkAqua)
            background?.updateLayer()
            let darkComponents = background?.layer?.backgroundColor?.components

            XCTAssertNotEqual(lightComponents, darkComponents)
        }
    }

    @MainActor
    func testHistoryPageShowsDisabledAndUnavailableStates() {
        let controller = PreferencesWindowController(actions: makeActions())

        controller.update(snapshot: makeSnapshot(isHistoryEnabled: false))
        XCTAssertEqual(controller.historyState, .disabled)

        controller.update(snapshot: makeSnapshot(historyLoadErrorDescription: "corrupt"))
        XCTAssertEqual(controller.historyState, .unavailable)
    }

    @MainActor
    func testHistoryPageFiltersAndFallsBackToFirstVisibleSelection() {
        let first = TranscriptRecord(id: UUID(), createdAt: Date(timeIntervalSince1970: 2), text: "Swift notes")
        let second = TranscriptRecord(id: UUID(), createdAt: Date(timeIntervalSince1970: 1), text: "Kubernetes notes")
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot(records: [first, second]))
        controller.selectSection(.history)

        XCTAssertEqual(controller.historySelectedRecordID, first.id)
        controller.setHistorySearchQuery("kubernetes")

        XCTAssertEqual(controller.historyVisibleRecordIDs, [second.id])
        XCTAssertEqual(controller.historySelectedRecordID, second.id)

        controller.setHistorySearchQuery("missing")
        XCTAssertEqual(controller.historyState, .noSearchResults)
        XCTAssertNil(controller.historySelectedRecordID)

        controller.setHistorySearchQuery("")
        XCTAssertEqual(controller.historyState, .records)
        XCTAssertEqual(controller.historySelectedRecordID, first.id)
    }

    @MainActor
    func testHistoryAddDictionaryRequiresSelectedText() {
        let record = TranscriptRecord(id: UUID(), createdAt: .now, text: "Kubernetes notes")
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot(records: [record]))

        XCTAssertFalse(controller.isHistoryAddDictionaryEnabled)
        controller.selectHistoryText(range: NSRange(location: 0, length: 10))
        XCTAssertTrue(controller.isHistoryAddDictionaryEnabled)
    }

    @MainActor
    func testHistoryPageHasUnambiguousLayoutAtMinimumWindowSize() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        window.setFrame(NSRect(origin: .zero, size: window.minSize), display: false)
        controller.update(snapshot: makeSnapshot(records: [
            TranscriptRecord(id: UUID(), createdAt: .now, text: "A saved transcript")
        ]))
        controller.selectSection(.history)
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertFalse(controller.visibleSectionHasAmbiguousLayout)
        XCTAssertTrue(controller.isVisibleSectionWithinContentBounds)
        XCTAssertTrue(controller.isVisibleSectionCriticalContentWithinBounds)
    }

    @MainActor
    func testHistoryActionControlsFitAtDefaultWindowSize() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        controller.update(snapshot: makeSnapshot(records: [
            TranscriptRecord(id: UUID(), createdAt: .now, text: "A saved transcript")
        ]))
        controller.selectSection(.history)
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.isVisibleSectionCriticalContentWithinBounds)
    }

    @MainActor
    func testDictionaryPageFiltersByEitherColumnAndFallsBackToFirstSelection() {
        let first = DictionaryEntry(wrong: "post grass", correct: "Postgres")
        let second = DictionaryEntry(wrong: "cube", correct: "Kubernetes")
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot(dictionaryEntries: [first, second]))
        controller.selectSection(.dictionary)

        XCTAssertEqual(controller.dictionarySelectedWrong, first.wrong)
        controller.setDictionarySearchQuery("kube")

        XCTAssertEqual(controller.dictionaryVisibleWrongValues, [second.wrong])
        XCTAssertEqual(controller.dictionarySelectedWrong, second.wrong)

        controller.setDictionarySearchQuery("missing")
        XCTAssertEqual(controller.dictionaryState, .noSearchResults)
        XCTAssertNil(controller.dictionarySelectedWrong)

        controller.setDictionarySearchQuery("")
        XCTAssertEqual(controller.dictionaryState, .entries)
        XCTAssertEqual(controller.dictionarySelectedWrong, first.wrong)
    }

    @MainActor
    func testDictionaryPageShowsEmptyState() {
        let controller = PreferencesWindowController(actions: makeActions())

        controller.update(snapshot: makeSnapshot())

        XCTAssertEqual(controller.dictionaryState, .empty)
    }

    @MainActor
    func testDictionarySelectionUsesUpdatedVisibleKeyAfterCaseOnlyEdit() {
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot(dictionaryEntries: [
            DictionaryEntry(wrong: "kubernetes", correct: "Kubernetes")
        ]))

        controller.update(snapshot: makeSnapshot(dictionaryEntries: [
            DictionaryEntry(wrong: "Kubernetes", correct: "Kubernetes")
        ]))

        XCTAssertEqual(controller.dictionarySelectedWrong, "Kubernetes")
    }

    @MainActor
    func testDictionaryPageHasUnambiguousLayoutAtMinimumWindowSize() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        window.setFrame(NSRect(origin: .zero, size: window.minSize), display: false)
        controller.update(snapshot: makeSnapshot(dictionaryEntries: [
            DictionaryEntry(wrong: "post grass", correct: "Postgres")
        ]))
        controller.selectSection(.dictionary)
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertFalse(controller.visibleSectionHasAmbiguousLayout)
        XCTAssertTrue(controller.isVisibleSectionWithinContentBounds)
        XCTAssertTrue(controller.isVisibleSectionCriticalContentWithinBounds)
    }

    @MainActor
    private func makeSnapshot(
        isHistoryEnabled: Bool = true,
        historyLoadErrorDescription: String? = nil,
        records: [TranscriptRecord] = [],
        dictionaryEntries: [DictionaryEntry] = []
    ) -> PreferencesWindowController.Snapshot {
        PreferencesWindowController.Snapshot(
            settings: AppSettings(isTranscriptHistoryEnabled: isHistoryEnabled),
            downloadableModels: [],
            modelRows: [],
            microphoneStatus: .notDetermined,
            accessibilityStatus: .notDetermined,
            isCapturingHotkey: false,
            isModelDownloadInProgress: false,
            transcriptHistory: records,
            transcriptHistoryLoadErrorDescription: historyLoadErrorDescription,
            dictionaryEntries: dictionaryEntries
        )
    }

    @MainActor
    private func makeActions() -> PreferencesWindowController.Actions {
        PreferencesWindowController.Actions(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            setHotkey: {},
            requestMicrophone: {},
            requestAccessibility: {},
            setTranscriptHistoryEnabled: { _ in },
            copyTranscript: { _ in },
            repasteTranscript: { _ in },
            deleteTranscripts: { _ in },
            addDictionaryEntry: { _, _, completion in completion(.success(())) },
            saveDictionaryEntry: { _, _, _, completion in completion(.success(())) },
            deleteDictionaryEntries: { _, completion in completion(.success(())) }
        )
    }
}
