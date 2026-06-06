import AppKit

final class PreferencesModelsView: NSView {
    private let selectModel: (String) -> Void
    private let downloadModel: (DownloadableModel) -> Void
    private let deleteSelectedModel: () -> Void
    private var downloadableModelsByID: [String: DownloadableModel] = [:]

    private let modelsStack = NSStackView()
    private let listView = PreferencesPageSupport.makeRoundedBackground()
    private let deleteButton = NSButton(title: "Delete Selected", target: nil, action: nil)

    var isCriticalContentWithinBounds: Bool {
        [listView, deleteButton].allSatisfy {
            bounds.contains(convert($0.bounds, from: $0))
        }
    }

    init(
        selectModel: @escaping (String) -> Void,
        downloadModel: @escaping (DownloadableModel) -> Void,
        deleteSelectedModel: @escaping () -> Void
    ) {
        self.selectModel = selectModel
        self.downloadModel = downloadModel
        self.deleteSelectedModel = deleteSelectedModel
        super.init(frame: .zero)

        modelsStack.orientation = .vertical
        modelsStack.alignment = .width
        modelsStack.spacing = 0
        modelsStack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(modelsStack)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        listView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            listView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
            scrollView.leadingAnchor.constraint(equalTo: listView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: listView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: listView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: listView.bottomAnchor),
            modelsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            modelsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            modelsStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            modelsStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            modelsStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        PreferencesPageSupport.configureSecondaryButton(deleteButton)
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected(_:))

        let page = PreferencesPageSupport.makePage(
            title: "Models",
            description: "Select an installed model or download another.",
            content: [listView, PreferencesPageSupport.makeButtonRow(deleteButton)]
        )
        PreferencesPageSupport.fill(self, with: page)
        update(rows: [], downloadableModels: [], isDownloadInProgress: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(rows: [PreferencesModelRow], downloadableModels: [DownloadableModel], isDownloadInProgress: Bool) {
        downloadableModelsByID = Dictionary(uniqueKeysWithValues: downloadableModels.map { ($0.id, $0) })
        deleteButton.isEnabled = rows.contains { $0.isSelected && $0.isInstalled }

        modelsStack.arrangedSubviews.forEach {
            modelsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard !rows.isEmpty else {
            let emptyLabel = NSTextField(labelWithString: "No models found")
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.alignment = .center
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            emptyLabel.heightAnchor.constraint(equalToConstant: 48).isActive = true
            modelsStack.addArrangedSubview(emptyLabel)
            return
        }

        for (index, row) in rows.enumerated() {
            modelsStack.addArrangedSubview(makeModelRow(row, isDownloadBlocked: isDownloadInProgress))
            if index < rows.count - 1 {
                modelsStack.addArrangedSubview(PreferencesPageSupport.makeSeparator())
            }
        }
    }

    private func makeModelRow(_ row: PreferencesModelRow, isDownloadBlocked: Bool) -> NSView {
        let nameLabel = NSTextField(labelWithString: row.displayName)
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let statusLabel = NSTextField(labelWithString: row.statusText)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = row.isSelected ? .systemBlue : .secondaryLabelColor
        statusLabel.alignment = .right

        let actionButton = NSButton(title: row.actionTitle, target: self, action: nil)
        actionButton.identifier = NSUserInterfaceItemIdentifier(row.id)
        PreferencesPageSupport.configureSecondaryButton(actionButton)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
        if row.isInstalled {
            actionButton.action = #selector(selectModelAction(_:))
            actionButton.isEnabled = row.canSelect
        } else {
            actionButton.action = #selector(downloadModelAction(_:))
            actionButton.isEnabled = row.canDownload && !isDownloadBlocked
        }

        let stack = NSStackView(views: [nameLabel, statusLabel, actionButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        return stack
    }

    @objc private func selectModelAction(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        selectModel(id)
    }

    @objc private func downloadModelAction(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let model = downloadableModelsByID[id] else { return }
        downloadModel(model)
    }

    @objc private func deleteSelected(_ sender: NSButton) {
        deleteSelectedModel()
    }
}
