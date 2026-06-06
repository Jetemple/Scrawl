import AppKit
import TranscriptHistoryStore

final class PreferencesHistoryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextViewDelegate {
    enum State: Equatable {
        case disabled
        case unavailable
        case empty
        case noSearchResults
        case records
    }

    struct Actions {
        let setEnabled: (Bool) -> Void
        let copy: (UUID) -> Void
        let repaste: (UUID) -> Void
        let delete: (Set<UUID>) -> Void
        let addDictionaryEntry: (String, String, @escaping (Result<Void, Error>) -> Void) -> Void
    }

    private let actions: Actions
    private let toggle = NSButton(checkboxWithTitle: "Save transcript history", target: nil, action: nil)
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let textView = NSTextView()
    private let timestampLabel = NSTextField(labelWithString: "")
    private let wordCountLabel = NSTextField(labelWithString: "")
    private let stateTitle = NSTextField(labelWithString: "")
    private let stateDetail = NSTextField(wrappingLabelWithString: "")
    private let stateView = NSView()
    private let panes = NSStackView()
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let repasteButton = NSButton(title: "Paste Again", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let addDictionaryButton = NSButton(title: "Add to Dictionary", target: nil, action: nil)
    private var actionRetainers: [ClosureAction] = []
    private var records: [TranscriptRecord] = []
    private var visibleRecords: [TranscriptRecord] = []
    private var selectedID: UUID?
    private var isEnabled = true
    private var loadErrorDescription: String?
    private var dictionaryPopover: NSPopover?
    private var dictionaryPopoverActions: [ClosureAction] = []

    private(set) var state = State.empty
    var visibleRecordIDs: [UUID] { visibleRecords.map(\.id) }
    var selectedRecordID: UUID? { selectedID }
    var isAddDictionaryEnabled: Bool { addDictionaryButton.isEnabled }

    init(actions: Actions) {
        self.actions = actions
        super.init(frame: .zero)
        buildView()
        update(records: [], isEnabled: true, loadErrorDescription: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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

    func selectText(range: NSRange) {
        textView.setSelectedRange(range)
        updateActionAvailability()
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleRecords.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleRecords.indices.contains(row) else { return nil }
        let record = visibleRecords[row]
        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: record.text.replacingOccurrences(of: "\n", with: " "))
        text.lineBreakMode = .byTruncatingTail
        text.font = .systemFont(ofSize: 12)
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectedID = visibleRecords.indices.contains(tableView.selectedRow) ? visibleRecords[tableView.selectedRow].id : nil
        updateDetail()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateActionAvailability()
    }

    private func buildView() {
        let header = PreferencesPageSupport.makePageHeader(
            title: "History",
            description: "Review, reuse, or remove transcripts saved locally on this Mac."
        )
        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))

        searchField.placeholderString = "Search transcripts"
        searchField.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = true

        let listScroll = NSScrollView()
        listScroll.hasVerticalScroller = true
        listScroll.documentView = tableView
        let left = NSStackView(views: [searchField, listScroll])
        left.orientation = .vertical
        left.alignment = .width
        left.spacing = 8
        left.widthAnchor.constraint(equalToConstant: 150).isActive = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.delegate = self
        let textScroll = NSScrollView()
        textScroll.hasVerticalScroller = true
        textScroll.documentView = textView

        timestampLabel.textColor = .secondaryLabelColor
        wordCountLabel.textColor = .secondaryLabelColor
        let metadata = NSStackView(views: [timestampLabel, NSView(), wordCountLabel])
        metadata.orientation = .horizontal
        metadata.alignment = .centerY

        for button in [copyButton, repasteButton, addDictionaryButton, deleteButton] {
            PreferencesPageSupport.configureSecondaryButton(button)
        }
        deleteButton.contentTintColor = .systemRed
        bind(copyButton) { [weak self] in self?.performOnSelected(self?.actions.copy) }
        bind(repasteButton) { [weak self] in self?.performOnSelected(self?.actions.repaste) }
        bind(deleteButton) { [weak self] in
            guard let id = self?.selectedID else { return }
            self?.actions.delete([id])
        }
        bind(addDictionaryButton) { [weak self] in self?.showDictionaryPopover() }
        let buttons = NSStackView(views: [copyButton, repasteButton, addDictionaryButton, NSView(), deleteButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 6

        let right = NSStackView(views: [metadata, textScroll, buttons])
        right.orientation = .vertical
        right.alignment = .width
        right.spacing = 8

        panes.addArrangedSubview(left)
        panes.addArrangedSubview(right)
        panes.orientation = .horizontal
        panes.alignment = .height
        panes.spacing = 12

        stateTitle.font = .systemFont(ofSize: 15, weight: .medium)
        stateTitle.alignment = .center
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
            stateStack.centerYAnchor.constraint(equalTo: stateView.centerYAnchor),
            stateStack.leadingAnchor.constraint(greaterThanOrEqualTo: stateView.leadingAnchor, constant: 16),
            stateStack.trailingAnchor.constraint(lessThanOrEqualTo: stateView.trailingAnchor, constant: -16)
        ])

        let workspace = NSView()
        panes.translatesAutoresizingMaskIntoConstraints = false
        stateView.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(panes)
        workspace.addSubview(stateView)
        NSLayoutConstraint.activate([
            panes.leadingAnchor.constraint(equalTo: workspace.leadingAnchor),
            panes.trailingAnchor.constraint(equalTo: workspace.trailingAnchor),
            panes.topAnchor.constraint(equalTo: workspace.topAnchor),
            panes.bottomAnchor.constraint(equalTo: workspace.bottomAnchor),
            stateView.leadingAnchor.constraint(equalTo: workspace.leadingAnchor),
            stateView.trailingAnchor.constraint(equalTo: workspace.trailingAnchor),
            stateView.topAnchor.constraint(equalTo: workspace.topAnchor),
            stateView.bottomAnchor.constraint(equalTo: workspace.bottomAnchor)
        ])

        let root = NSStackView(views: [header, toggle, workspace])
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            workspace.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
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
        updateDetail()
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
        stateView.isHidden = state == .records || state == .noSearchResults
        panes.isHidden = state != .records && state != .noSearchResults
        searchField.isEnabled = isEnabled && loadErrorDescription == nil && !records.isEmpty
    }

