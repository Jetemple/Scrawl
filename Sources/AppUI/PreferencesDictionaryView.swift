import AppKit
import DictionaryStore

final class PreferencesDictionaryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    enum State: Equatable { case unavailable, empty, noSearchResults, entries }

    struct Actions {
        let save: (String?, String, String, @escaping (Result<Void, Error>) -> Void) -> Void
        let delete: (Set<String>, @escaping (Result<Void, Error>) -> Void) -> Void
        let recover: (@escaping (Result<Void, Error>) -> Void) -> Void
    }

    private let actions: Actions
    private let termField = NSTextField()
    private let searchField = NSSearchField()
    private let tableView = DeleteKeyTableView()
    private let stateView = NSView()
    private var workspaceGroup: NSView?
    private var listHeightConstraint: NSLayoutConstraint?
    private var actionBarView: NSView?
    private let stateTitle = NSTextField(labelWithString: "")
    private let stateDetail = NSTextField(wrappingLabelWithString: "")
    private let resetButton = NSButton(title: "Reset Dictionary", target: nil, action: nil)
    private let editButton = NSButton(title: "Edit", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private var terms: [VocabularyTerm] = []
    private var visibleTerms: [VocabularyTerm] = []
    private var selectedValues: Set<String> = []
    private var loadErrorDescription: String?
    private weak var editorWindow: NSWindow?
    private var editorOriginal: String?
    private var editorField: NSTextField?

    private(set) var state = State.empty
    var visibleWrongValues: [String] {
        visibleTerms.map(\.value)
    }

    var selectedWrong: String? {
        selectedValues.count == 1 ? selectedValues.first : nil
    }

    var usesGroupedWorkspace: Bool {
        workspaceGroup is PreferencesBackgroundView
    }

    var usesPinnedActionBar: Bool {
        actionBarView is PreferencesPinnedActionBarView
    }

    init(actions: Actions) {
        self.actions = actions
        super.init(frame: .zero)
        buildView()
        update(entries: [], loadErrorDescription: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(entries: [DictionaryEntry], loadErrorDescription: String?) {
        terms = entries.map { VocabularyTerm(value: $0.correct) }
        self.loadErrorDescription = loadErrorDescription
        applyFilter()
    }

    func setSearchQuery(_ query: String) {
        searchField.stringValue = query
        applyFilter()
    }

    func controlTextDidChange(_: Notification) {
        applyFilter()
    }

    func numberOfRows(in _: NSTableView) -> Int {
        visibleTerms.count
    }

    func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard visibleTerms.indices.contains(row) else { return nil }
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: visibleTerms[row].value)
        label.font = .systemFont(ofSize: 14)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: PreferencesPageSupport.rowInset),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -PreferencesPageSupport.rowInset),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableView(_: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
        PreferencesSelectionRowView()
    }

    func tableViewSelectionDidChange(_: Notification) {
        selectedValues = Set(tableView.selectedRowIndexes.compactMap {
            visibleTerms.indices.contains($0) ? visibleTerms[$0].value : nil
        })
        updateActionAvailability()
    }

    private func buildView() {
        termField.placeholderString = "Add a preferred term"
        // A plain NSTextField defaults to a square bezel, whose sharp corners clash
        // with the rounded search field and list group below it. The rounded bezel
        // gives the input the same soft corners as everything around it.
        termField.bezelStyle = .roundedBezel
        termField.target = self
        termField.action = #selector(addTerm(_:))

        searchField.placeholderString = "Search dictionary"
        searchField.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("term"))
        column.title = "Preferred Terms"
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 40
        // `.plain` drops the automatic source-list inset so term text starts at the shared
        // row grid instead of ~17pt further right than every other page.
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.gridStyleMask = .solidHorizontalGridLineMask
        tableView.gridColor = PreferencesPageSupport.hairlineColor
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(editSelected(_:))
        tableView.onDelete = { [weak self] in self?.deleteSelected(nil) }
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

        stateTitle.font = .systemFont(ofSize: 15, weight: .medium)
        stateDetail.textColor = .secondaryLabelColor
        stateDetail.alignment = .center
        PreferencesPageSupport.configureSecondaryButton(resetButton)
        resetButton.target = self
        resetButton.action = #selector(recoverDictionary(_:))
        let stateStack = NSStackView(views: [stateTitle, stateDetail, resetButton])
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

        PreferencesPageSupport.configureSecondaryButton(editButton)
        PreferencesPageSupport.configureSecondaryButton(deleteButton)
        deleteButton.contentTintColor = .systemRed
        editButton.target = self
        editButton.action = #selector(editSelected(_:))
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected(_:))
        let actionBar = PreferencesPageSupport.makePinnedActionBar(leading: [editButton], trailing: [deleteButton])
        actionBarView = actionBar
        let page = PreferencesPageSupport.makePage(
            title: "Dictionary",
            description: "Preferred terms for names and phrases.",
            content: [
                termField,
                searchField,
                workspace,
                actionBar,
            ]
        )
        PreferencesPageSupport.fill(self, with: page)
    }

    @objc private func addTerm(_: Any) {
        let value = termField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        termField.isEnabled = false
        actions.save(nil, value, value) { [weak self] result in
            guard let self else { return }
            termField.isEnabled = state != .unavailable
            if case .success = result { termField.stringValue = "" }
            if case let .failure(error) = result { NSAlert(error: error).runModal() }
        }
    }

    private func applyFilter() {
        visibleTerms = PreferencesContentState.filteredVocabulary(terms: terms, query: searchField.stringValue)
        let retained = visibleTerms.compactMap { term in
            selectedValues.contains { term.value.caseInsensitiveCompare($0) == .orderedSame } ? term.value : nil
        }
        selectedValues = retained.isEmpty ? Set(visibleTerms.first.map { [$0.value] } ?? []) : Set(retained)
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(visibleTerms.indices.filter { selectedValues.contains(visibleTerms[$0].value) }), byExtendingSelection: false)
        updateState()
        updateActionAvailability()
        updateListHeight()
    }

    /// Hug the list to its content so the framed region ends just under the last term (or the
    /// empty-state message) rather than stretching a mostly-empty box.
    private func updateListHeight() {
        let contentHeight: CGFloat = state == .entries
            ? CGFloat(visibleTerms.count) * tableView.rowHeight + 2
            : 150
        listHeightConstraint?.constant = min(
            PreferencesPageSupport.listMaxHeight,
            max(PreferencesPageSupport.listMinHeight, contentHeight)
        )
    }

    private func updateState() {
        if loadErrorDescription != nil {
            state = .unavailable
            stateTitle.stringValue = "Dictionary unavailable"
            stateDetail.stringValue = "Scrawl could not read the saved dictionary file."
        } else if terms.isEmpty {
            state = .empty
            stateTitle.stringValue = "No preferred terms yet"
            stateDetail.stringValue = "Add names and phrases you want Whisper to recognize."
        } else if visibleTerms.isEmpty {
            state = .noSearchResults
            stateTitle.stringValue = "No matching terms"
            stateDetail.stringValue = "Try a different search."
        } else {
            state = .entries
        }
        resetButton.isHidden = state != .unavailable
        stateView.isHidden = state == .entries
        tableView.enclosingScrollView?.isHidden = state != .entries
        termField.isEnabled = state != .unavailable
        searchField.isEnabled = state != .unavailable
    }

    private func updateActionAvailability() {
        editButton.isEnabled = state != .unavailable && selectedValues.count == 1
        deleteButton.isEnabled = state != .unavailable && !selectedValues.isEmpty
    }

    @objc private func recoverDictionary(_ sender: NSButton) {
        sender.isEnabled = false
        actions.recover { result in
            sender.isEnabled = true
            if case let .failure(error) = result {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func editSelected(_: Any?) {
        showEditorForSelection()
    }

    private func showEditorForSelection() {
        guard let selectedWrong else { return }
        showEditor(original: selectedWrong)
    }

    private func showEditor(original: String) {
        guard let window else { return }
        let field = NSTextField(string: original)
        field.bezelStyle = .roundedBezel
        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        let save = NSButton(title: "Save", target: nil, action: nil)
        save.keyEquivalent = "\r"
        cancel.keyEquivalent = "\u{1b}" // Escape dismisses, matching macOS sheet convention.
        let root = NSStackView(views: [NSTextField(labelWithString: "Preferred term"), field, NSStackView(views: [NSView(), cancel, save])])
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Edit Term"
        panel.contentView = root
        editorWindow = window
        editorOriginal = original
        editorField = field
        cancel.target = self
        cancel.action = #selector(cancelEditor(_:))
        save.target = self
        save.action = #selector(saveEditor(_:))
        window.beginSheet(panel)
        panel.makeFirstResponder(field)
    }

    @objc private func cancelEditor(_: NSButton) {
        guard let window = editorWindow, let sheet = window.attachedSheet else { return }
        window.endSheet(sheet)
        clearEditorState()
    }

    @objc private func saveEditor(_ sender: NSButton) {
        guard let field = editorField else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        sender.isEnabled = false
        actions.save(editorOriginal, value, value) { [weak self] result in
            guard let self else { return }
            if case .success = result, let window = editorWindow, let sheet = window.attachedSheet {
                window.endSheet(sheet)
                clearEditorState()
            }
            if case let .failure(error) = result {
                sender.isEnabled = true
                NSAlert(error: error).runModal()
            }
        }
    }

    private func clearEditorState() {
        editorOriginal = nil
        editorField = nil
        editorWindow = nil
    }

    @objc private func deleteSelected(_: Any? = nil) {
        guard !selectedValues.isEmpty else { return }
        if selectedValues.count > 1 {
            let alert = NSAlert()
            alert.messageText = "Delete \(selectedValues.count) Terms?"
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        actions.delete(selectedValues) { result in
            if case let .failure(error) = result { NSAlert(error: error).runModal() }
        }
    }
}

private final class DeleteKeyTableView: NSTableView {
    var onDelete: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { onDelete?() } else { super.keyDown(with: event) }
    }
}
