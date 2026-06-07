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
            ["General", "Models", "Keyboard", "History", "Vocabulary", "About"]
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
    func testHistoryButtonsDispatchActions() throws {
        let record = TranscriptRecord(id: UUID(), createdAt: .now, text: "A saved transcript")
        var copiedID: UUID?
        var repastedID: UUID?
        var deletedIDs: Set<UUID> = []
        let controller = PreferencesWindowController(actions: makeActions(
            copyTranscript: { copiedID = $0 },
            repasteTranscript: { repastedID = $0 },
            deleteTranscripts: { deletedIDs = $0 }
        ))
        controller.update(snapshot: makeSnapshot(records: [record]))
        controller.selectSection(.history)
        let contentView = try XCTUnwrap(controller.window?.contentView)

        try XCTUnwrap(contentView.button(titled: "Copy")).performClick(nil)
        try XCTUnwrap(contentView.button(titled: "Paste Again")).performClick(nil)
        try XCTUnwrap(contentView.button(titled: "Delete")).performClick(nil)

        XCTAssertEqual(copiedID, record.id)
        XCTAssertEqual(repastedID, record.id)
        XCTAssertEqual(deletedIDs, [record.id])
    }

    @MainActor
    func testHistoryToggleDispatchesAction() throws {
        var enabledValue: Bool?
        let controller = PreferencesWindowController(actions: makeActions(
            setTranscriptHistoryEnabled: { enabledValue = $0 }
        ))
        controller.selectSection(.history)
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let toggle = try XCTUnwrap(contentView.button(titled: "Save transcript history"))

        toggle.performClick(nil)

        XCTAssertEqual(enabledValue, false)
    }

    @MainActor
    func testGeneralKeyboardAndAboutButtonsDispatchActions() throws {
        var requestedMicrophone = false
        var requestedAccessibility = false
        var requestedHotkey = false
        var openedProjectPage = false
        let controller = PreferencesWindowController(actions: makeActions(
            setHotkey: { requestedHotkey = true },
            requestMicrophone: { requestedMicrophone = true },
            requestAccessibility: { requestedAccessibility = true },
            openProjectPage: { openedProjectPage = true }
        ))
        let contentView = try XCTUnwrap(controller.window?.contentView)

        try XCTUnwrap(contentView.button(titled: "Request")).performClick(nil)
        try XCTUnwrap(contentView.button(titled: "Open Prompt")).performClick(nil)
        controller.selectSection(.keyboard)
        try XCTUnwrap(contentView.button(titled: "Set Hotkey...")).performClick(nil)
        controller.selectSection(.about)
        try XCTUnwrap(contentView.button(titled: "Open Project Page")).performClick(nil)

        XCTAssertTrue(requestedMicrophone)
        XCTAssertTrue(requestedAccessibility)
        XCTAssertTrue(requestedHotkey)
        XCTAssertTrue(openedProjectPage)
    }

    @MainActor
    func testVocabularyPageFiltersPreferredTermsAndFallsBackToFirstSelection() {
        let first = DictionaryEntry(wrong: "post grass", correct: "Postgres")
        let second = DictionaryEntry(wrong: "cube", correct: "Kubernetes")
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot(dictionaryEntries: [first, second]))
        controller.selectSection(.dictionary)

        XCTAssertEqual(controller.dictionarySelectedWrong, first.correct)
        controller.setDictionarySearchQuery("kube")

        XCTAssertEqual(controller.dictionaryVisibleWrongValues, [second.correct])
        XCTAssertEqual(controller.dictionarySelectedWrong, second.correct)

        controller.setDictionarySearchQuery("missing")
        XCTAssertEqual(controller.dictionaryState, .noSearchResults)
        XCTAssertNil(controller.dictionarySelectedWrong)

        controller.setDictionarySearchQuery("")
        XCTAssertEqual(controller.dictionaryState, .entries)
        XCTAssertEqual(controller.dictionarySelectedWrong, first.correct)
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
    func testVocabularyAddButtonDispatchesAction() throws {
        var savedValue: String?
        let controller = PreferencesWindowController(actions: makeActions(
            saveDictionaryEntry: { _, _, correct, completion in
                savedValue = correct
                completion(.success(()))
            }
        ))
        controller.selectSection(.dictionary)
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let field = try XCTUnwrap(contentView.textField(withPlaceholder: "Add a preferred term, such as Anduril"))
        field.stringValue = "Anduril"

        try XCTUnwrap(contentView.button(titled: "Add Term")).performClick(nil)

        XCTAssertEqual(savedValue, "Anduril")
    }

    @MainActor
    func testVocabularyEditAndDeleteButtonsDispatchActions() throws {
        var editedOriginal: String?
        var editedValue: String?
        var deletedValues: Set<String> = []
        let controller = PreferencesWindowController(actions: makeActions(
            saveDictionaryEntry: { original, _, correct, completion in
                editedOriginal = original
                editedValue = correct
                completion(.success(()))
            },
            deleteDictionaryEntries: { values, completion in
                deletedValues = values
                completion(.success(()))
            }
        ))
        controller.update(snapshot: makeSnapshot(dictionaryEntries: [
            DictionaryEntry(wrong: "Anduril", correct: "Anduril")
        ]))
        controller.selectSection(.dictionary)
        let contentView = try XCTUnwrap(controller.window?.contentView)

        try XCTUnwrap(contentView.button(titled: "Edit")).performClick(nil)
        let sheet = try XCTUnwrap(controller.window?.attachedSheet)
        let field = try XCTUnwrap(sheet.contentView?.editableTextField(withValue: "Anduril"))
        field.stringValue = "Anduril Labs"
        try XCTUnwrap(sheet.contentView?.button(titled: "Save")).performClick(nil)
        try XCTUnwrap(contentView.button(titled: "Delete")).performClick(nil)

        XCTAssertEqual(editedOriginal, "Anduril")
        XCTAssertEqual(editedValue, "Anduril Labs")
        XCTAssertEqual(deletedValues, ["Anduril"])
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
    private func makeActions(
        setHotkey: @escaping () -> Void = {},
        requestMicrophone: @escaping () -> Void = {},
        requestAccessibility: @escaping () -> Void = {},
        openProjectPage: @escaping () -> Void = {},
        setTranscriptHistoryEnabled: @escaping (Bool) -> Void = { _ in },
        copyTranscript: @escaping (UUID) -> Void = { _ in },
        repasteTranscript: @escaping (UUID) -> Void = { _ in },
        deleteTranscripts: @escaping (Set<UUID>) -> Void = { _ in },
        saveDictionaryEntry: @escaping (String?, String, String, @escaping (Result<Void, Error>) -> Void) -> Void = {
            _, _, _, completion in completion(.success(()))
        },
        deleteDictionaryEntries: @escaping (Set<String>, @escaping (Result<Void, Error>) -> Void) -> Void = {
            _, completion in completion(.success(()))
        }
    ) -> PreferencesWindowController.Actions {
        PreferencesWindowController.Actions(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            setHotkey: setHotkey,
            requestMicrophone: requestMicrophone,
            requestAccessibility: requestAccessibility,
            setTranscriptHistoryEnabled: setTranscriptHistoryEnabled,
            copyTranscript: copyTranscript,
            repasteTranscript: repasteTranscript,
            deleteTranscripts: deleteTranscripts,
            saveDictionaryEntry: saveDictionaryEntry,
            deleteDictionaryEntries: deleteDictionaryEntries,
            openProjectPage: openProjectPage
        )
    }
}

private extension NSView {
    func button(titled title: String) -> NSButton? {
        if let button = self as? NSButton, button.title == title, !button.isEffectivelyHidden {
            return button
        }
        return subviews.lazy.compactMap { $0.button(titled: title) }.first
    }

    func textField(withPlaceholder placeholder: String) -> NSTextField? {
        if let field = self as? NSTextField, field.placeholderString == placeholder, !field.isEffectivelyHidden {
            return field
        }
        return subviews.lazy.compactMap { $0.textField(withPlaceholder: placeholder) }.first
    }

    func editableTextField(withValue value: String) -> NSTextField? {
        if let field = self as? NSTextField, field.isEditable, field.stringValue == value, !field.isEffectivelyHidden {
            return field
        }
        return subviews.lazy.compactMap { $0.editableTextField(withValue: value) }.first
    }

    var isEffectivelyHidden: Bool {
        isHidden || superview?.isEffectivelyHidden == true
    }
}