    private func updateDetail() {
        guard let record = visibleRecords.first(where: { $0.id == selectedID }), state == .records else {
            textView.string = state == .noSearchResults ? "No matching transcripts.\nTry a different search." : ""
            timestampLabel.stringValue = ""
            wordCountLabel.stringValue = ""
            updateActionAvailability()
            return
        }
        textView.string = record.text
        timestampLabel.stringValue = DateFormatter.localizedString(
            from: record.createdAt,
            dateStyle: .medium,
            timeStyle: .short
        )
        let count = record.text.split(whereSeparator: \.isWhitespace).count
        wordCountLabel.stringValue = "\(count) \(count == 1 ? "word" : "words")"
        updateActionAvailability()
    }

    private func updateActionAvailability() {
        let hasRecord = selectedID != nil && state == .records
        copyButton.isEnabled = hasRecord
        repasteButton.isEnabled = hasRecord
        deleteButton.isEnabled = hasRecord
        addDictionaryButton.isEnabled = hasRecord && textView.selectedRange().length > 0
    }

    private func performOnSelected(_ action: ((UUID) -> Void)?) {
        guard let selectedID else { return }
        action?(selectedID)
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        actions.setEnabled(sender.state == .on)
    }

    private func showDictionaryPopover() {
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        let selectedText = (textView.string as NSString).substring(with: range)
        let heardField = NSTextField(string: selectedText)
        let replacementField = NSTextField(string: selectedText)
        let errorLabel = NSTextField(wrappingLabelWithString: "")
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        let add = NSButton(title: "Add", target: nil, action: nil)
        add.keyEquivalent = "\r"

        let fields = NSStackView(views: [
            NSTextField(labelWithString: "Heard text"), heardField,
            NSTextField(labelWithString: "Replacement"), replacementField,
            errorLabel
        ])
        fields.orientation = .vertical
        fields.alignment = .width
        fields.spacing = 5
        let buttons = NSStackView(views: [NSView(), cancel, add])
        buttons.orientation = .horizontal
        buttons.spacing = 6
        let root = NSStackView(views: [fields, buttons])
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let popover = NSPopover()
        let controller = NSViewController()
        controller.view = root
        controller.preferredContentSize = NSSize(width: 280, height: 170)
        popover.contentViewController = controller
        popover.behavior = .transient

        let cancelAction = ClosureAction { popover.close() }
        let addAction = ClosureAction { [weak self] in
            guard
                !heardField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !replacementField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                errorLabel.stringValue = "Both fields are required."
                errorLabel.isHidden = false
                return
            }
            self?.actions.addDictionaryEntry(heardField.stringValue, replacementField.stringValue) { result in
                switch result {
                case .success:
                    popover.close()
                case let .failure(error):
                    errorLabel.stringValue = error.localizedDescription
                    errorLabel.isHidden = false
                }
            }
        }
        dictionaryPopover = popover
        dictionaryPopoverActions = [cancelAction, addAction]
        cancel.target = cancelAction
        cancel.action = #selector(ClosureAction.perform(_:))
        add.target = addAction
        add.action = #selector(ClosureAction.perform(_:))
        popover.show(relativeTo: addDictionaryButton.bounds, of: addDictionaryButton, preferredEdge: .maxY)
    }
}
