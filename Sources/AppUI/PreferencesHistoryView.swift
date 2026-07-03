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
        let addTerm: (String, @escaping (Result<Void, Error>) -> Void) -> Void
    }

    private let actions: Actions
    private let toggle = NSButton(checkboxWithTitle: "Save transcript history", target: nil, action: nil)
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let stateView = NSView()
    private var workspaceGroup: NSView?
    private var listHeightConstraint: NSLayoutConstraint?
    private var actionBarView: NSView?
    private let stateTitle = NSTextField(labelWithString: "")
    private let stateDetail = NSTextField(wrappingLabelWithString: "")
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let repasteButton = NSButton(title: "Paste Again", target: nil, action: nil)
    private let addTermButton = NSButton(title: "Add Term...", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private var preferredTermPopover: NSPopover?
    private var preferredTermField: NSTextField?
    private var preferredTermSaveButton: NSButton?
    private var records: [TranscriptRecord] = []
    private var visibleRecords: [TranscriptRecord] = []
    private var selectedID: UUID?
    private var isEnabled = true
    private var loadErrorDescription: String?
    private var rowsAreTranscriptFirst = true
    private var transcriptTextIsLeftAligned = true
    private var hasRenderedOnce = false

    private(set) var state = State.empty
    private(set) var contentReloadCount = 0
    var visibleRecordIDs: [UUID] {
        visibleRecords.map(\.id)
    }

    var selectedRecordID: UUID? {
        selectedID
    }

    var usesGroupedWorkspace: Bool {
        workspaceGroup is PreferencesBackgroundView
    }

    var usesPinnedActionBar: Bool {
        actionBarView is PreferencesPinnedActionBarView
    }

    var visibleRowsAreTranscriptFirst: Bool {
        rowsAreTranscriptFirst
    }

    var visibleTranscriptTextIsLeftAligned: Bool {
        transcriptTextIsLeftAligned
    }

    var visibleMetrics: [String] {
        visibleRecords.map(PreferencesContentState.historyMetrics(for:))
    }

    var areActionControlsWithinBounds: Bool {
        [copyButton, repasteButton, addTermButton, deleteButton].allSatisfy { bounds.contains(convert($0.bounds, from: $0)) }
    }

    init(actions: Actions) {
        self.actions = actions
        super.init(frame: .zero)
        buildView()
        update(records: [], isEnabled: true, loadErrorDescription: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(records: [TranscriptRecord], isEnabled: Bool, loadErrorDescription: String?) {
        syncToggleState(isEnabled: isEnabled)
        // Model/permission/hotkey refreshes reach this page with identical history data;
        // reloading the table and re-measuring every transcript's height each time is a
        // measured contributor to preferences lag, so skip no-op updates entirely.
        if hasRenderedOnce,
           records == self.records,
           isEnabled == self.isEnabled,
           loadErrorDescription == self.loadErrorDescription
        {
            return
        }
        hasRenderedOnce = true
        self.records = records
        self.isEnabled = isEnabled
        self.loadErrorDescription = loadErrorDescription
        applyFilter()
    }

    func syncToggleState(isEnabled: Bool) {
        toggle.state = isEnabled ? .on : .off
    }

    func setSearchQuery(_ query: String) {
        searchField.stringValue = query
        applyFilter()
    }

    func controlTextDidChange(_: Notification) {
        applyFilter()
    }

    func numberOfRows(in _: NSTableView) -> Int {
        visibleRecords.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard visibleRecords.indices.contains(row) else { return 76 }
        let width = max(260, tableView.bounds.width - 36)
        let text = visibleRecords[row].text as NSString
        let textHeight = text.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        ).height
        // top(13) + text + gap(5) + metadata(~15) + bottom(13)
        return max(80, ceil(textHeight) + 46)
    }

    func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard visibleRecords.indices.contains(row) else { return nil }
        let record = visibleRecords[row]
        let cell = NSTableCellView()
        let text = NSTextField(wrappingLabelWithString: record.text)
        text.font = .systemFont(ofSize: 14)
        text.textColor = .labelColor
        text.alignment = .left
        text.maximumNumberOfLines = 0

        let time = NSTextField(labelWithString: DateFormatter.localizedString(
            from: record.createdAt,
            dateStyle: .medium,
            timeStyle: .short
        ))
        time.font = .systemFont(ofSize: 12, weight: .medium)
        time.textColor = .secondaryLabelColor
        let metrics = NSTextField(labelWithString: PreferencesContentState.historyMetrics(for: record))
        metrics.font = .systemFont(ofSize: 12)
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
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: PreferencesPageSupport.rowInset),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -PreferencesPageSupport.rowInset),
            text.topAnchor.constraint(equalTo: cell.topAnchor, constant: 13),
            metadata.leadingAnchor.constraint(equalTo: text.leadingAnchor),
            metadata.trailingAnchor.constraint(equalTo: text.trailingAnchor),
            metadata.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 5),
            metadata.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -13),
        ])
        rowsAreTranscriptFirst = true
        transcriptTextIsLeftAligned = text.alignment == .left
        return cell
    }

    func tableView(_: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
        PreferencesSelectionRowView()
    }

    func tableViewSelectionDidChange(_: Notification) {
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
        // `.plain` drops the automatic source-list inset so cell text starts at the shared
        // row grid instead of ~17pt further right than every other page.
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.gridStyleMask = .solidHorizontalGridLineMask
        tableView.gridColor = PreferencesPageSupport.hairlineColor
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

        for button in [copyButton, repasteButton, addTermButton, deleteButton] {
            PreferencesPageSupport.configureSecondaryButton(button)
        }
        deleteButton.contentTintColor = .systemRed
        copyButton.target = self
        copyButton.action = #selector(copySelected(_:))
        repasteButton.target = self
        repasteButton.action = #selector(repasteSelected(_:))
        addTermButton.target = self
        addTermButton.action = #selector(showAddTermPopover(_:))
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
            stateStack.centerYAnchor.constraint(equalTo: stateView.centerYAnchor),
        ])

        let (workspace, listHeight) = PreferencesPageSupport.makeListWorkspace(scrollView: scrollView, stateView: stateView)
        workspaceGroup = workspace
        listHeightConstraint = listHeight
        let actionBar = PreferencesPageSupport.makePinnedActionBar(
            leading: [copyButton, repasteButton, addTermButton],
            trailing: [deleteButton]
        )
        actionBarView = actionBar
        let toggleRow = NSStackView(views: [toggle, NSView()])
        toggleRow.orientation = .horizontal
        toggleRow.alignment = .centerY
        toggleRow.edgeInsets = NSEdgeInsets(
            top: 11,
            left: PreferencesPageSupport.rowInset,
            bottom: 11,
            right: PreferencesPageSupport.rowInset
        )

        let page = PreferencesPageSupport.makePage(
            title: "History",
            description: "Recent transcripts stored on this Mac.",
            content: [
                PreferencesPageSupport.makeGroup(rows: [toggleRow]),
                searchField,
                workspace,
                actionBar,
            ]
        )
        PreferencesPageSupport.fill(self, with: page)
    }

    private func applyFilter() {
        contentReloadCount += 1
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
        updateListHeight()
    }

    /// Hug the list to its content so the framed region ends just under the last row (or the
    /// empty-state message) rather than stretching a mostly-empty box.
    private func updateListHeight() {
        let contentHeight: CGFloat
        if state == .records, !visibleRecords.isEmpty {
            contentHeight = visibleRecords.indices.reduce(CGFloat(0)) { $0 + self.tableView(tableView, heightOfRow: $1) } + 2
        } else {
            contentHeight = 150
        }
        listHeightConstraint?.constant = min(
            PreferencesPageSupport.listMaxHeight,
            max(PreferencesPageSupport.listMinHeight, contentHeight)
        )
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
        addTermButton.isEnabled = enabled
        deleteButton.isEnabled = enabled
    }

    private func performOnSelected(_ action: (UUID) -> Void) {
        guard let selectedID else { return }
        action(selectedID)
    }

    @objc private func copySelected(_: NSButton) {
        performOnSelected(actions.copy)
    }

    @objc private func repasteSelected(_: NSButton) {
        performOnSelected(actions.repaste)
    }

    @objc private func showAddTermPopover(_ sender: NSButton) {
        let field = NSTextField()
        field.placeholderString = "Preferred term"
        field.bezelStyle = .roundedBezel
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPreferredTermPopover(_:)))
        let save = NSButton(title: "Save", target: self, action: #selector(savePreferredTermDraftAction(_:)))
        save.keyEquivalent = "\r"
        PreferencesPageSupport.configureSecondaryButton(cancel)
        PreferencesPageSupport.configureSecondaryButton(save)

        let title = NSTextField(labelWithString: "Add preferred term")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let buttons = NSStackView(views: [NSView(), cancel, save])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let content = NSStackView(views: [title, field, buttons])
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        preferredTermPopover = popover
        preferredTermField = field
        preferredTermSaveButton = save
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        field.window?.makeFirstResponder(field)
    }

    func setPreferredTermDraft(_ value: String) {
        preferredTermField?.stringValue = value
    }

    func savePreferredTermDraft() {
        guard let field = preferredTermField else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        preferredTermSaveButton?.isEnabled = false
        actions.addTerm(value) { [weak self] result in
            self?.preferredTermSaveButton?.isEnabled = true
            if case .success = result {
                self?.preferredTermPopover?.close()
                self?.preferredTermPopover = nil
                self?.preferredTermField = nil
                self?.preferredTermSaveButton = nil
            }
            if case let .failure(error) = result {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func savePreferredTermDraftAction(_: NSButton) {
        savePreferredTermDraft()
    }

    @objc private func cancelPreferredTermPopover(_: NSButton) {
        preferredTermPopover?.close()
        preferredTermPopover = nil
        preferredTermField = nil
        preferredTermSaveButton = nil
    }

    @objc private func deleteSelected(_: NSButton) {
        guard let selectedID else { return }
        actions.delete([selectedID])
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        actions.setEnabled(sender.state == .on)
    }
}
