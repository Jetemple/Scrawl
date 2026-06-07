import AppKit
import DictionaryStore

final class PreferencesDictionaryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    enum State: Equatable { case empty, noSearchResults, entries }

    struct Actions {
        let save: (String?, String, String, @escaping (Result<Void, Error>) -> Void) -> Void
        let delete: (Set<String>, @escaping (Result<Void, Error>) -> Void) -> Void
    }

    private let actions: Actions
    private let termField = NSTextField()
    private let addButton = NSButton(title: "Add Term", target: nil, action: nil)
    private let searchField = NSSearchField()
    private let tableView = DeleteKeyTableView()
    private let stateView = NSView()
    private let stateTitle = NSTextField(labelWithString: "")
    private let stateDetail = NSTextField(wrappingLabelWithString: "")
    private let editButton = NSButton(title: "Edit", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private var terms: [VocabularyTerm] = []
    private var visibleTerms: [VocabularyTerm] = []
    private var selectedValues: Set<String> = []
    private var actionRetainers: [ClosureAction] = []
    private var editorActionRetainers: [ClosureAction] = []

    private(set) var state = State.empty
    var visibleWrongValues: [String] { visibleTerms.map(\.value) }
    var selectedWrong: String? { selectedValues.count == 1 ? selectedValues.first : nil }

    init(actions: Actions) {
        self.actions = actions
        super.init(frame: .zero)
        buildView()
        update(entries: [])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(entries: [DictionaryEntry]) {
        terms = entries.map { VocabularyTerm(value: $0.correct) }
        applyFilter()
    }

    func setSearchQuery(_ query: String) {
        searchField.stringValue = query
        applyFilter()
    }

    func controlTextDidChange(_ obj: Notification) { applyFilter() }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleTerms.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleTerms.indices.contains(row) else { return nil }
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: visibleTerms[row].value)
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectedValues = Set(tableView.selectedRowIndexes.compactMap {
            visibleTerms.indices.contains($0) ? visibleTerms[$0].value : nil
        })
        updateActionAvailability()
    }

    private func buildView() {
        let header = PreferencesPageSupport.makePageHeader(
            title: "Vocabulary",
            description: "Preferred names, terms, and phrases that help Whisper recognize your language."
        )
        termField.placeholderString = "Add a preferred term, such as Anduril"
        PreferencesPageSupport.configureSecondaryButton(addButton)
        addButton.bezelColor = .controlAccentColor
        bind(addButton) { [weak self] in self?.addTerm() }
        let addRow = NSStackView(views: [termField, addButton])
        addRow.orientation = .horizontal
        addRow.spacing = 8

        searchField.placeholderString = "Search vocabulary"
        searchField.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("term"))
        column.title = "Preferred Terms"
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.rowHeight = 30
        tableView.allowsMultipleSelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(editSelected(_:))
        tableView.onDelete = { [weak self] in self?.deleteSelected() }
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

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

        PreferencesPageSupport.configureSecondaryButton(editButton)
        PreferencesPageSupport.configureSecondaryButton(deleteButton)
        deleteButton.contentTintColor = .systemRed
        bind(editButton) { [weak self] in self?.showEditorForSelection() }
        bind(deleteButton) { [weak self] in self?.deleteSelected() }
        let buttons = NSStackView(views: [editButton, deleteButton, NSView()])
        buttons.orientation = .horizontal
        buttons.spacing = 6

        let root = NSStackView(views: [header, addRow, searchField, workspace, buttons])
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
            workspace.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
    }

    private func bind(_ button: NSButton, action: @escaping () -> Void) {
        let retainer = ClosureAction(action)
        actionRetainers.append(retainer)
        button.target = retainer
        button.action = #selector(ClosureAction.perform(_:))
    }

    private func addTerm() {
        let value = termField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        addButton.isEnabled = false
        actions.save(nil, value, value) { [weak self] result in
            self?.addButton.isEnabled = true
            if case .success = result { self?.termField.stringValue = "" }
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
    }

    private func updateState() {
        if terms.isEmpty {
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
        stateView.isHidden = state == .entries
        tableView.enclosingScrollView?.isHidden = state != .entries
    }

    private func updateActionAvailability() {
        editButton.isEnabled = selectedValues.count == 1
        deleteButton.isEnabled = !selectedValues.isEmpty
    }

    @objc private func editSelected(_ sender: Any?) { showEditorForSelection() }

    private func showEditorForSelection() {
        guard let selectedWrong else { return }
        showEditor(original: selectedWrong)
    }

    private func showEditor(original: String) {
        guard let window else { return }
        let field = NSTextField(string: original)
        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        let save = NSButton(title: "Save", target: nil, action: nil)
        save.keyEquivalent = "\r"
        let root = NSStackView(views: [NSTextField(labelWithString: "Preferred term"), field, NSStackView(views: [NSView(), cancel, save])])
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Edit Term"
        panel.contentView = root
        let cancelAction = ClosureAction { [weak window] in
            if let sheet = window?.attachedSheet { window?.endSheet(sheet) }
        }
        let saveAction = ClosureAction { [weak self, weak window] in
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            save.isEnabled = false
            self?.actions.save(original, value, value) { result in
                if case .success = result, let sheet = window?.attachedSheet { window?.endSheet(sheet) }
                if case let .failure(error) = result { save.isEnabled = true; NSAlert(error: error).runModal() }
            }
        }
        editorActionRetainers = [cancelAction, saveAction]
        cancel.target = cancelAction
        cancel.action = #selector(ClosureAction.perform(_:))
        save.target = saveAction
        save.action = #selector(ClosureAction.perform(_:))
        window.beginSheet(panel)
        window.makeFirstResponder(field)
    }

    private func deleteSelected() {
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
