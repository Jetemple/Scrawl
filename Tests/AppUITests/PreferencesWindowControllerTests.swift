import AppKit
@testable import AppUI
import DictionaryStore
import Permissions
import SettingsStore
import TranscriptHistoryStore
import XCTest

final class PreferencesWindowControllerTests: XCTestCase {
    @MainActor
    func testIdenticalSnapshotIsAppliedOnlyOnce() {
        let controller = PreferencesWindowController(actions: makeActions())

        controller.update(snapshot: makeSnapshot())
        controller.update(snapshot: makeSnapshot())
        XCTAssertEqual(controller.snapshotApplyCount, 1, "identical snapshots must not re-apply")

        controller.update(snapshot: makeSnapshot(downloadProgressText: "10% (100/1000 MB)"))
        XCTAssertEqual(controller.snapshotApplyCount, 2, "changed snapshots must still apply")
    }

    @MainActor
    func testToolbarContainsFiveConsolidatedSections() {
        XCTAssertEqual(
            PreferencesWindowController.Section.allCases.map(\.title),
            ["General", "Models", "Dictionary", "History", "About"]
        )
    }

    @MainActor
    func testWindowUsesNativeToolbarTabConfiguration() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)

        XCTAssertEqual(window.title, "Scrawl Preferences")
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertFalse(window.styleMask.contains(.resizable), "preferences window must not be user-resizable")
        XCTAssertTrue(controller.usesToolbarTabs)
        XCTAssertEqual(controller.tabSymbolNames.count, 5)
    }

    @MainActor
    func testTabSelectionSwitchesPagesAndPersists() {
        let controller = PreferencesWindowController(actions: makeActions())

        XCTAssertEqual(controller.visibleSection, .general)
        controller.selectSection(.models)
        XCTAssertEqual(controller.visibleSection, .models)

        controller.window?.orderOut(nil)
        controller.showWindow(nil)
        XCTAssertEqual(controller.visibleSection, .models)
    }

    @MainActor
    func testGeneralUsesCompactWindowWidthAndWorkbenchPagesExpand() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertEqual(contentView.bounds.width, 560, accuracy: 0.5)

        controller.selectSection(.models)
        XCTAssertEqual(contentView.bounds.width, 740, accuracy: 0.5)

        controller.selectSection(.general)
        XCTAssertEqual(contentView.bounds.width, 560, accuracy: 0.5)
    }

    @MainActor
    func testTabSwitchesFitWindowHeightToEachPagesContent() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)
        controller.update(snapshot: makeSnapshot(
            records: [TranscriptRecord(id: UUID(), createdAt: .now, text: "A saved transcript")],
            dictionaryEntries: [DictionaryEntry(wrong: "Anduril", correct: "Anduril")],
            modelRows: [
                PreferencesModelRow(
                    id: "tiny.en", displayName: "Tiny (English)",
                    isInstalled: true, isSelected: true,
                    isDownloading: false, isCancelled: false, downloadProgressText: nil
                ),
                PreferencesModelRow(
                    id: "ggml-medium", displayName: "Medium",
                    isInstalled: false, isSelected: false,
                    isDownloading: false, isCancelled: false, downloadProgressText: nil
                ),
            ]
        ))

        controller.selectSection(.models)
        let modelsHeight = contentView.bounds.height

        controller.selectSection(.about)
        let aboutHeight = contentView.bounds.height
        XCTAssertLessThan(
            aboutHeight, modelsHeight - 100,
            "About has far less content and must get a correspondingly shorter window"
        )

        controller.selectSection(.general)
        XCTAssertEqual(contentView.bounds.width, 560, accuracy: 0.5)
        XCTAssertGreaterThan(contentView.bounds.height, aboutHeight)
    }

    @MainActor
    func testContentUpdatesAdjustWindowHeightForVisiblePage() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)
        controller.selectSection(.dictionary)
        let sparseHeight = contentView.bounds.height

        controller.update(snapshot: makeSnapshot(dictionaryEntries: (1 ... 12).map {
            DictionaryEntry(wrong: "term \($0)", correct: "term \($0)")
        }))

        XCTAssertGreaterThan(
            contentView.bounds.height, sparseHeight,
            "a fuller list must grow the fixed (non-user-resizable) window to fit"
        )
    }

    @MainActor
    func testToolbarTabsUseOnlyApprovedSFSymbolNames() {
        let controller = PreferencesWindowController(actions: makeActions())

        XCTAssertEqual(
            controller.tabSymbolNames,
            ["gearshape", "cpu", "text.book.closed", "clock.arrow.circlepath", "info.circle"]
        )
    }

    @MainActor
    func testWindowUsesNativeToolbarTabs() {
        let controller = PreferencesWindowController(actions: makeActions())

        XCTAssertTrue(controller.usesToolbarTabs)
    }

    @MainActor
    func testModelsPageHasUnambiguousLayoutAtFixedWindowSize() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        controller.selectSection(.models)
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertFalse(controller.visibleSectionHasAmbiguousLayout)
        XCTAssertTrue(controller.isVisibleSectionWithinContentBounds)
        XCTAssertTrue(controller.isVisibleSectionCriticalContentWithinBounds)
    }

    @MainActor
    func testModelsPageUsesTopAnchoredTwoLineRowsWithSelectedAction() {
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
        // The mockup keeps a "Use" button on every installed row, including the selected one.
        XCTAssertTrue(controller.modelsSelectedRowHasAction)
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
    func testGroupedPreferencesSurfacesUseSubtleBorders() {
        let view = PreferencesPageSupport.makeRoundedBackground()

        view.updateLayer()

        XCTAssertLessThanOrEqual(view.layer?.borderWidth ?? 0, 0.5)
    }

    @MainActor
    func testCustomPreferencesSelectionKeepsNormalTextBackgroundStyle() {
        let row = PreferencesSelectionRowView()
        row.isSelected = true
        row.isEmphasized = true
        row.selectionHighlightStyle = .regular

        XCTAssertEqual(row.interiorBackgroundStyle, .normal)
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
    func testPreferencePagesPaintNativeWindowBackground() {
        let page = PreferencesPageSupport.makePage(
            title: "General",
            description: "Readiness and defaults.",
            content: []
        )

        XCTAssertTrue(page is PreferencesBackgroundView)
    }

    @MainActor
    func testPinnedActionBarsDefaultToSharedRowGrid() {
        let button = NSButton(title: "Edit", target: nil, action: nil)
        PreferencesPageSupport.configureSecondaryButton(button)
        let actionBar = PreferencesPageSupport.makePinnedActionBar(leading: [button], trailing: [])
        actionBar.frame = NSRect(x: 0, y: 0, width: 360, height: 44)
        actionBar.layoutSubtreeIfNeeded()

        let contentMinX = actionBar.subviews.first?.subviews.first?.frame.minX ?? -1
        XCTAssertEqual(contentMinX, PreferencesPageSupport.rowInset, accuracy: 0.5)
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
    func testHistoryPageHasUnambiguousLayoutAtFixedWindowSize() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
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
    func testHistoryAddTermPopoverSavesPreferredTerm() throws {
        let record = TranscriptRecord(id: UUID(), createdAt: .now, text: "Anduril was mentioned")
        var savedValue: String?
        let controller = PreferencesWindowController(actions: makeActions(
            saveDictionaryEntry: { _, _, correct, completion in
                savedValue = correct
                completion(.success(()))
            }
        ))
        controller.update(snapshot: makeSnapshot(records: [record]))
        controller.selectSection(.history)
        let contentView = try XCTUnwrap(controller.window?.contentView)

        try XCTUnwrap(contentView.button(titled: "Add Term...")).performClick(nil)
        controller.setHistoryPreferredTermDraft("Anduril")
        controller.saveHistoryPreferredTermDraft()

        XCTAssertEqual(savedValue, "Anduril")
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
    func testHistoryToggleRevertsWhenDisableIsCancelledAndSameSnapshotReapplies() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let snapshot = makeSnapshot(isHistoryEnabled: true)
        controller.update(snapshot: snapshot)
        controller.selectSection(.history)
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let toggle = try XCTUnwrap(contentView.button(titled: "Save transcript history"))

        toggle.performClick(nil)
        XCTAssertEqual(toggle.state, .off)

        controller.update(snapshot: snapshot)

        XCTAssertEqual(toggle.state, .on)
    }

    @MainActor
    func testGeneralAndAboutButtonsDispatchActions() throws {
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

        // Microphone, Accessibility, and the hotkey control now all live on General (the
        // default tab), so no section switch is needed before clicking them.
        try XCTUnwrap(contentView.button(titled: "Request")).performClick(nil)
        try XCTUnwrap(contentView.button(titled: "Open Prompt")).performClick(nil)
        try XCTUnwrap(contentView.button(titled: "Set Hotkey…")).performClick(nil)
        controller.selectSection(.about)
        try XCTUnwrap(contentView.button(titled: "Open Project Page")).performClick(nil)

        XCTAssertTrue(requestedMicrophone)
        XCTAssertTrue(requestedAccessibility)
        XCTAssertTrue(requestedHotkey)
        XCTAssertTrue(openedProjectPage)
    }

    @MainActor
    func testGeneralSettingTitlesShareLeadingEdge() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot())
        let contentView = try XCTUnwrap(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()

        let titleMinXs = try ["Hotkey", "Offload model", "Microphone", "Accessibility"].map { title -> CGFloat in
            let field = try XCTUnwrap(contentView.textField(withValue: title))
            return contentView.convert(field.bounds, from: field).minX.rounded()
        }

        XCTAssertEqual(Set(titleMinXs).count, 1)
    }

    @MainActor
    func testGeneralAvoidsDuplicateReadinessSummary() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot())
        let contentView = try XCTUnwrap(controller.window?.contentView)

        XCTAssertNotNil(contentView.textField(withValue: "Hotkey, permissions, and defaults."))
        XCTAssertNil(contentView.textField(withValue: "Readiness"))
        XCTAssertNil(contentView.textField(withValue: "Readiness and defaults."))
    }

    @MainActor
    func testGeneralButtonsShareTrailingEdge() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot())
        let contentView = try XCTUnwrap(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()

        let controls: [NSView] = [
            try XCTUnwrap(contentView.button(titled: "Set Hotkey…")),
            try XCTUnwrap(contentView.button(titled: "Open Prompt")),
        ]
        let trailingEdges = controls.map { control in
            contentView.convert(control.frame, from: control.superview).maxX.rounded()
        }

        let maxTrailingEdge = try XCTUnwrap(trailingEdges.max())
        let minTrailingEdge = try XCTUnwrap(trailingEdges.min())
        let spread = maxTrailingEdge - minTrailingEdge
        XCTAssertLessThanOrEqual(spread, 2)
    }

    @MainActor
    func testGeneralOffloadPopupAlignsUnderHotkeyValue() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot())
        let contentView = try XCTUnwrap(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()

        let hotkeyValue = try XCTUnwrap(contentView.textField(withValue: "Right ⌥ Option"))
        let offloadPopup = try XCTUnwrap(contentView.popupButton(selectedTitle: "5 minutes"))
        let hotkeyMinX = contentView.convert(hotkeyValue.bounds, from: hotkeyValue).minX.rounded()
        let offloadMinX = contentView.convert(offloadPopup.frame, from: offloadPopup.superview).minX.rounded()

        XCTAssertEqual(offloadMinX, hotkeyMinX, accuracy: 2)
    }

    @MainActor
    func testGeneralHotkeyHelpDoesNotAddVisibleRow() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot())
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let hotkeyButton = try XCTUnwrap(contentView.button(titled: "Set Hotkey…"))
        let hotkeyValue = try XCTUnwrap(contentView.textField(withValue: "Right ⌥ Option"))
        let tooltip = "Hold to dictate. Double-tap to lock recording."

        XCTAssertNil(contentView.textField(withValue: tooltip))
        XCTAssertNil(contentView.textField(withValue: """
        Hold the hotkey while speaking, then release to transcribe. \
        Double-tap to keep recording hands-free, then tap again to stop.
        """))
        XCTAssertEqual(hotkeyButton.toolTip, tooltip)
        XCTAssertEqual(hotkeyValue.toolTip, tooltip)
    }

    @MainActor
    func testGeneralOptionsUseCompactRows() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot())
        let contentView = try XCTUnwrap(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()

        let clipboard = try XCTUnwrap(contentView.button(titled: "Keep transcripts in clipboard history"))
        let launch = try XCTUnwrap(contentView.button(titled: "Launch at login"))
        XCTAssertNil(contentView.textField(withValue: "Allows clipboard managers to save your dictations"))
        XCTAssertNil(contentView.textField(withValue: "Start Scrawl automatically when you sign in."))
        XCTAssertEqual(clipboard.toolTip, "Allows clipboard managers to save your dictations.")
        XCTAssertEqual(launch.toolTip, "Start Scrawl automatically when you sign in.")

        let clipboardFrame = contentView.convert(clipboard.frame, from: clipboard.superview)
        let launchFrame = contentView.convert(launch.frame, from: launch.superview)
        XCTAssertLessThanOrEqual(abs(clipboardFrame.midY - launchFrame.midY), 44)
    }

    @MainActor
    func testGeneralPermissionStatusColorsStaySubtle() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot(
            microphoneStatus: .authorized,
            accessibilityStatus: .denied
        ))
        let contentView = try XCTUnwrap(controller.window?.contentView)

        let authorized = try XCTUnwrap(contentView.textField(withValue: "Authorized"))
        let denied = try XCTUnwrap(contentView.textField(withValue: "Denied"))

        XCTAssertFalse(authorized.textColor?.isEqual(NSColor.systemGreen) ?? false)
        XCTAssertFalse(denied.textColor?.isEqual(NSColor.systemRed) ?? false)
    }

    @MainActor
    func testDictionaryVisibleCopyUsesNewName() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let contentView = try XCTUnwrap(controller.window?.contentView)

        controller.selectSection(.dictionary)
        XCTAssertNotNil(contentView.textField(withValue: "Dictionary"))
        XCTAssertNil(contentView.textField(withValue: "Vocabulary"))
    }

    @MainActor
    func testModelsAddAndRevealButtonsDispatchActionsWithoutFindModels() throws {
        var addedModel = false
        var revealedFolder = false
        let controller = PreferencesWindowController(actions: makeActions(
            addModel: { addedModel = true },
            revealModelsFolder: { revealedFolder = true }
        ))
        let contentView = try XCTUnwrap(controller.window?.contentView)

        controller.selectSection(.models)
        try XCTUnwrap(contentView.button(titled: "Add Model…")).performClick(nil)
        try XCTUnwrap(contentView.button(titled: "Reveal Models Folder")).performClick(nil)

        XCTAssertTrue(addedModel)
        XCTAssertTrue(revealedFolder)
        XCTAssertNil(contentView.button(titled: "Find Models"))
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
    func testDictionaryPageFiltersPreferredTermsAndFallsBackToFirstSelection() {
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
        try XCTUnwrap(contentView.button(titled: "Reset Dictionary")).performClick(nil)
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
    func testDictionaryPageHasUnambiguousLayoutAtFixedWindowSize() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
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
    func testEverySettingsPageFitsAtFixedWindowSize() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
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
    func testListPageTableScrollViewsDoNotRubberBandVertically() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let contentView = try XCTUnwrap(controller.window?.contentView)
        controller.update(snapshot: makeSnapshot(
            records: [TranscriptRecord(id: UUID(), createdAt: .now, text: "A saved transcript")],
            dictionaryEntries: [DictionaryEntry(wrong: "Anduril", correct: "Anduril")]
        ))

        for section in [PreferencesWindowController.Section.dictionary, .history] {
            controller.selectSection(section)
            let scrollView = try XCTUnwrap(contentView.visibleTableScrollView(), "\(section.title) missing table scroll view")

            XCTAssertEqual(scrollView.verticalScrollElasticity, .none, "\(section.title) table should not rubber-band")
        }
    }

    @MainActor
    func testWorkbenchActionBarsShareLeadingGrid() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        controller.update(snapshot: makeSnapshot(
            records: [TranscriptRecord(id: UUID(), createdAt: .now, text: "A saved transcript")],
            dictionaryEntries: [DictionaryEntry(wrong: "Anduril", correct: "Anduril")],
            modelRows: [
                PreferencesModelRow(
                    id: ModelCatalog.parakeetModelID,
                    displayName: "Parakeet v3",
                    isInstalled: true,
                    isSelected: true,
                    isDownloading: false,
                    isCancelled: false,
                    downloadProgressText: nil
                ),
            ]
        ))

        let expectedMinX = PreferencesPageSupport.pageHorizontalInset + PreferencesPageSupport.rowInset
        for section in [PreferencesWindowController.Section.models, .dictionary, .history] {
            controller.selectSection(section)
            window.contentView?.layoutSubtreeIfNeeded()

            let contentStack = try XCTUnwrap(window.contentView?.firstLeadingStackInPinnedActionBar(), "\(section.title) missing action bar stack")
            let contentMinX = window.contentView?.convert(contentStack.frame, from: contentStack.superview).minX ?? -1
            XCTAssertEqual(contentMinX, expectedMinX, accuracy: 0.5, "\(section.title) action bar is off-grid")
        }
    }

    @MainActor
    func testHistoryUsesPinnedWorkbenchActionBar() {
        let controller = PreferencesWindowController(actions: makeActions())

        XCTAssertTrue(controller.historyUsesPinnedActionBar)
    }

    @MainActor
    func testWorkbenchPageDescriptionsAreCompact() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let contentView = try XCTUnwrap(controller.window?.contentView)

        // Every page — Models included — now carries a compact subtitle under its title;
        // the model picker and filter live in a toolbar strip below the header.
        controller.selectSection(.models)
        XCTAssertNotNil(contentView.textField(withValue: "On-device transcription models."))
        controller.selectSection(.dictionary)
        XCTAssertNotNil(contentView.textField(withValue: "Preferred terms for names and phrases."))
        XCTAssertNil(contentView.textField(withValue: "Preferred names, terms, and phrases that help Whisper recognize your language."))
    }

    @MainActor
    func testDictionaryUsesPinnedActionBarAndNewSearchPlaceholder() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        controller.update(snapshot: makeSnapshot(dictionaryEntries: [
            DictionaryEntry(wrong: "Anduril", correct: "Anduril"),
        ]))
        controller.selectSection(.dictionary)
        let contentView = try XCTUnwrap(controller.window?.contentView)

        XCTAssertTrue(controller.dictionaryUsesPinnedActionBar)
        XCTAssertNotNil(contentView.textField(withPlaceholder: "Search dictionary"))
        XCTAssertNil(contentView.textField(withPlaceholder: "Search vocabulary"))
    }

    @MainActor
    func testDictionaryAddButtonDispatchesAction() throws {
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
    func testDictionaryReturnKeyAddsPreferredTerm() throws {
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

        field.sendAction(field.action, to: field.target)

        XCTAssertEqual(savedValue, "Anduril")
    }

    @MainActor
    func testDictionaryEditAndDeleteButtonsDispatchActions() throws {
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
        launchAtLoginEnabled: Bool = false,
        microphoneStatus: PermissionStatus = .notDetermined,
        accessibilityStatus: PermissionStatus = .notDetermined
    ) -> PreferencesWindowController.Snapshot {
        PreferencesWindowController.Snapshot(
            settings: AppSettings(
                isTranscriptHistoryEnabled: isHistoryEnabled,
                modelOffloadPolicy: modelOffloadPolicy,
                keepTranscriptsInClipboardHistory: keepTranscriptsInClipboardHistory
            ),
            downloadableModels: [],
            modelRows: modelRows,
            microphoneStatus: microphoneStatus,
            accessibilityStatus: accessibilityStatus,
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

    func popupButton(selectedTitle title: String) -> NSPopUpButton? {
        if let popup = self as? NSPopUpButton, popup.titleOfSelectedItem == title, !popup.isEffectivelyHidden {
            return popup
        }
        return subviews.lazy.compactMap { $0.popupButton(selectedTitle: title) }.first
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

    func textField(withValue value: String) -> NSTextField? {
        if let field = self as? NSTextField, field.stringValue == value, !field.isEffectivelyHidden {
            return field
        }
        return subviews.lazy.compactMap { $0.textField(withValue: value) }.first
    }

    func firstLeadingStackInPinnedActionBar() -> NSView? {
        if self is PreferencesPinnedActionBarView {
            return subviews.first?.subviews.first
        }
        return subviews.lazy.compactMap { $0.firstLeadingStackInPinnedActionBar() }.first
    }

    func visibleTableScrollView() -> NSScrollView? {
        if let scrollView = self as? NSScrollView,
           scrollView.documentView is NSTableView,
           !scrollView.isEffectivelyHidden
        {
            return scrollView
        }
        return subviews.lazy.compactMap { $0.visibleTableScrollView() }.first
    }

    var isEffectivelyHidden: Bool {
        isHidden || superview?.isEffectivelyHidden == true
    }
}
