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
    private var listHeightConstraint: NSLayoutConstraint?
    private var actionBarView: NSView?
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
        [copyButton, repasteButton, deleteButton].allSatisfy { bounds.contains(convert($0.bounds, from: $0)) }
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

    /// Measuring with the same label configuration the cells use keeps the height
    /// answer and the rendered wrap in exact agreement; any drift shows up as clipped
    /// metadata or phantom gaps between rows.
    private static let measuringTranscriptLabel = makeTranscriptLabel(text: "")

    private static let metadataLineHeight: CGFloat = {
        let label = NSTextField(labelWithString: "Ag")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        return ceil(label.intrinsicContentSize.height)
    }()

    private static func makeTranscriptLabel(text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 14)
        label.textColor = .labelColor
        label.alignment = .left
        // Long dictations clamp so one paste can't swallow the list; Copy and the
        // tooltip still carry the full text.
        label.maximumNumberOfLines = 3
        label.cell?.truncatesLastVisibleLine = true
        return label
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let textHeight: CGFloat
        if visibleRecords.indices.contains(row) {
            let label = Self.measuringTranscriptLabel
            label.stringValue = visibleRecords[row].text
            label.preferredMaxLayoutWidth = max(260, tableView.bounds.width - 2 * PreferencesPageSupport.rowInset)
            textHeight = ceil(label.intrinsicContentSize.height)
        } else {
            textHeight = Self.metadataLineHeight
        }
        // Mirrors the cell constraints: top(13) + text + gap(5) + metadata + bottom(13)
        return 13 + textHeight + 5 + Self.metadataLineHeight + 13
    }

    func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard visibleRecords.indices.contains(row) else { return nil }
        let record = visibleRecords[row]
        let cell = NSTableCellView()
        let text = Self.makeTranscriptLabel(text: record.text)
        text.toolTip = record.text

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
            stateStack.centerYAnchor.constraint(equalTo: stateView.centerYAnchor),
        ])

        let actionBar = PreferencesPageSupport.makePinnedActionBar(
            leading: [copyButton, repasteButton],
            trailing: [deleteButton]
        )
        actionBarView = actionBar
        let (workspace, listHeight) = PreferencesPageSupport.makeListWorkspace(
            scrollView: scrollView,
            stateView: stateView,
            actionBar: actionBar
        )
        workspaceGroup = workspace
        listHeightConstraint = listHeight
        let toggleRow = NSStackView(views: [toggle, NSView()])
        toggleRow.orientation = .horizontal
        toggleRow.alignment = .centerY
        toggleRow.edgeInsets = NSEdgeInsets(
            top: 11,
            left: PreferencesPageSupport.rowInset,
            bottom: 11,
            right: PreferencesPageSupport.rowInset
        )

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let searchRow = NSStackView(views: [NSView(), searchField])
        searchRow.orientation = .horizontal
        searchRow.alignment = .centerY

        let page = PreferencesPageSupport.makePage(
            content: [
                PreferencesPageSupport.makeGroup(
                    footer: "Recent transcripts stored on this Mac.",
                    rows: [toggleRow]
                ),
                searchRow,
                workspace,
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
        let contentHeight: CGFloat = if state == .records, !visibleRecords.isEmpty {
            visibleRecords.indices.reduce(CGFloat(0)) { $0 + self.tableView(tableView, heightOfRow: $1) } + 2
        } else {
            150
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

    @objc private func deleteSelected(_: NSButton) {
        guard let selectedID else { return }
        actions.delete([selectedID])
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        actions.setEnabled(sender.state == .on)
    }
}
