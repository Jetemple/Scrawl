import AppKit
import TranscriptHistoryStore

final class PreferencesHistoryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    enum State: Equatable {
        case disabled, unavailable, empty, noSearchResults, records
    }

    struct Actions {
        let setEnabled: (Bool) -> Void
        let copy: (UUID) -> Void
        let repaste: (UUID) -> Void
        let delete: (Set<UUID>) -> Void
    }

    private let actions: Actions
    private let toggle = NSButton(checkboxWithTitle: "Save transcript history", target: nil, action: nil)
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let stateView = NSView()
    private var workspaceGroup: NSView?
    private let stateTitle = NSTextField(labelWithString: "")
    private let stateDetail = NSTextField(wrappingLabelWithString: "")
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let repasteButton = NSButton(title: "Paste Again", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private var records: [TranscriptRecord] = []
    private var visibleRecords: [TranscriptRecord] = []
    private var selectedID: UUID?
    private var isEnabled = true
    private var loadErrorDescription: String?
    private var rowsAreTranscriptFirst = true
    private var transcriptTextIsLeftAligned = true

    private(set) var state = State.empty
    var visibleRecordIDs: [UUID] { visibleRecords.map(\.id) }
    var selectedRecordID: UUID? { selectedID }
    var usesGroupedWorkspace: Bool { workspaceGroup is PreferencesBackgroundView }
    var visibleRowsAreTranscriptFirst: Bool { rowsAreTranscriptFirst }
    var visibleTranscriptTextIsLeftAligned: Bool { transcriptTextIsLeftAligned }
    var visibleMetrics: [String] { visibleRecords.map(PreferencesContentState.historyMetrics(for:)) }
    var areActionControlsWithinBounds: Bool {
        [copyButton, repasteButton, deleteButton].allSatisfy { bounds.contains(convert($0.bounds, from: $0)) }
    }

    init(actions: Actions) {
        self.actions = actions
        super.init(frame: .zero)
        buildView()
        update(records: [], isEnabled: true, loadErrorDescription: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(records: [TranscriptRecord], isEnabled: Bool, loadErrorDescription: String?) {
        self.records = records
        self.isEnabled = isEnabled
        self.loadErrorDescription = loadErrorDescription
        toggle.state = isEnabled ? .on : .off
        applyFilter()
    }

    func setSearchQuery(_ query: String) {
        searchField.stringValue = query
        applyFilter()
    }

    func controlTextDidChange(_ obj: Notification) { applyFilter() }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleRecords.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard visibleRecords.indices.contains(row) else { return 72 }
        let width = max(260, tableView.bounds.width - 28)
        let text = visibleRecords[row].text as NSString
        let textHeight = text.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        ).height
        return max(76, ceil(textHeight) + 50)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleRecords.indices.contains(row) else { return nil }
        let record = visibleRecords[row]
        let cell = NSTableCellView()
        let text = NSTextField(wrappingLabelWithString: record.text)
        text.font = .systemFont(ofSize: 13)
        text.alignment = .left
        text.maximumNumberOfLines = 0

        let time = NSTextField(labelWithString: DateFormatter.localizedString(
            from: record.createdAt,
            dateStyle: .medium,
            timeStyle: .short
        ))
        time.font = .systemFont(ofSize: 10, weight: .medium)
        time.textColor = .secondaryLabelColor
        let metrics = NSTextField(labelWithString: PreferencesContentState.historyMetrics(for: record))
        metrics.font = .systemFont(ofSize: 10)
        metrics.textColor = .tertiaryLabelColor
        metrics.alignment = .right
        let metadata = NSStackView(views: [time, NSView(), metrics])
        metadata.orientation = .horizontal
        metadata.alignment = .centerY
        text.translatesAutoresizingMaskIntoConstraints = false
        metadata.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.addSubview(metadata)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            text.topAnchor.constraint(equalTo: cell.topAnchor, constant: 10),
            metadata.leadingAnchor.constraint(equalTo: text.leadingAnchor),
            metadata.trailingAnchor.constraint(equalTo: text.trailingAnchor),
            metadata.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 8),
            metadata.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -9)
        ])
        rowsAreTranscriptFirst = true
        transcriptTextIsLeftAligned = text.alignment == .left
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectedID = visibleRecords.indices.contains(tableView.selectedRow) ? visibleRecords[tableView.selectedRow].id : nil
        updateActionAvailability()
    }

    private func buildView() {
        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        searchField.placeholderString = "Search transcripts"
        searchField.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.usesAutomaticRowHeights = false
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.gridStyleMask = []
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

        for button in [copyButton, repasteButton, deleteButton] {
            PreferencesPageSupport.configureSecondaryButton(button)
        }
        deleteButton.contentTintColor = .systemRed
        copyButton.target = self
        copyButton.action = #selector(copySelected(_:))
        repasteButton.target = self
        repasteButton.action = #selector(repasteSelected(_:))
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected(_:))
        stateTitle.font = .systemFont(ofSize: 15, weight: .medium)
        stateDetail.textColor = .secondaryLabelColor
        stateDetail.alignment = .center
        let stateStack = NSStackView(views: [stateTitle, stateDetail])
        stateStack.orientation = .vertical
        stateStack.alignment = .centerX
        stateStack.spacing = 5
        stateStack.translatesAutoresizingMaskIntoConstraints = false
        stateView.addSubview(stateStack)
        NSLayoutConstraint.activate([
            stateStack.centerXAnchor.constraint(equalTo: stateView.centerXAnchor),
            stateStack.centerYAnchor.constraint(equalTo: stateView.centerYAnchor)
        ])

        let workspace = PreferencesPageSupport.makeListWorkspace(scrollView: scrollView, stateView: stateView)
        workspaceGroup = workspace
        let page = PreferencesPageSupport.makePage(
            title: "History",
            description: "Recent transcripts stored only on this Mac.",
            content: [
                toggle,
                searchField,
                workspace,
                PreferencesPageSupport.makeActionRow(buttons: [copyButton, repasteButton, deleteButton])
            ]
        )
        PreferencesPageSupport.fill(self, with: page)
    }

    private func applyFilter() {
        visibleRecords = PreferencesContentState.filteredHistory(records: records, query: searchField.stringValue)
        selectedID = PreferencesContentState.resolvedHistorySelection(currentID: selectedID, visibleRecords: visibleRecords)
        tableView.reloadData()
        if let selectedID, let row = visibleRecords.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        updateState()
        updateActionAvailability()
    }

    private func updateState() {
        if !isEnabled {
            state = .disabled
            stateTitle.stringValue = "Transcript history is off"
            stateDetail.stringValue = "Turn it on to save future transcripts locally."
        } else if loadErrorDescription != nil {
            state = .unavailable
            stateTitle.stringValue = "Transcript history is unavailable"
            stateDetail.stringValue = "Scrawl could not read the saved history file."
        } else if records.isEmpty {
            state = .empty
            stateTitle.stringValue = "No transcript history yet"
            stateDetail.stringValue = "Saved transcripts will appear here."
        } else if visibleRecords.isEmpty {
            state = .noSearchResults
            stateTitle.stringValue = "No matching transcripts"
            stateDetail.stringValue = "Try a different search."
        } else {
            state = .records
        }
        stateView.isHidden = state == .records
        tableView.enclosingScrollView?.isHidden = state != .records
        searchField.isEnabled = isEnabled && loadErrorDescription == nil && !records.isEmpty
    }

    private func updateActionAvailability() {
        let enabled = selectedID != nil && state == .records
        copyButton.isEnabled = enabled
        repasteButton.isEnabled = enabled
        deleteButton.isEnabled = enabled
    }

    private func performOnSelected(_ action: (UUID) -> Void) {
        guard let selectedID else { return }
        action(selectedID)
    }

    @objc private func copySelected(_ sender: NSButton) { performOnSelected(actions.copy) }
    @objc private func repasteSelected(_ sender: NSButton) { performOnSelected(actions.repaste) }
    @objc private func deleteSelected(_ sender: NSButton) {
        guard let selectedID else { return }
        actions.delete([selectedID])
    }
    @objc private func toggleChanged(_ sender: NSButton) { actions.setEnabled(sender.state == .on) }
}
