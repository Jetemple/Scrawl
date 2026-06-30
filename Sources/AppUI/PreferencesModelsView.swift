import AppKit

private final class FlippedModelsDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}

private final class ModelRowBackgroundView: NSView {
    private let isSelectedRow: Bool

    init(content: NSView, isSelected: Bool) {
        isSelectedRow = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isSelectedRow
                ? NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
                : NSColor.clear.cgColor
        }
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
    private var footerHelpLabel: NSTextField?
    private var listHeightConstraint: NSLayoutConstraint?
    private var twoLineRowCount = 0
    private var modelInfoButtonCount = 0
    private var selectedRowHasAction = false
    private var selectedIndicatorView: NSView?
    private var selectedActionSlotView: NSView?
    private var firstActionView: NSView?
    private var firstActionRowView: NSView?
    private var firstTextStackView: NSView?
    private weak var installedSectionLabel: NSTextField?
    private weak var availableSectionLabel: NSTextField?
    private var modelInfoPopover: NSPopover?
    private let rowActionWidth: CGFloat = 86
    private let selectedIndicatorWidth: CGFloat = 28
    private let rowContentLeftInset: CGFloat = 18
    private let rowContentRightInset: CGFloat = 12
    private let estimatedRowHeight: CGFloat = 55

    var listIsTopAnchored: Bool {
        modelsStack.superview?.isFlipped == true
    }

    var visibleTwoLineRowCount: Int {
        twoLineRowCount
    }

    var visibleInstalledSectionTitle: String? {
        installedSectionLabel?.stringValue
    }

    var visibleAvailableSectionTitle: String? {
        availableSectionLabel?.stringValue
    }

    var visibleModelSearchFieldCount: Int {
        countDescendants(ofType: NSSearchField.self)
    }

    var visibleModelInfoButtonCount: Int {
        modelInfoButtonCount
    }

    var visibleSelectedRowHasAction: Bool {
        selectedRowHasAction
    }

    var visibleActionControlsWithinBounds: Bool {
        [addButton, revealButton, deleteButton, cancelButton, findModelsButton]
            .filter { !$0.isHidden }
            .allSatisfy {
                bounds.contains(convert($0.bounds, from: $0))
            }
    }

    var visibleSelectedIndicatorWidth: CGFloat? {
        selectedIndicatorView?.frame.width
    }

    var visibleSelectedActionSlotWidth: CGFloat? {
        selectedActionSlotView?.frame.width
    }

    var visibleModelListHeight: CGFloat {
        listHeightConstraint?.constant ?? 0
    }

    var visibleFirstActionCenterYOffset: CGFloat? {
        guard let firstActionView, let firstActionRowView else { return nil }
        let actionFrame = convert(firstActionView.bounds, from: firstActionView)
        let rowFrame = convert(firstActionRowView.bounds, from: firstActionRowView)
        return actionFrame.midY - rowFrame.midY
    }

    var visibleFirstRowTextMinX: CGFloat? {
        guard let firstTextStackView else { return nil }
        return convert(firstTextStackView.bounds, from: firstTextStackView).minX
    }

    var visibleFirstRowTextLeftInset: CGFloat? {
        guard let visibleFirstRowTextMinX else { return nil }
        let listFrame = convert(listView.bounds, from: listView)
        return visibleFirstRowTextMinX - listFrame.minX
    }

    var visibleFooterControlsMinX: CGFloat? {
        convert(addButton.bounds, from: addButton).minX
    }

    var visibleFooterHelpMinX: CGFloat? {
        guard let footerHelpLabel else { return nil }
        return convert(footerHelpLabel.bounds, from: footerHelpLabel).minX
    }

