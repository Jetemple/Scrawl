import AppKit

private final class FlippedModelsDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}

final class PreferencesModelsView: NSView {
    private let selectModel: (String) -> Void
    private let downloadModel: (DownloadableModel) -> Void
    private let deleteSelectedModel: () -> Void
    private let cancelDownload: () -> Void
    private let addModel: () -> Void
    private let revealModelsFolder: () -> Void
    private let openModelSource: () -> Void
    private var downloadableModelsByID: [String: DownloadableModel] = [:]

    private let modelsStack = NSStackView()
    private let listView = PreferencesPageSupport.makeRoundedBackground()
    private let addButton = NSButton(title: "Add Model…", target: nil, action: nil)
    private let revealButton = NSButton(title: "Reveal Models Folder", target: nil, action: nil)
    private let findModelsButton = NSButton(title: "Find Models", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete Selected", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel Download", target: nil, action: nil)
    private var listHeightConstraint: NSLayoutConstraint?
    private var twoLineRowCount = 0
    private var selectedRowHasAction = false

    var listIsTopAnchored: Bool {
        modelsStack.superview?.isFlipped == true
    }

    var visibleTwoLineRowCount: Int {
        twoLineRowCount
    }

    var visibleSelectedRowHasAction: Bool {
        selectedRowHasAction
    }

    var isCriticalContentWithinBounds: Bool {
        [listView, deleteButton].allSatisfy {
            bounds.contains(convert($0.bounds, from: $0))
        }
    }

    init(
        selectModel: @escaping (String) -> Void,
        downloadModel: @escaping (DownloadableModel) -> Void,
        deleteSelectedModel: @escaping () -> Void,
        cancelDownload: @escaping () -> Void,
        addModel: @escaping () -> Void,
        revealModelsFolder: @escaping () -> Void,
        openModelSource: @escaping () -> Void
    ) {
        self.selectModel = selectModel
        self.downloadModel = downloadModel
        self.deleteSelectedModel = deleteSelectedModel
        self.cancelDownload = cancelDownload
        self.addModel = addModel
        self.revealModelsFolder = revealModelsFolder
        self.openModelSource = openModelSource
        super.init(frame: .zero)

        modelsStack.orientation = .vertical
        modelsStack.alignment = .width
        modelsStack.spacing = 0
        modelsStack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = FlippedModelsDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(modelsStack)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        listView.addSubview(scrollView)
        let listHeightConstraint = listView.heightAnchor.constraint(equalToConstant: 140)
        self.listHeightConstraint = listHeightConstraint
        NSLayoutConstraint.activate([
            listHeightConstraint,
            scrollView.leadingAnchor.constraint(equalTo: listView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: listView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: listView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: listView.bottomAnchor),
            modelsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            modelsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            modelsStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            modelsStack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor),
            modelsStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        PreferencesPageSupport.configureSecondaryButton(addButton)
        addButton.target = self
        addButton.action = #selector(addModelAction(_:))
        addButton.toolTip = "Import a whisper.cpp ggml model file (.bin) you already have."

        PreferencesPageSupport.configureSecondaryButton(revealButton)
        revealButton.target = self
        revealButton.action = #selector(revealModelsFolderAction(_:))
        revealButton.toolTip = "Open the models folder in Finder to drop in your own ggml-*.bin files."

        PreferencesPageSupport.configureSecondaryButton(deleteButton)
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected(_:))

        PreferencesPageSupport.configureSecondaryButton(cancelButton)
        cancelButton.target = self
        cancelButton.action = #selector(cancelDownloadAction(_:))
        cancelButton.isHidden = true

        // A quiet inline link rather than a full button, so it doesn't compete with
        // the primary Add/Reveal/Delete controls.
        findModelsButton.isBordered = false
        findModelsButton.attributedTitle = NSAttributedString(
            string: findModelsButton.title,
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .font: NSFont.systemFont(ofSize: 11),
            ]
        )
        findModelsButton.target = self
        findModelsButton.action = #selector(openModelSourceAction(_:))
        findModelsButton.toolTip = "Open the whisper.cpp model repository in your browser."

