import AppKit
import DictionaryStore

final class PreferencesDictionaryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    enum State: Equatable {
        case empty
        case noSearchResults
        case entries
    }

    struct Actions {
        let save: (String?, String, String, @escaping (Result<Void, Error>) -> Void) -> Void
        let delete: (Set<String>, @escaping (Result<Void, Error>) -> Void) -> Void
    }

    private let actions: Actions
    private let searchField = NSSearchField()
    private let tableView = DeleteKeyTableView()
    private let stateView = NSView()
    private let stateTitle = NSTextField(labelWithString: "")
    private let stateDetail = NSTextField(wrappingLabelWithString: "")
    private let addButton = NSButton(title: "Add Replacement", target: nil, action: nil)
    private let editButton = NSButton(title: "Edit", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private var entries: [DictionaryEntry] = []
    private var visibleEntries: [DictionaryEntry] = []
    private var selectedWrongValues: Set<String> = []
    private var actionRetainers: [ClosureAction] = []
    private var editorActionRetainers: [ClosureAction] = []

    private(set) var state = State.empty
    var visibleWrongValues: [String] { visibleEntries.map(\.wrong) }
    var selectedWrong: String? { selectedWrongValues.count == 1 ? selectedWrongValues.first : nil }

    init(actions: Actions) {
        self.actions = actions
        super.init(frame: .zero)
        buildView()
        update(entries: [])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(entries: [DictionaryEntry]) {
        self.entries = entries
        applyFilter()
    }

    func setSearchQuery(_ query: String) {
        searchField.stringValue = query
        applyFilter()
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleEntries.indices.contains(row), let identifier = tableColumn?.identifier else { return nil }
        let entry = visibleEntries[row]
        let value = identifier.rawValue == "wrong" ? entry.wrong : entry.correct
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: value)
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 12)
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectedWrongValues = Set(tableView.selectedRowIndexes.compactMap { row in
            visibleEntries.indices.contains(row) ? visibleEntries[row].wrong : nil
        })
        updateActionAvailability()
    }

    private func buildView() {
        let header = PreferencesPageSupport.makePageHeader(
            title: "Dictionary",
            description: "Correct words and phrases Scrawl commonly gets wrong."
        )
        PreferencesPageSupport.configureSecondaryButton(addButton)
        addButton.bezelColor = .controlAccentColor
        bind(addButton) { [weak self] in self?.showEditor(entry: nil) }

        let headerRow = NSStackView(views: [header, NSView(), addButton])
        headerRow.orientation = .horizontal
        headerRow.alignment = .top
        headerRow.spacing = 12

        searchField.placeholderString = "Search replacements"
        searchField.delegate = self

        let wrongColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("wrong"))
        wrongColumn.title = "Heard Text"
        wrongColumn.resizingMask = .autoresizingMask
        let correctColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("correct"))
        correctColumn.title = "Replace With"
        correctColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(wrongColumn)
        tableView.addTableColumn(correctColumn)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.rowHeight = 28
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
        let actions = NSStackView(views: [editButton, deleteButton, NSView()])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 6

        let root = NSStackView(views: [headerRow, searchField, workspace, actions])
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

    private func applyFilter() {
        visibleEntries = PreferencesContentState.filteredDictionary(entries: entries, query: searchField.stringValue)
        let retained = visibleEntries.compactMap { entry in
            selectedWrongValues.contains { entry.wrong.caseInsensitiveCompare($0) == .orderedSame }
                ? entry.wrong
                : nil
        }
        selectedWrongValues = retained.isEmpty ? Set(visibleEntries.first.map { [$0.wrong] } ?? []) : Set(retained)
        tableView.reloadData()
        let indexes = IndexSet(visibleEntries.indices.filter { selectedWrongValues.contains(visibleEntries[$0].wrong) })
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        updateState()
        updateActionAvailability()
    }

    private func updateState() {
        if entries.isEmpty {
            state = .empty
            stateTitle.stringValue = "No dictionary entries yet"
            stateDetail.stringValue = "Add replacements here or from selected transcript text."
        } else if visibleEntries.isEmpty {
            state = .noSearchResults
            stateTitle.stringValue = "No matching replacements"
            stateDetail.stringValue = "Try a different search."
        } else {
            state = .entries
        }
        stateView.isHidden = state == .entries
        tableView.enclosingScrollView?.isHidden = state != .entries
    }

    private func updateActionAvailability() {
        editButton.isEnabled = selectedWrongValues.count == 1
        deleteButton.isEnabled = !selectedWrongValues.isEmpty
    }

    @objc private func editSelected(_ sender: Any?) {
        showEditorForSelection()
    }

    private func showEditorForSelection() {
        guard let selectedWrong, let entry = entries.first(where: {
            $0.wrong.caseInsensitiveCompare(selectedWrong) == .orderedSame
        }) else { return }
        showEditor(entry: entry)
    }

    private func showEditor(entry: DictionaryEntry?) {
        guard let window else { return }
        let heardField = NSTextField(string: entry?.wrong ?? "")
        let replacementField = NSTextField(string: entry?.correct ?? "")
        let errorLabel = NSTextField(wrappingLabelWithString: "")
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        let save = NSButton(title: "Save", target: nil, action: nil)
        save.keyEquivalent = "\r"

        let fields = NSStackView(views: [
            NSTextField(labelWithString: "Heard text"), heardField,
            NSTextField(labelWithString: "Replace with"), replacementField,
            errorLabel
        ])
        fields.orientation = .vertical
        fields.alignment = .width
        fields.spacing = 5
        let buttons = NSStackView(views: [NSView(), cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 6
        let root = NSStackView(views: [fields, buttons])
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 210),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = entry == nil ? "Add Replacement" : "Edit Replacement"
        panel.contentView = root

        let cancelAction = ClosureAction { [weak window] in
            guard let sheet = window?.attachedSheet else { return }
            window?.endSheet(sheet)
        }
        let saveAction = ClosureAction { [weak self, weak window] in
            let wrong = heardField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let correct = replacementField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wrong.isEmpty, !correct.isEmpty else {
                errorLabel.stringValue = "Both fields are required."
                errorLabel.isHidden = false
                return
            }
            save.isEnabled = false
            self?.actions.save(entry?.wrong, wrong, correct) { result in
                switch result {
                case .success:
                    if let sheet = window?.attachedSheet {
                        window?.endSheet(sheet)
                    }
                case let .failure(error):
                    errorLabel.stringValue = error.localizedDescription
                    errorLabel.isHidden = false
                    save.isEnabled = true
                }
            }
        }
        editorActionRetainers = [cancelAction, saveAction]
        cancel.target = cancelAction
        cancel.action = #selector(ClosureAction.perform(_:))
        save.target = saveAction
        save.action = #selector(ClosureAction.perform(_:))
        window.beginSheet(panel)
        window.makeFirstResponder(heardField)
    }

    private func deleteSelected() {
        guard !selectedWrongValues.isEmpty else { return }
        if selectedWrongValues.count > 1 {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Delete \(selectedWrongValues.count) Replacements?"
            alert.informativeText = "This cannot be undone."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        deleteButton.isEnabled = false
        actions.delete(selectedWrongValues) { [weak self] result in
            guard let self else { return }
            self.deleteButton.isEnabled = true
            if case let .failure(error) = result {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }
}

private final class DeleteKeyTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}
