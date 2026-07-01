import AppKit
import DictionaryStore
import Permissions
import SettingsStore
import TranscriptHistoryStore

/// Hosts a preferences page NSView inside a view controller so `NSTabViewController`
/// can own it. A fixed `preferredContentSize` keeps the window stable across tabs
/// (a tall Models list and a short About page report the same size, so switching
/// tabs never resizes the window) — list pages scroll internally instead.
private final class PreferencesPageViewController: NSViewController {
    private let pageView: NSView

    init(pageView: NSView, preferredSize: NSSize) {
        self.pageView = pageView
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = preferredSize
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = pageView
    }
}

final class PreferencesWindowController: NSWindowController {
    struct Actions {
        let selectModel: (String) -> Void
        let downloadModel: (DownloadableModel) -> Void
        let deleteSelectedModel: () -> Void
        let cancelDownload: () -> Void
        let addModel: () -> Void
        let revealModelsFolder: () -> Void
        let openModelSource: () -> Void
        let setHotkey: () -> Void
        let requestMicrophone: () -> Void
        let requestAccessibility: () -> Void
        let setModelOffloadPolicy: (ModelOffloadPolicy) -> Void
        let setKeepTranscriptsInClipboardHistory: (Bool) -> Void
        let setLaunchAtLogin: (Bool) -> Void
        let setTranscriptHistoryEnabled: (Bool) -> Void
        let copyTranscript: (UUID) -> Void
        let repasteTranscript: (UUID) -> Void
        let deleteTranscripts: (Set<UUID>) -> Void
        let saveDictionaryEntry: (String?, String, String, @escaping (Result<Void, Error>) -> Void) -> Void
        let deleteDictionaryEntries: (Set<String>, @escaping (Result<Void, Error>) -> Void) -> Void
        let recoverDictionary: (@escaping (Result<Void, Error>) -> Void) -> Void
        let openProjectPage: () -> Void
    }

    struct Snapshot {
        let settings: AppSettings
        let downloadableModels: [DownloadableModel]
        let modelRows: [PreferencesModelRow]
        let microphoneStatus: PermissionStatus
        let accessibilityStatus: PermissionStatus
        let isCapturingHotkey: Bool
        let isModelDownloadInProgress: Bool
        /// Non-nil while a download is active, e.g. "25% (412/1621 MB)".
        let downloadProgressText: String?
        let transcriptHistory: [TranscriptRecord]
        let transcriptHistoryLoadErrorDescription: String?
        let dictionaryEntries: [DictionaryEntry]
        let dictionaryLoadErrorDescription: String?
        let launchAtLoginEnabled: Bool
    }

    /// One tab in the native toolbar-tab window. Raw value is the tab index.
    enum Section: Int, CaseIterable {
        case general
        case models
        case dictionary
        case history
        case about

        var title: String {
            switch self {
            case .general: "General"
            case .models: "Models"
            case .dictionary: "Dictionary"
            case .history: "History"
            case .about: "About"
            }
        }

        var symbolName: String {
            switch self {
            case .general: "gearshape"
            case .models: "cpu"
            case .dictionary: "text.book.closed"
            case .history: "clock.arrow.circlepath"
            case .about: "info.circle"
            }
        }
    }

    private let generalView: PreferencesGeneralView
    private let modelsView: PreferencesModelsView
    private let historyView: PreferencesHistoryView
    private let dictionaryView: PreferencesDictionaryView
    private let aboutView: PreferencesAboutView
    private let tabController = NSTabViewController()
    private var sectionViews: [Section: NSView] = [:]
    private var didCenterWindow = false

    var visibleSection: Section {
        Section(rawValue: tabController.selectedTabViewItemIndex) ?? .general
    }

    var isVisibleSectionWithinContentBounds: Bool {
        sectionViews[visibleSection] != nil
    }

    var visibleSectionHasAmbiguousLayout: Bool {
        sectionViews[visibleSection]?.hasAmbiguousLayout ?? true
    }

    var isVisibleSectionCriticalContentWithinBounds: Bool {
        switch visibleSection {
        case .models:
            modelsView.isCriticalContentWithinBounds
        case .history:
            historyView.areActionControlsWithinBounds
        default:
            true
        }
    }

    /// SF Symbol names shown on the toolbar tabs, in tab order.
    var tabSymbolNames: [String] {
        Section.allCases.map(\.symbolName)
    }

    var usesToolbarTabs: Bool {
        tabController.tabStyle == .toolbar
    }

    var historyState: PreferencesHistoryView.State {
        historyView.state
    }

    var historyVisibleRecordIDs: [UUID] {
        historyView.visibleRecordIDs
    }

    var historySelectedRecordID: UUID? {
        historyView.selectedRecordID
    }

    var dictionaryState: PreferencesDictionaryView.State {
        dictionaryView.state
    }

    var dictionaryVisibleWrongValues: [String] {
        dictionaryView.visibleWrongValues
    }

    var dictionarySelectedWrong: String? {
        dictionaryView.selectedWrong
    }

    var historyUsesGroupedWorkspace: Bool {
        historyView.usesGroupedWorkspace
    }

    var historyUsesPinnedActionBar: Bool {
        historyView.usesPinnedActionBar
    }

    var historyRowsAreTranscriptFirst: Bool {
        historyView.visibleRowsAreTranscriptFirst
    }

    var historyTranscriptTextIsLeftAligned: Bool {
        historyView.visibleTranscriptTextIsLeftAligned
    }

    var historyVisibleMetrics: [String] {
        historyView.visibleMetrics
    }

    var dictionaryUsesGroupedWorkspace: Bool {
        dictionaryView.usesGroupedWorkspace
    }