        let buttonRow = NSStackView(views: [addButton, revealButton, NSView(), deleteButton, cancelButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let helpLabel = NSTextField(labelWithString: "Bring your own: any whisper.cpp ggml .bin.")
        helpLabel.font = .systemFont(ofSize: 11)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.lineBreakMode = .byTruncatingTail
        helpLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let helpRow = NSStackView(views: [helpLabel, findModelsButton, NSView()])
        helpRow.orientation = .horizontal
        helpRow.alignment = .centerY
        helpRow.spacing = 6

        let page = PreferencesPageSupport.makePage(
            title: "Models",
            description: "Select an installed model, download another, or add your own.",
            content: [listView, buttonRow, helpRow]
        )
        PreferencesPageSupport.fill(self, with: page)
        update(rows: [], downloadableModels: [], isDownloadInProgress: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(rows: [PreferencesModelRow], downloadableModels: [DownloadableModel], isDownloadInProgress: Bool) {
        downloadableModelsByID = Dictionary(uniqueKeysWithValues: downloadableModels.map { ($0.id, $0) })
        deleteButton.isEnabled = rows.contains { $0.isSelected && $0.isInstalled }
        cancelButton.isEnabled = isDownloadInProgress
        cancelButton.isHidden = !isDownloadInProgress
        twoLineRowCount = rows.count
        selectedRowHasAction = false
        listHeightConstraint?.constant = min(300, max(140, CGFloat(rows.count) * 64))

        for arrangedSubview in modelsStack.arrangedSubviews {
            modelsStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
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

        let detailLabel = NSTextField(labelWithString: row.descriptionText)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.alignment = .left
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let statusLabel = NSTextField(labelWithString: row.statusText)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = row.isSelected ? .systemBlue : .secondaryLabelColor
        statusLabel.alignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        // Size to the status text so longer strings like "Download cancelled" render in
        // full; the name label (low compression resistance) yields space instead.
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let actionArea: NSView
        if row.isSelected {
            let checkmark = NSImageView(image: NSImage(
                systemSymbolName: "checkmark.circle.fill",
                accessibilityDescription: "Selected"
            ) ?? NSImage())
            checkmark.contentTintColor = .systemBlue
            checkmark.symbolConfiguration = .init(pointSize: 13, weight: .medium)
            actionArea = checkmark
        } else {
            let actionButton = NSButton(title: row.actionTitle, target: self, action: nil)
            actionButton.identifier = NSUserInterfaceItemIdentifier(row.id)
            PreferencesPageSupport.configureSecondaryButton(actionButton)
            if row.isInstalled {
                actionButton.action = #selector(selectModelAction(_:))
                actionButton.isEnabled = row.canSelect
            } else {
                actionButton.action = #selector(downloadModelAction(_:))
                actionButton.isEnabled = row.canDownload && !isDownloadBlocked
            }
            actionArea = actionButton
        }
        actionArea.translatesAutoresizingMaskIntoConstraints = false
        actionArea.widthAnchor.constraint(equalToConstant: 88).isActive = true

        let topLine = NSStackView(views: [nameLabel, NSView(), statusLabel, actionArea])
        topLine.orientation = .horizontal
        topLine.alignment = .centerY
        topLine.spacing = 8

        let detailLine = NSStackView(views: [detailLabel, NSView()])
        detailLine.orientation = .horizontal
        detailLine.alignment = .centerY

        let rowStack = NSStackView(views: [topLine, detailLine])
        rowStack.orientation = .vertical
        rowStack.alignment = .width
        rowStack.spacing = 3
        rowStack.edgeInsets = NSEdgeInsets(top: 9, left: 14, bottom: 9, right: 14)
        return rowStack
    }

    @objc private func selectModelAction(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        selectModel(id)
    }

    @objc private func downloadModelAction(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if let model = downloadableModelsByID[id] {
            downloadModel(model)
        } else {
            selectModel(id)
        }
    }

    @objc private func deleteSelected(_: NSButton) {
        deleteSelectedModel()
    }

    @objc private func cancelDownloadAction(_: NSButton) {
        cancelDownload()
    }

    @objc private func addModelAction(_: NSButton) {
        addModel()
    }

    @objc private func revealModelsFolderAction(_: NSButton) {
        revealModelsFolder()
    }

    @objc private func openModelSourceAction(_: NSButton) {
        openModelSource()
    }
}
