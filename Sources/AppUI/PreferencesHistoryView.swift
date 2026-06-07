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
    private let stateTitle = NSTextField(labelWithString: "")
    private let stateDetail = NSTextField(wrappingLabelWithString: "")
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let repasteButton = NSButton(title: "Paste Again", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private var actionRetainers: [ClosureAction] = []
    private var records: [TranscriptRecord] = []
    private var visibleRecords: [TranscriptRecord] = []
    private var selectedID: UUID?
    private var isEnabled = true
    private var loadErrorDescription: String?

    private(set) var state = State.empty
    var visibleRecordIDs: [UUID] { visibleRecords.map(\.id) }
    var selectedRecordID: UUID? { selectedID }
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
        return max(74, ceil(textHeight) + 48)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleRecords.indices.contains(row) else { return nil }
        let record = visibleRecords[row]
        let cell = NSTableCellView()
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
        let metadata = NSStackView(views: [time, NSView(), metrics])
        metadata.orientation = .horizontal
        let text = NSTextField(wrappingLabelWithString: record.text)
        text.font = .systemFont(ofSize: 13)
        text.maximumNumberOfLines = 0
        let stack = NSStackView(views: [metadata, text])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            stack.topAnchor.constraint(equalTo: cell.topAnchor),
            stack.bottomAnchor.constraint(equalTo: cell.bottomAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectedID = visibleRecords.indices.contains(tableView.selectedRow) ? visibleRecords[tableView.selectedRow].id : nil
        updateActionAvailability()
    }

    private func buildView() {
        let header = PreferencesPageSupport.makePageHeader(
            title: "History",
            description: "Recent transcripts stored only on this Mac."
        )
        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        searchField.placeholderString = "Search transcripts"
        searchField.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.usesAutomaticRowHeights = false
        tableView.intercellSpacing = NSSize(width: 0, height: 6)
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

        for button in [copyButton, repasteButton, deleteButton] {
            PreferencesPageSupport.configureSecondaryButton(button)
        }
        deleteButton.contentTintColor = .systemRed
        bind(copyButton) { [weak self] in self?.performOnSelected(self?.actions.copy) }
        bind(repasteButton) { [weak self] in self?.performOnSelected(self?.actions.repaste) }
        bind(deleteButton) { [weak self] in
            guard let id = self?.selectedID else { return }
            self?.actions.delete([id])
        }
        let buttons = NSStackView(views: [copyButton, repasteButton, deleteButton, NSView()])
        buttons.orientation = .horizontal
        buttons.spacing = 6

        stateTitle.font = .systemFont(ofSize: 15, weight: .medium)
        stateDetail.textColor = .secondaryLabelColor
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

        let workspace = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stateView.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(scrollView)
        workspace.addSubview(stateView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: workspace.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: workspace.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: workspace.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: workspace.bottomAnchor),
            stateView.leadingAnchor.constraint(equalTo: workspace.leadingAnchor),
            stateView.trailingAnchor.constraint(equalTo: workspace.trailingAnchor),
            stateView.topAnchor.constraint(equalTo: workspace.topAnchor),
            stateView.bottomAnchor.constraint(equalTo: workspace.bottomAnchor)
        ])

        let root = NSStackView(views: [header, toggle, searchField, workspace, buttons])
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 9
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            workspace.heightAnchor.constraint(greaterThanOrEqualToConstant: 250)
        ])
    }

    private func bind(_ button: NSButton, action: @escaping () -> Void) {
        let retainer = ClosureAction(action)
        actionRetainers.append(retainer)
        button.target = retainer
        button.action = #selector(ClosureAction.perform(_:))
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

    private func performOnSelected(_ action: ((UUID) -> Void)?) {
        guard let selectedID else { return }
        action?(selectedID)
    }

    @objc private func toggleChanged(_ sender: NSButton) { actions.setEnabled(sender.state == .on) }
}
