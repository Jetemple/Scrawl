import AppKit
import DictionaryStore
import Permissions
import SettingsStore
import TranscriptHistoryStore

final class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    struct Actions {
        let selectModel: (String) -> Void
        let downloadModel: (DownloadableModel) -> Void
        let deleteSelectedModel: () -> Void
        let setHotkey: () -> Void
        let requestMicrophone: () -> Void
        let requestAccessibility: () -> Void
        let setModelOffloadPolicy: (ModelOffloadPolicy) -> Void
        let setTranscriptHistoryEnabled: (Bool) -> Void
        let copyTranscript: (UUID) -> Void
        let repasteTranscript: (UUID) -> Void
        let deleteTranscripts: (Set<UUID>) -> Void
        let saveDictionaryEntry: (String?, String, String, @escaping (Result<Void, Error>) -> Void) -> Void
        let deleteDictionaryEntries: (Set<String>, @escaping (Result<Void, Error>) -> Void) -> Void
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
        let transcriptHistory: [TranscriptRecord]
        let transcriptHistoryLoadErrorDescription: String?
        let dictionaryEntries: [DictionaryEntry]
    }

    enum Section: Int, CaseIterable {
        case general
        case models
        case keyboard
        case history
        case dictionary
        case about

        var title: String {
            switch self {
            case .general: "General"
            case .models: "Models"
            case .keyboard: "Keyboard"
            case .history: "History"
            case .dictionary: "Vocabulary"
            case .about: "About"
            }
        }

        var symbolName: String {
            switch self {
            case .general: "gearshape"
            case .models: "cpu"
            case .keyboard: "keyboard"
            case .history: "clock.arrow.circlepath"
            case .dictionary: "text.book.closed"
            case .about: "info.circle"
            }
        }
    }

    private let generalView: PreferencesGeneralView
    private let modelsView: PreferencesModelsView
    private let keyboardView: PreferencesKeyboardView
    private let historyView: PreferencesHistoryView
    private let dictionaryView: PreferencesDictionaryView
    private let aboutView: PreferencesAboutView
    private let sidebarTable = NSTableView()
    private let contentContainer = PreferencesPageSupport.makeContentBackground()
    private var sectionViews: [Section: NSView] = [:]
    private var selectedSection = Section.general
    private var didCenterWindow = false

    var visibleSection: Section {
        selectedSection
    }

    var isVisibleSectionWithinContentBounds: Bool {
        guard let view = sectionViews[selectedSection] else { return false }
        return contentContainer.bounds.contains(view.frame)
    }

    var visibleSectionHasAmbiguousLayout: Bool {
        sectionViews[selectedSection]?.hasAmbiguousLayout ?? true
    }

    var isVisibleSectionCriticalContentWithinBounds: Bool {
        switch selectedSection {
        case .models:
            modelsView.isCriticalContentWithinBounds
        case .history:
            historyView.areActionControlsWithinBounds
        case .dictionary:
            true
        default:
            true
        }
    }

    var hasDraggableSidebarDivider: Bool {
        window?.contentView?.containsSplitView ?? false
    }

    var historyState: PreferencesHistoryView.State { historyView.state }
    var historyVisibleRecordIDs: [UUID] { historyView.visibleRecordIDs }
    var historySelectedRecordID: UUID? { historyView.selectedRecordID }
    var dictionaryState: PreferencesDictionaryView.State { dictionaryView.state }
    var dictionaryVisibleWrongValues: [String] { dictionaryView.visibleWrongValues }
    var dictionarySelectedWrong: String? { dictionaryView.selectedWrong }
    var historyUsesGroupedWorkspace: Bool { historyView.usesGroupedWorkspace }
    var historyRowsAreTranscriptFirst: Bool { historyView.visibleRowsAreTranscriptFirst }
    var historyTranscriptTextIsLeftAligned: Bool { historyView.visibleTranscriptTextIsLeftAligned }
    var historyVisibleMetrics: [String] { historyView.visibleMetrics }
    var dictionaryUsesGroupedWorkspace: Bool { dictionaryView.usesGroupedWorkspace }
    var modelsListIsTopAnchored: Bool { modelsView.listIsTopAnchored }
    var modelsTwoLineRowCount: Int { modelsView.visibleTwoLineRowCount }
    var modelsSelectedRowHasAction: Bool { modelsView.visibleSelectedRowHasAction }
    var generalModelOffloadChoices: [String] { generalView.modelOffloadChoices }
    var generalSelectedModelOffloadPolicy: ModelOffloadPolicy? { generalView.selectedModelOffloadPolicy }

    init(actions: Actions) {
        generalView = PreferencesGeneralView(
            requestMicrophone: actions.requestMicrophone,
            requestAccessibility: actions.requestAccessibility,
            setModelOffloadPolicy: actions.setModelOffloadPolicy
        )
        modelsView = PreferencesModelsView(
            selectModel: actions.selectModel,
            downloadModel: actions.downloadModel,
            deleteSelectedModel: actions.deleteSelectedModel
        )
        keyboardView = PreferencesKeyboardView(setHotkey: actions.setHotkey)
        historyView = PreferencesHistoryView(actions: .init(
            setEnabled: actions.setTranscriptHistoryEnabled,
            copy: actions.copyTranscript,
            repaste: actions.repasteTranscript,
            delete: actions.deleteTranscripts
        ))
        dictionaryView = PreferencesDictionaryView(actions: .init(
            save: actions.saveDictionaryEntry,
            delete: actions.deleteDictionaryEntries
        ))
        aboutView = PreferencesAboutView(openProjectPage: actions.openProjectPage)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Scrawl"
        window.isReleasedWhenClosed = false
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 620, height: 400)
        window.identifier = NSUserInterfaceItemIdentifier("ScrawlPreferencesWindow")

        super.init(window: window)
        window.contentView = makeContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
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
            isCapturingHotkey: snapshot.isCapturingHotkey
        )
        modelsView.update(
            rows: snapshot.modelRows,
            downloadableModels: snapshot.downloadableModels,
            isDownloadInProgress: snapshot.isModelDownloadInProgress
        )
        keyboardView.update(hotkey: snapshot.settings.hotkey, isCapturing: snapshot.isCapturingHotkey)
        historyView.update(
            records: snapshot.transcriptHistory,
            isEnabled: snapshot.settings.isTranscriptHistoryEnabled,
            loadErrorDescription: snapshot.transcriptHistoryLoadErrorDescription
        )
        dictionaryView.update(entries: snapshot.dictionaryEntries)
    }

    func selectGeneralModelOffloadPolicy(_ policy: ModelOffloadPolicy) {
        generalView.selectModelOffloadPolicy(policy)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let section = Section(rawValue: row) else { return nil }
        let cell = NSTableCellView()
        let imageView = NSImageView(image: NSImage(systemSymbolName: section.symbolName, accessibilityDescription: nil) ?? NSImage())
        let label = NSTextField(labelWithString: section.title)
        label.font = .systemFont(ofSize: 13)
        imageView.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        imageView.contentTintColor = .secondaryLabelColor

        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let section = Section(rawValue: sidebarTable.selectedRow) else { return }
        selectedSection = section
        showSelectedSection()
    }

    func selectSection(_ section: Section) {
        selectedSection = section
        sidebarTable.selectRowIndexes(IndexSet(integer: section.rawValue), byExtendingSelection: false)
        showSelectedSection()
    }

    func setHistorySearchQuery(_ query: String) {
        historyView.setSearchQuery(query)
    }

    func setDictionarySearchQuery(_ query: String) {
        dictionaryView.setSearchQuery(query)
    }

    private func makeContentView() -> NSView {
        sectionViews = [
            .general: generalView,
            .models: modelsView,
            .keyboard: keyboardView,
            .history: historyView,
            .dictionary: dictionaryView,
            .about: aboutView
        ]

        let sidebar = makeSidebar()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        for (section, view) in sectionViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isHidden = section != selectedSection
            contentContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
            ])
        }

        let root = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)
        root.addSubview(divider)
        root.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            sidebar.widthAnchor.constraint(equalToConstant: 150),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: root.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        return root
    }

    private func makeSidebar() -> NSView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        column.resizingMask = .autoresizingMask
        sidebarTable.addTableColumn(column)
        sidebarTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        sidebarTable.headerView = nil
        sidebarTable.rowHeight = 30
        sidebarTable.style = .sourceList
        sidebarTable.backgroundColor = .clear
        sidebarTable.dataSource = self
        sidebarTable.delegate = self

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.documentView = sidebarTable
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor)
        ])

        sidebarTable.selectRowIndexes(IndexSet(integer: selectedSection.rawValue), byExtendingSelection: false)
        return sidebar
    }

    private func showSelectedSection() {
        for (section, view) in sectionViews {
            view.isHidden = section != selectedSection
        }
    }
}

private extension NSView {
    var containsSplitView: Bool {
        self is NSSplitView || subviews.contains(where: \.containsSplitView)
    }
}
