import AppKit
import DictionaryStore
import Permissions
import SettingsStore
import TranscriptHistoryStore

/// Hosts a preferences page NSView inside a view controller so `NSTabViewController`
/// can own it. Window sizing is handled by `PreferencesWindowController`; child
/// controllers deliberately avoid preferred-size hints so tab switches do not
/// reset the user's current window height.
private final class PreferencesPageViewController: NSViewController {
    private let pageView: NSView

    init(pageView: NSView) {
        self.pageView = pageView
        super.init(nibName: nil, bundle: nil)
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
    private var tabSelectionObservation: NSKeyValueObservation?
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

        // Fixed-size window: every page has a designed size (compact General, wider
        // workbench pages), so user resizing only creates layouts nobody designed.
        let window = NSWindow(
            // Nominal size; the post-setup resize snaps to the General page's fitted size.
            contentRect: NSRect(x: 0, y: 0, width: Section.general.windowContentWidth, height: 512),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Scrawl Preferences"
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("ScrawlPreferencesWindow")

        super.init(window: window)
        setupTabs()
        // Assigning contentViewController lets AppKit shrink the window to the tab
        // view's fitting size; snap back to the selected section's designed size.
        resizeWindowForSelectedSection(animated: false)
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
        // Content changes move a page's natural height (lists hug their rows); the
        // user can't resize the fixed window, so it follows the visible page.
        resizeWindowForSelectedSection(animated: window?.isVisible == true)
    }

    func selectGeneralModelOffloadPolicy(_ policy: ModelOffloadPolicy) {
        generalView.selectModelOffloadPolicy(policy)
    }

    func selectSection(_ section: Section) {
        tabController.selectedTabViewItemIndex = section.rawValue
        // On a visible window the tab-selection observation already animates the
        // resize; a second, instant resize here would snap-cancel that motion. On a
        // hidden window (tests, restoration) transitions don't animate reliably, so
        // resize deterministically.
        if window?.isVisible != true {
            resizeWindowForSelectedSection(animated: false)
        }
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
        for section in Section.allCases {
            guard let view = sectionViews[section] else { continue }
            let pageController = PreferencesPageViewController(pageView: view)
            let item = NSTabViewItem(viewController: pageController)
            item.label = section.title
            item.image = NSImage(systemSymbolName: section.symbolName, accessibilityDescription: section.title)
            tabController.addTabViewItem(item)
        }

        window?.contentViewController = tabController
        tabSelectionObservation = tabController.observe(\.selectedTabViewItemIndex, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            self.resizeWindowForSelectedSection(animated: self.window?.isVisible == true)
            self.window?.title = "Scrawl Preferences"
        }
        tabController.selectedTabViewItemIndex = Section.general.rawValue
        // NSTabViewController can push the selected page's title onto the window; keep our own.
        window?.title = "Scrawl Preferences"
    }

    /// Classic macOS preferences sizing: the user cannot resize the window, so each
    /// page resizes it instead — designed width per section, height fitted to that
    /// page's content (About stays small, list pages take the room their rows need).
    private func resizeWindowForSelectedSection(animated: Bool) {
        guard let window, let contentView = window.contentView else { return }
        guard let pageView = sectionViews[visibleSection] else { return }
        let contentSize = NSSize(
            width: visibleSection.windowContentWidth,
            height: max(pageView.fittingSize.height, 260)
        )
        let currentSize = contentView.bounds.size
        guard abs(currentSize.width - contentSize.width) > 0.5 ||
            abs(currentSize.height - contentSize.height) > 0.5
        else {
            return
        }

        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        let currentFrame = window.frame
        let targetFrame = NSRect(
            x: currentFrame.midX - frameSize.width / 2,
            y: currentFrame.maxY - frameSize.height,
            width: frameSize.width,
            height: frameSize.height
        )
        guard animated else {
            window.setFrame(targetFrame, display: true)
            return
        }
        // `setFrame(animate: true)` is the legacy stepped resize (linear, chunky);
        // an eased animator group matches the tab crossfade and reads as one motion.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(targetFrame, display: true)
        }
    }
}

private extension PreferencesWindowController.Section {
    var windowContentWidth: CGFloat {
        switch self {
        case .general:
            560
        case .models, .dictionary, .history, .about:
            740
        }
    }
}