    var isCriticalContentWithinBounds: Bool {
        [listView, deleteButton]
            .filter { !$0.isHidden }
            .allSatisfy {
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
        findModelsButton.isHidden = true

        let buttonRow = NSStackView(views: [addButton, revealButton, findModelsButton, NSView(), deleteButton, cancelButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.edgeInsets = NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 0)

        let helpLabel = NSTextField(labelWithString: "Bring your own: any whisper.cpp ggml .bin.")
        helpLabel.font = .systemFont(ofSize: 11)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.lineBreakMode = .byTruncatingTail
        helpLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footerHelpLabel = helpLabel
        let helpRow = NSStackView(views: [helpLabel, NSView()])
        helpRow.orientation = .horizontal
        helpRow.alignment = .centerY
        helpRow.spacing = 0
        helpRow.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)

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
        deleteButton.isHidden = isDownloadInProgress
        cancelButton.isEnabled = isDownloadInProgress
        cancelButton.isHidden = !isDownloadInProgress
        findModelsButton.isHidden = true
        twoLineRowCount = rows.count
        modelInfoButtonCount = 0
        selectedRowHasAction = false
        selectedIndicatorView = nil
        selectedActionSlotView = nil
        firstActionView = nil
        firstActionRowView = nil
        firstTextStackView = nil
        installedSectionLabel = nil
        availableSectionLabel = nil
        listHeightConstraint?.constant = modelListHeight(rowCount: rows.count)

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

        let installedRows = rows.filter(\.isInstalled)
        let availableRows = rows.filter { !$0.isInstalled }
        if !installedRows.isEmpty {
            installedSectionLabel = addSection(title: "Installed Models", rows: installedRows, isDownloadBlocked: isDownloadInProgress)
        }
        if !availableRows.isEmpty {
            availableSectionLabel = addSection(title: "Available Downloads", rows: availableRows, isDownloadBlocked: isDownloadInProgress)
        }
    }

    @discardableResult
    private func addSection(title: String, rows: [PreferencesModelRow], isDownloadBlocked: Bool) -> NSTextField {
        let label = PreferencesPageSupport.makeSectionLabel(title)
        let header = NSStackView(views: [label, NSView()])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.edgeInsets = NSEdgeInsets(top: modelsStack.arrangedSubviews.isEmpty ? 10 : 14, left: rowContentLeftInset, bottom: 6, right: rowContentRightInset)
        modelsStack.addArrangedSubview(header)

        for (index, row) in rows.enumerated() {
            modelsStack.addArrangedSubview(makeModelRow(row, isDownloadBlocked: isDownloadBlocked))
            if index < rows.count - 1 {
                modelsStack.addArrangedSubview(PreferencesPageSupport.makeSeparator())
            }
        }
        return label
    }

    private func makeModelRow(_ row: PreferencesModelRow, isDownloadBlocked: Bool) -> NSView {
        let nameLabel = NSTextField(labelWithString: row.displayName)
        nameLabel.font = .systemFont(ofSize: 13, weight: row.isSelected ? .medium : .regular)
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
        statusLabel.textColor = statusColor(for: row)
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
            checkmark.setContentHuggingPriority(.required, for: .horizontal)
            checkmark.setContentCompressionResistancePriority(.required, for: .horizontal)
            checkmark.translatesAutoresizingMaskIntoConstraints = false
            checkmark.widthAnchor.constraint(equalToConstant: selectedIndicatorWidth).isActive = true

            let selectedSlot = NSView()
            selectedSlot.translatesAutoresizingMaskIntoConstraints = false
            selectedSlot.addSubview(checkmark)
            NSLayoutConstraint.activate([
                selectedSlot.widthAnchor.constraint(equalToConstant: rowActionWidth),
                selectedSlot.heightAnchor.constraint(equalToConstant: 20),
                checkmark.centerXAnchor.constraint(equalTo: selectedSlot.centerXAnchor),
                checkmark.centerYAnchor.constraint(equalTo: selectedSlot.centerYAnchor),
            ])
            actionArea = selectedSlot
            selectedIndicatorView = checkmark
            selectedActionSlotView = selectedSlot
        } else {
            let actionButton = NSButton(title: row.actionTitle, target: self, action: nil)
            actionButton.identifier = NSUserInterfaceItemIdentifier(row.id)
            PreferencesPageSupport.configureSecondaryButton(actionButton)
            actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            if row.isInstalled {
                actionButton.action = #selector(selectModelAction(_:))
                actionButton.isEnabled = row.canSelect
            } else {
                actionButton.action = #selector(downloadModelAction(_:))
                actionButton.isEnabled = row.canDownload && !isDownloadBlocked
            }
            actionButton.translatesAutoresizingMaskIntoConstraints = false
            actionButton.widthAnchor.constraint(equalToConstant: rowActionWidth).isActive = true
            actionArea = actionButton
        }

        let textStack = NSStackView(views: [nameLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if firstTextStackView == nil {
            firstTextStackView = textStack
        }

        let infoButton = NSButton(image: NSImage(
            systemSymbolName: "info.circle",
            accessibilityDescription: "Model details"
        ) ?? NSImage(), target: self, action: #selector(showModelInfoAction(_:)))
        infoButton.identifier = NSUserInterfaceItemIdentifier(row.id)
        infoButton.isBordered = false
        infoButton.controlSize = .small
        infoButton.imagePosition = .imageOnly
        infoButton.contentTintColor = .secondaryLabelColor
        infoButton.toolTip = "Show model details"
        infoButton.translatesAutoresizingMaskIntoConstraints = false
        infoButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        modelInfoButtonCount += 1

        let rowStack = NSStackView(views: [textStack, NSView(), statusLabel, infoButton, actionArea])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 8
        rowStack.edgeInsets = NSEdgeInsets(
            top: 8,
            left: rowContentLeftInset,
            bottom: 8,
            right: rowContentRightInset
        )
        let rowContainer = ModelRowBackgroundView(content: rowStack, isSelected: row.isSelected)
        if !row.isSelected, firstActionView == nil {
            firstActionView = actionArea
            firstActionRowView = rowContainer
        }
        return rowContainer
    }

    private func modelListHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 128 }
        let separatorHeight = CGFloat(max(0, rowCount - 1))
        return min(300, max(128, CGFloat(rowCount) * estimatedRowHeight + separatorHeight))
    }

    private func statusColor(for row: PreferencesModelRow) -> NSColor {
        if row.isCancelled { return .systemOrange }
        if row.isSelected || row.isDownloading || row.isPreparing { return .systemBlue }
        return .secondaryLabelColor
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

    @objc private func showModelInfoAction(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        let name = PreferencesModelState.displayName(forModelID: id)
        let detail = PreferencesModelState.description(forModelID: id)
        let content = NSStackView(views: [
            NSTextField(labelWithString: name),
            NSTextField(wrappingLabelWithString: detail),
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        content.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let popover = NSPopover()
        let controller = NSViewController()
        controller.view = content
        popover.contentViewController = controller
        popover.behavior = .transient
        modelInfoPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }
}

private extension NSView {
    func countDescendants<T: NSView>(ofType type: T.Type) -> Int {
        subviews.reduce(self is T ? 1 : 0) { count, subview in
            count + subview.countDescendants(ofType: type)
        }
    }
}