    var dictionaryUsesPinnedActionBar: Bool {
        dictionaryView.usesPinnedActionBar
    }

    var modelsListIsTopAnchored: Bool {
        modelsView.listIsTopAnchored
    }

    var modelsTwoLineRowCount: Int {
        modelsView.visibleTwoLineRowCount
    }

    var modelsSelectedRowHasAction: Bool {
        modelsView.visibleSelectedRowHasAction
    }

    var generalModelOffloadChoices: [String] {
        generalView.modelOffloadChoices
    }

    var generalSelectedModelOffloadPolicy: ModelOffloadPolicy? {
        generalView.selectedModelOffloadPolicy
    }

    var generalIsClipboardHistoryEnabled: Bool {
        generalView.isClipboardHistoryEnabled
    }

    var generalLaunchAtLoginEnabled: Bool {
        generalView.isLaunchAtLoginEnabled
    }

    init(actions: Actions) {
        generalView = PreferencesGeneralView(
            setHotkey: actions.setHotkey,
            requestMicrophone: actions.requestMicrophone,
            requestAccessibility: actions.requestAccessibility,
            setModelOffloadPolicy: actions.setModelOffloadPolicy,
            setKeepTranscriptsInClipboardHistory: actions.setKeepTranscriptsInClipboardHistory,
            setLaunchAtLogin: actions.setLaunchAtLogin
        )
        modelsView = PreferencesModelsView(
            selectModel: actions.selectModel,
            downloadModel: actions.downloadModel,
            deleteSelectedModel: actions.deleteSelectedModel,
            cancelDownload: actions.cancelDownload,
            addModel: actions.addModel,
            revealModelsFolder: actions.revealModelsFolder,
            openModelSource: actions.openModelSource
        )
        historyView = PreferencesHistoryView(actions: .init(
            setEnabled: actions.setTranscriptHistoryEnabled,
            copy: actions.copyTranscript,
            repaste: actions.repasteTranscript,
            delete: actions.deleteTranscripts,
            addTerm: { term, completion in
                actions.saveDictionaryEntry(nil, term, term, completion)
            }
        ))
        dictionaryView = PreferencesDictionaryView(actions: .init(
            save: actions.saveDictionaryEntry,
            delete: actions.deleteDictionaryEntries,
            recover: actions.recoverDictionary
        ))
        aboutView = PreferencesAboutView(openProjectPage: actions.openProjectPage)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 512),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Scrawl Preferences"
        window.isReleasedWhenClosed = false
        // The toolbar tab strip claims vertical space the old sidebar didn't, so the
        // minimum window is a little taller to leave the pages the same room to breathe.
        window.minSize = NSSize(width: 620, height: 480)
        window.identifier = NSUserInterfaceItemIdentifier("ScrawlPreferencesWindow")

        super.init(window: window)
        setupTabs()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if !didCenterWindow {
            window?.center()
            didCenterWindow = true
        }
        window?.makeKeyAndOrderFront(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func update(snapshot: Snapshot) {
        generalView.update(
            settings: snapshot.settings,
            microphoneStatus: snapshot.microphoneStatus,
            accessibilityStatus: snapshot.accessibilityStatus,
            isCapturingHotkey: snapshot.isCapturingHotkey,
            launchAtLoginEnabled: snapshot.launchAtLoginEnabled
        )
        modelsView.update(
            rows: snapshot.modelRows,
            downloadableModels: snapshot.downloadableModels,
            isDownloadInProgress: snapshot.isModelDownloadInProgress
        )
        historyView.update(
            records: snapshot.transcriptHistory,
            isEnabled: snapshot.settings.isTranscriptHistoryEnabled,
            loadErrorDescription: snapshot.transcriptHistoryLoadErrorDescription
        )
        dictionaryView.update(
            entries: snapshot.dictionaryEntries,
            loadErrorDescription: snapshot.dictionaryLoadErrorDescription
        )
    }

    func selectGeneralModelOffloadPolicy(_ policy: ModelOffloadPolicy) {
        generalView.selectModelOffloadPolicy(policy)
    }

    func selectSection(_ section: Section) {
        tabController.selectedTabViewItemIndex = section.rawValue
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    func setHistorySearchQuery(_ query: String) {
        historyView.setSearchQuery(query)
    }

    func setHistoryPreferredTermDraft(_ value: String) {
        historyView.setPreferredTermDraft(value)
    }

    func saveHistoryPreferredTermDraft() {
        historyView.savePreferredTermDraft()
    }

    func setDictionarySearchQuery(_ query: String) {
        dictionaryView.setSearchQuery(query)
    }

    private func setupTabs() {
        sectionViews = [
            .general: generalView,
            .models: modelsView,
            .dictionary: dictionaryView,
            .history: historyView,
            .about: aboutView,
        ]

        tabController.tabStyle = .toolbar
        // A fixed content size across every tab is what keeps the window from resizing
        // as you switch pages (Codex's one design caution). List pages scroll internally.
        let preferredSize = NSSize(width: 740, height: 468)
        for section in Section.allCases {
            guard let view = sectionViews[section] else { continue }
            let pageController = PreferencesPageViewController(pageView: view, preferredSize: preferredSize)
            let item = NSTabViewItem(viewController: pageController)
            item.label = section.title
            item.image = NSImage(systemSymbolName: section.symbolName, accessibilityDescription: section.title)
            tabController.addTabViewItem(item)
        }

        window?.contentViewController = tabController
        tabController.selectedTabViewItemIndex = Section.general.rawValue
        // NSTabViewController can push the selected page's title onto the window; keep our own.
        window?.title = "Scrawl Preferences"
    }
}
