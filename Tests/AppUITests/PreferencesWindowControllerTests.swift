import AppKit
@testable import AppUI
import DictionaryStore
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
    func testModelsPageUsesTopAnchoredTwoLineRowsWithoutSelectedAction() {
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot(modelRows: [
            PreferencesModelRow(
                id: "tiny.en",
                displayName: "tiny.en — fast, 75 MB",
                isInstalled: true,
                isSelected: false,
                isDownloading: false,
                isCancelled: false,
                downloadProgressText: nil
            ),
            PreferencesModelRow(
                id: "large-v3-turbo",
                displayName: "large-v3-turbo — highest accuracy, 1.6 GB",
                isInstalled: true,
                isSelected: true,
                isDownloading: false,
                isCancelled: false,
                downloadProgressText: nil
            ),
        ]))
        controller.selectSection(.models)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.modelsListIsTopAnchored)
        XCTAssertEqual(controller.modelsTwoLineRowCount, 2)
        XCTAssertFalse(controller.modelsSelectedRowHasAction)
    }

    @MainActor
    func testSnapshotCarriesDownloadProgressText() {
        let snapshot = makeSnapshot(downloadProgressText: "42% (630/1500 MB)")
        XCTAssertEqual(snapshot.downloadProgressText, "42% (630/1500 MB)")
    }

    @MainActor
    func testSnapshotDownloadProgressTextDefaultsToNil() {
        let snapshot = makeSnapshot()
        XCTAssertNil(snapshot.downloadProgressText)
    }

    @MainActor
    func testPreferencesBackgroundsUpdateForAppearanceChanges() {
        for view in [
            PreferencesPageSupport.makeRoundedBackground(),
            PreferencesPageSupport.makeContentBackground(),
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
    func testPageHeaderUsesSameWidthAndLeadingEdgeAsContent() throws {
        let content = PreferencesPageSupport.makeRoundedBackground()
        content.heightAnchor.constraint(equalToConstant: 80).isActive = true
        let page = PreferencesPageSupport.makePage(
            title: "Models",
            description: "Select an installed model or download another.",
            content: [content]
        )
        page.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        page.layoutSubtreeIfNeeded()

        let pageStack = try XCTUnwrap(page.subviews.compactMap { $0 as? NSStackView }.first)
        let header = try XCTUnwrap(pageStack.arrangedSubviews.first)

        XCTAssertEqual(header.frame.minX, content.frame.minX, accuracy: 0.5)
        XCTAssertEqual(header.frame.width, content.frame.width, accuracy: 0.5)
    }

    @MainActor
    func testPageHeaderLabelsFillWidthAndAlignLeft() {
        let header = PreferencesPageSupport.makePageHeader(
            title: "Models",
            description: "Select an installed model or download another."
        )
        header.frame = NSRect(x: 0, y: 0, width: 500, height: 60)
        header.layoutSubtreeIfNeeded()

        let labels = header.subviews.compactMap { $0 as? NSTextField }
        XCTAssertEqual(labels.count, 2)
        for label in labels {
            XCTAssertEqual(label.alignment, .left)
            XCTAssertGreaterThanOrEqual(label.frame.width, header.bounds.width)
        }
        XCTAssertEqual(labels[0].frame.width, labels[1].frame.width, accuracy: 0.5)
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
            TranscriptRecord(id: UUID(), createdAt: .now, text: "A saved transcript"),
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
            TranscriptRecord(id: UUID(), createdAt: .now, text: "A saved transcript"),
        ]))
        controller.selectSection(.history)
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.isVisibleSectionCriticalContentWithinBounds)
    }

    @MainActor
    func testHistoryRowsPresentTranscriptBeforeQuietFooter() {
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot(records: [
            TranscriptRecord(
                id: UUID(),
                createdAt: .now,
                text: "A saved transcript",
                recordingDurationMS: 2000,
                transcriptionLatencyMS: 1400
            ),
        ]))
        controller.selectSection(.history)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.historyRowsAreTranscriptFirst)
        XCTAssertTrue(controller.historyTranscriptTextIsLeftAligned)
        XCTAssertEqual(controller.historyVisibleMetrics, ["2s audio · 1.4s processing"])
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
    func testModelsAddRevealAndFindButtonsDispatchActions() throws {
        var addedModel = false
        var revealedFolder = false
        var openedModelSource = false
        let controller = PreferencesWindowController(actions: makeActions(
            addModel: { addedModel = true },
            revealModelsFolder: { revealedFolder = true },
            openModelSource: { openedModelSource = true }
        ))
        let contentView = try XCTUnwrap(controller.window?.contentView)

        controller.selectSection(.models)
        try XCTUnwrap(contentView.button(titled: "Add Model…")).performClick(nil)
        try XCTUnwrap(contentView.button(titled: "Reveal Models Folder")).performClick(nil)
        try XCTUnwrap(contentView.button(titled: "Find models")).performClick(nil)

        XCTAssertTrue(addedModel)
        XCTAssertTrue(revealedFolder)
        XCTAssertTrue(openedModelSource)
    }

    @MainActor
    func testGeneralLaunchAtLoginCheckboxReflectsStateAndDispatchesAction() {
        var capturedValue: Bool?
        let controller = PreferencesWindowController(actions: makeActions(
            setLaunchAtLogin: { capturedValue = $0 }
        ))

        // Defaults to off.
        controller.update(snapshot: makeSnapshot())
        XCTAssertFalse(controller.generalLaunchAtLoginEnabled)

        // Reflects the live login-item state when enabled.
        controller.update(snapshot: makeSnapshot(launchAtLoginEnabled: true))
        XCTAssertTrue(controller.generalLaunchAtLoginEnabled)

        // Clicking dispatches the action.
        let contentView = controller.window?.contentView
        let checkbox = contentView?.button(titled: "Launch at login")
        XCTAssertNotNil(checkbox)
        checkbox?.performClick(nil)
        XCTAssertNotNil(capturedValue)
    }

    @MainActor
    func testGeneralClipboardHistoryCheckboxReflectsSettingAndDispatchesAction() {
        var capturedValue: Bool?
        let controller = PreferencesWindowController(actions: makeActions(
            setKeepTranscriptsInClipboardHistory: { capturedValue = $0 }
        ))

        // Defaults to false.
        controller.update(snapshot: makeSnapshot())
        XCTAssertFalse(controller.generalIsClipboardHistoryEnabled)

        // Reflects true when setting is on.
        controller.update(snapshot: makeSnapshot(keepTranscriptsInClipboardHistory: true))
        XCTAssertTrue(controller.generalIsClipboardHistoryEnabled)

        // Clicking dispatches the action.
        let contentView = controller.window?.contentView
        let checkbox = contentView?.button(titled: "Keep transcripts in clipboard history")
        XCTAssertNotNil(checkbox)
        checkbox?.performClick(nil)
        XCTAssertNotNil(capturedValue)
    }

    @MainActor
    func testGeneralModelOffloadControlShowsChoicesAndDispatchesSelection() {
        var selectedPolicy: ModelOffloadPolicy?
        let controller = PreferencesWindowController(actions: makeActions(
            setModelOffloadPolicy: { selectedPolicy = $0 }
        ))
        controller.update(snapshot: makeSnapshot(modelOffloadPolicy: .oneMinute))

        XCTAssertEqual(
            controller.generalModelOffloadChoices,
            ["Immediately", "1 minute", "5 minutes", "15 minutes", "Never"]
        )
        XCTAssertEqual(controller.generalSelectedModelOffloadPolicy, .oneMinute)

        controller.selectGeneralModelOffloadPolicy(.fifteenMinutes)

        XCTAssertEqual(selectedPolicy, .fifteenMinutes)
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
    func testDictionaryPageShowsUnavailableStateAndDispatchesRecovery() throws {
        var didRecover = false
        let controller = PreferencesWindowController(actions: makeActions(
            recoverDictionary: { completion in
                didRecover = true
                completion(.success(()))
            }
        ))

        controller.update(snapshot: makeSnapshot(dictionaryLoadErrorDescription: "corrupt"))
        controller.selectSection(.dictionary)
        let contentView = try XCTUnwrap(controller.window?.contentView)

        XCTAssertEqual(controller.dictionaryState, .unavailable)
        try XCTUnwrap(contentView.button(titled: "Reset Vocabulary")).performClick(nil)
        XCTAssertTrue(didRecover)
    }

    @MainActor
    func testDictionarySelectionUsesUpdatedVisibleKeyAfterCaseOnlyEdit() {
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot(dictionaryEntries: [
            DictionaryEntry(wrong: "kubernetes", correct: "Kubernetes"),
        ]))

        controller.update(snapshot: makeSnapshot(dictionaryEntries: [
            DictionaryEntry(wrong: "Kubernetes", correct: "Kubernetes"),
        ]))

        XCTAssertEqual(controller.dictionarySelectedWrong, "Kubernetes")
    }

    @MainActor
    func testDictionaryPageHasUnambiguousLayoutAtMinimumWindowSize() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        window.setFrame(NSRect(origin: .zero, size: window.minSize), display: false)
        controller.update(snapshot: makeSnapshot(dictionaryEntries: [
            DictionaryEntry(wrong: "post grass", correct: "Postgres"),
        ]))
        controller.selectSection(.dictionary)
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertFalse(controller.visibleSectionHasAmbiguousLayout)
        XCTAssertTrue(controller.isVisibleSectionWithinContentBounds)
        XCTAssertTrue(controller.isVisibleSectionCriticalContentWithinBounds)
    }

    @MainActor
    func testEverySettingsPageFitsAtMinimumWindowSize() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        window.setFrame(NSRect(origin: .zero, size: window.minSize), display: false)
        controller.update(snapshot: makeSnapshot(
            records: [TranscriptRecord(id: UUID(), createdAt: .now, text: "A saved transcript")],
            dictionaryEntries: [DictionaryEntry(wrong: "Anduril", correct: "Anduril")]
        ))

        for section in PreferencesWindowController.Section.allCases {
            controller.selectSection(section)
            window.contentView?.layoutSubtreeIfNeeded()

            XCTAssertFalse(controller.visibleSectionHasAmbiguousLayout, "\(section.title) has ambiguous layout")
            XCTAssertTrue(controller.isVisibleSectionWithinContentBounds, "\(section.title) extends beyond content bounds")
            XCTAssertTrue(controller.isVisibleSectionCriticalContentWithinBounds, "\(section.title) clips critical controls")
        }
    }

    @MainActor
    func testListPagesUseSharedGroupedWorkspaceTreatment() {
        let controller = PreferencesWindowController(actions: makeActions())

        XCTAssertTrue(controller.historyUsesGroupedWorkspace)
        XCTAssertTrue(controller.dictionaryUsesGroupedWorkspace)
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
        let field = try XCTUnwrap(contentView.textField(withPlaceholder: "Add a preferred term"))
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
            DictionaryEntry(wrong: "Anduril", correct: "Anduril"),
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
        modelOffloadPolicy: ModelOffloadPolicy = .fiveMinutes,
        historyLoadErrorDescription: String? = nil,
        records: [TranscriptRecord] = [],
        dictionaryEntries: [DictionaryEntry] = [],
        dictionaryLoadErrorDescription: String? = nil,
        modelRows: [PreferencesModelRow] = [],
        downloadProgressText: String? = nil,
        keepTranscriptsInClipboardHistory: Bool = false,
        launchAtLoginEnabled: Bool = false
    ) -> PreferencesWindowController.Snapshot {
        PreferencesWindowController.Snapshot(
            settings: AppSettings(
                isTranscriptHistoryEnabled: isHistoryEnabled,
                modelOffloadPolicy: modelOffloadPolicy,
                keepTranscriptsInClipboardHistory: keepTranscriptsInClipboardHistory
            ),
            downloadableModels: [],
            modelRows: modelRows,
            microphoneStatus: .notDetermined,
            accessibilityStatus: .notDetermined,
            isCapturingHotkey: false,
            isModelDownloadInProgress: false,
            downloadProgressText: downloadProgressText,
            transcriptHistory: records,
            transcriptHistoryLoadErrorDescription: historyLoadErrorDescription,
            dictionaryEntries: dictionaryEntries,
            dictionaryLoadErrorDescription: dictionaryLoadErrorDescription,
            launchAtLoginEnabled: launchAtLoginEnabled
        )
    }

    @MainActor
    private func makeActions(
        setHotkey: @escaping () -> Void = {},
        requestMicrophone: @escaping () -> Void = {},
        requestAccessibility: @escaping () -> Void = {},
        addModel: @escaping () -> Void = {},
        revealModelsFolder: @escaping () -> Void = {},
        openModelSource: @escaping () -> Void = {},
        openProjectPage: @escaping () -> Void = {},
        setTranscriptHistoryEnabled: @escaping (Bool) -> Void = { _ in },
        setModelOffloadPolicy: @escaping (ModelOffloadPolicy) -> Void = { _ in },
        setKeepTranscriptsInClipboardHistory: @escaping (Bool) -> Void = { _ in },
        setLaunchAtLogin: @escaping (Bool) -> Void = { _ in },
        copyTranscript: @escaping (UUID) -> Void = { _ in },
        repasteTranscript: @escaping (UUID) -> Void = { _ in },
        deleteTranscripts: @escaping (Set<UUID>) -> Void = { _ in },
        saveDictionaryEntry: @escaping (String?, String, String, @escaping (Result<Void, Error>) -> Void) -> Void = {
            _, _, _, completion in completion(.success(()))
        },
        deleteDictionaryEntries: @escaping (Set<String>, @escaping (Result<Void, Error>) -> Void) -> Void = {
            _, completion in completion(.success(()))
        },
        recoverDictionary: @escaping (@escaping (Result<Void, Error>) -> Void) -> Void = {
            completion in completion(.success(()))
        }
    ) -> PreferencesWindowController.Actions {
        PreferencesWindowController.Actions(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            cancelDownload: {},
            addModel: addModel,
            revealModelsFolder: revealModelsFolder,
            openModelSource: openModelSource,
            setHotkey: setHotkey,
            requestMicrophone: requestMicrophone,
            requestAccessibility: requestAccessibility,
            setModelOffloadPolicy: setModelOffloadPolicy,
            setKeepTranscriptsInClipboardHistory: setKeepTranscriptsInClipboardHistory,
            setLaunchAtLogin: setLaunchAtLogin,
            setTranscriptHistoryEnabled: setTranscriptHistoryEnabled,
            copyTranscript: copyTranscript,
            repasteTranscript: repasteTranscript,
            deleteTranscripts: deleteTranscripts,
            saveDictionaryEntry: saveDictionaryEntry,
            deleteDictionaryEntries: deleteDictionaryEntries,
            recoverDictionary: recoverDictionary,
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
