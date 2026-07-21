import AppKit
import QuartzCore

private final class FlippedModelsDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}

/// Soft, inset, rounded coral highlight behind the selected model row — a floating pill
/// rather than a full-bleed macOS selection band.
private final class ModelRowBackgroundView: NSView {
    private let isSelectedRow: Bool
    private let highlightLayer = CALayer()

    init(content: NSView, isSelected: Bool) {
        isSelectedRow = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        highlightLayer.cornerRadius = 9
        highlightLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "backgroundColor": NSNull(),
        ]
        layer?.addSublayer(highlightLayer)
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

    override func layout() {
        super.layout()
        updateHighlightLayer()
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        updateHighlightLayer()
    }

    private func updateHighlightLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightLayer.frame = bounds.insetBy(
            dx: PreferencesPageSupport.selectionPillHorizontalInset,
            dy: PreferencesPageSupport.selectionPillVerticalInset
        )
        effectiveAppearance.performAsCurrentDrawingAppearance {
            highlightLayer.backgroundColor = isSelectedRow
                ? PreferencesPageSupport.selectionTint.cgColor
                : NSColor.clear.cgColor
        }
        CATransaction.commit()
    }
}

/// Thin rounded progress bar with an orange fill, matching the mockup's download row.
private final class MiniProgressBar: NSView {
    private let fraction: Double

    init(fraction: Double) {
        self.fraction = max(0, min(1, fraction))
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let height = bounds.height
        let radius = height / 2

        let track = CALayer()
        track.frame = bounds
        track.cornerRadius = radius
        track.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        layer.addSublayer(track)

        let fill = CALayer()
        fill.frame = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(fraction), height: height)
        fill.cornerRadius = radius
        fill.backgroundColor = PreferencesPageSupport.accentColor.cgColor
        layer.addSublayer(fill)
    }
}

/// Small orange cube glyph used as the model row icon, matching the mockup.
private final class ModelIconView: NSView {
    private let imageView = NSImageView()

    init() {
        super.init(frame: .zero)
        let symbol = NSImage(systemSymbolName: "cube.fill", accessibilityDescription: "Model")
        imageView.image = symbol
        imageView.contentTintColor = PreferencesPageSupport.accentColor
        imageView.symbolConfiguration = .init(pointSize: 20, weight: .regular)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    private let listView = FlippedModelsDocumentView()
    private let scrollContainer = NSView()
    private let modelPicker = NSPopUpButton()
    private let filterField = NSSearchField()
    /// Temporarily shelved: the curated download list covers the practical whisper.cpp
    /// sizes, so the import/reveal affordances mostly added clutter. The models-folder
    /// scan still honors hand-dropped ggml-*.bin files; flipping this back on is the
    /// whole revert.
    private static let showsBringYourOwnModel = false

    private let addButton = NSButton(title: "Add Model…", target: nil, action: nil)
    private let revealButton = NSButton(title: "Reveal Models Folder", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete Selected", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel Download", target: nil, action: nil)
    private var footerHelpLabel: NSTextField?
    private var actionBarView: NSView?

    // Current rows and filter state.
    private var allRows: [PreferencesModelRow] = []
    private var isDownloadInProgress = false
    private var filterQuery = ""
    private var hasRenderedOnce = false

    // Bookkeeping for test accessors.
    private(set) var listRebuildCount = 0
    private var twoLineRowCount = 0
    private var selectedRowHasAction = false
    private var firstActionView: NSView?
    private var firstActionRowView: NSView?
    private var firstTextStackView: NSView?
    private weak var installedSectionLabel: NSTextField?
    private weak var availableSectionLabel: NSTextField?
    private weak var firstSectionCard: NSView?
    private var pickerIDByIndex: [Int: String] = [:]

    // Column metrics shared by header and rows so they line up like the mockup table.
    private let rowContentLeftInset = PreferencesPageSupport.rowInset
    private let rowContentRightInset = PreferencesPageSupport.rowInset
    private let columnSpacing: CGFloat = 12
    private let iconColumnWidth: CGFloat = 28
    private let engineColumnWidth: CGFloat = 62
    private let statusColumnWidth: CGFloat = 120
    private let actionColumnWidth: CGFloat = 92
    private let rowActionButtonWidth: CGFloat = 66
    private let minListHeight: CGFloat = 150
    private let maxListHeight: CGFloat = 460

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
        0
    }

    var visibleModelPickerTitle: String? {
        modelPicker.titleOfSelectedItem
    }

    var visibleColumnHeaderTitles: [String] {
        var titles: [String] = []
        collectColumnHeaderTitles(in: self, into: &titles)
        return titles
    }

    var usesPinnedActionBar: Bool {
        actionBarView is PreferencesPinnedActionBarView
    }

    var visibleSelectedRowHasAction: Bool {
        selectedRowHasAction
    }

    var visibleActionControlsWithinBounds: Bool {
        [addButton, revealButton, deleteButton, cancelButton]
            .filter { !$0.isHidden }
            .allSatisfy {
                bounds.contains(convert($0.bounds, from: $0))
            }
    }

    var visibleModelListHeight: CGFloat {
        scrollContainer.frame.height
    }

    var visibleFirstModelRowHeight: CGFloat? {
        firstSectionCard?.frame.height
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

    var isCriticalContentWithinBounds: Bool {
        [deleteButton, cancelButton, addButton]
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

        listView.translatesAutoresizingMaskIntoConstraints = false
        listView.addSubview(modelsStack)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = listView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        scrollContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollContainer.addSubview(scrollView)
        // The scroll subtree must not impose its content's natural width on the page;
        // let the page stack stretch it to full width instead of right-sizing it.
        for view in [scrollContainer, scrollView] {
            view.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            view.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        }
        let contentHug = scrollContainer.heightAnchor.constraint(equalTo: listView.heightAnchor)
        contentHug.priority = .defaultLow
        // High-but-breakable: at the window's minimum height the whole page cannot fit,
        // and the viewport (which scrolls) must be what gives — never the row content.
        let minHeight = scrollContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: minListHeight)
        minHeight.priority = NSLayoutConstraint.Priority(900)
        NSLayoutConstraint.activate([
            minHeight,
            scrollContainer.heightAnchor.constraint(lessThanOrEqualToConstant: maxListHeight),
            contentHug,
            scrollView.leadingAnchor.constraint(equalTo: scrollContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: scrollContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: scrollContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: scrollContainer.bottomAnchor),
            // Document sized purely top-down: leading AND trailing pinned to the clip so
            // its width follows the clip (which the page stack stretches to full width).
            // No width constraint pushes the content's natural width back up the chain.
            listView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            listView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            modelsStack.leadingAnchor.constraint(equalTo: listView.leadingAnchor),
            modelsStack.trailingAnchor.constraint(equalTo: listView.trailingAnchor),
            modelsStack.topAnchor.constraint(equalTo: listView.topAnchor),
            modelsStack.bottomAnchor.constraint(equalTo: listView.bottomAnchor),
        ])
        scrollView.hasHorizontalScroller = false

        modelPicker.controlSize = .regular
        modelPicker.target = self
        modelPicker.action = #selector(modelPickerChanged(_:))
        modelPicker.translatesAutoresizingMaskIntoConstraints = false
        modelPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        filterField.placeholderString = "Filter models"
        filterField.target = self
        filterField.action = #selector(filterChanged(_:))
        filterField.sendsSearchStringImmediately = true
        filterField.translatesAutoresizingMaskIntoConstraints = false
        filterField.widthAnchor.constraint(equalToConstant: 220).isActive = true

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

        let actionBar = PreferencesPageSupport.makePinnedActionBar(
            leading: Self.showsBringYourOwnModel ? [addButton, revealButton] : [],
            trailing: [deleteButton, cancelButton],
            leadingInset: rowContentLeftInset,
            trailingInset: rowContentRightInset
        )
        actionBarView = actionBar

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
        helpRow.edgeInsets = NSEdgeInsets(top: 0, left: rowContentLeftInset, bottom: 0, right: 0)

        let page = makeModelsPage(listContent: scrollContainer, actionBar: actionBar, helpRow: helpRow)
        PreferencesPageSupport.fill(self, with: page)
        update(rows: [], downloadableModels: [], isDownloadInProgress: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Page chrome shared in spirit with every other page: a toolbar strip carrying the
    /// current-model picker and filter, then the scrolling list and pinned actions inside
    /// one grouped card. Sharing the card language with the other pages is what makes the
    /// Models tab stop looking like a different app.
    private func makeModelsPage(listContent: NSView, actionBar: NSView, helpRow: NSView) -> NSView {
        // Toolbar strip: active-model picker on the left, filter on the right, aligned to the
        // same content grid as the rows below.
        let toolbar = NSStackView(views: [modelPicker, NSView(), filterField])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 12

        let card = PreferencesPageSupport.makeCard(rows: [listContent, actionBar])

        let stack = NSStackView(views: Self.showsBringYourOwnModel ? [toolbar, card, helpRow] : [toolbar, card])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        // `.width` alignment alone does not stretch a child whose content prefers a
        // narrower width (the scroll list), so pin each row to the stack width explicitly.
        for item in stack.arrangedSubviews {
            item.setContentHuggingPriority(.defaultLow, for: .horizontal)
            item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let container = PreferencesPageSupport.makeContentBackground()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: PreferencesPageSupport.pageHorizontalInset),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -PreferencesPageSupport.pageHorizontalInset),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: PreferencesPageSupport.pageVerticalInset),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -PreferencesPageSupport.pageVerticalInset),
        ])
        return container
    }

    func update(rows: [PreferencesModelRow], downloadableModels: [DownloadableModel], isDownloadInProgress: Bool) {
        let newDownloadableModelsByID = Dictionary(uniqueKeysWithValues: downloadableModels.map { ($0.id, $0) })
        // Preferences refreshes fire for many reasons unrelated to models (permissions,
        // history, hotkey); tearing down and recreating every row view for an identical
        // snapshot is pure waste and a measured contributor to model-switch lag.
        if hasRenderedOnce,
           rows == allRows,
           newDownloadableModelsByID == downloadableModelsByID,
           isDownloadInProgress == self.isDownloadInProgress
        {
            return
        }
        hasRenderedOnce = true
        downloadableModelsByID = newDownloadableModelsByID
        allRows = rows
        self.isDownloadInProgress = isDownloadInProgress
        rebuild()
    }

    private func rebuild() {
        listRebuildCount += 1
        deleteButton.isEnabled = allRows.contains { $0.isSelected && $0.isInstalled }
        deleteButton.isHidden = isDownloadInProgress
        cancelButton.isEnabled = isDownloadInProgress
        cancelButton.isHidden = !isDownloadInProgress

        rebuildModelPicker()

        twoLineRowCount = allRows.count
        selectedRowHasAction = false
        firstActionView = nil
        firstActionRowView = nil
        firstTextStackView = nil
        installedSectionLabel = nil
        availableSectionLabel = nil
        firstSectionCard = nil

        for arrangedSubview in modelsStack.arrangedSubviews {
            modelsStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        let filtered = filteredRows()
        guard !filtered.isEmpty else {
            let message = filterQuery.isEmpty ? "No models found" : "No models match \"\(filterQuery)\""
            let emptyLabel = NSTextField(labelWithString: message)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.alignment = .center
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            emptyLabel.heightAnchor.constraint(equalToConstant: 64).isActive = true
            appendModelsRow(emptyLabel)
            return
        }

        let installedRows = filtered.filter(\.isInstalled)
        let availableRows = filtered.filter { !$0.isInstalled }
        if !installedRows.isEmpty {
            installedSectionLabel = addSection(title: "Installed Models", rows: installedRows)
        }
        if !availableRows.isEmpty {
            availableSectionLabel = addSection(title: "Available Downloads", rows: availableRows)
        }
    }

    private func filteredRows() -> [PreferencesModelRow] {
        let query = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allRows }
        return allRows.filter {
            $0.displayName.lowercased().contains(query) || $0.descriptionText.lowercased().contains(query)
        }
    }

    private func rebuildModelPicker() {
        modelPicker.removeAllItems()
        pickerIDByIndex = [:]
        let selectable = allRows.filter(\.isInstalled)
        guard !selectable.isEmpty else {
            modelPicker.isEnabled = false
            modelPicker.addItem(withTitle: "No models")
            return
        }
        modelPicker.isEnabled = true
        for (index, row) in selectable.enumerated() {
            modelPicker.addItem(withTitle: row.displayName)
            pickerIDByIndex[index] = row.id
            if row.isSelected {
                modelPicker.selectItem(at: index)
            }
        }
    }

    /// Adds a full-width row to the list. `.width` alignment alone leaves rows at their
    /// natural width (and right-aligned), so each row's width is pinned explicitly.
    private func appendModelsRow(_ view: NSView) {
        modelsStack.addArrangedSubview(view)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.widthAnchor.constraint(equalTo: modelsStack.widthAnchor).isActive = true
    }

    @discardableResult
    private func addSection(title: String, rows: [PreferencesModelRow]) -> NSTextField {
        let isFirstSection = modelsStack.arrangedSubviews.isEmpty
        let label = PreferencesPageSupport.makeSectionLabel(title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        let header = NSStackView(views: [label, NSView()])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.edgeInsets = NSEdgeInsets(top: isFirstSection ? 10 : 22, left: rowContentLeftInset, bottom: 6, right: rowContentRightInset)
        appendModelsRow(header)

        appendModelsRow(makeColumnHeaderRow())
        appendModelsRow(makeSeparatorRow())

        for (index, row) in rows.enumerated() {
            appendModelsRow(makeModelRow(row))
            if index < rows.count - 1 {
                appendModelsRow(makeSeparatorRow())
            }
        }
        return label
    }

    private func makeColumnHeaderRow() -> NSView {
        func headerLabel(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            return label
        }

        let iconSpacer = NSView()
        iconSpacer.translatesAutoresizingMaskIntoConstraints = false
        iconSpacer.widthAnchor.constraint(equalToConstant: iconColumnWidth).isActive = true

        // Wrap "Model" with a trailing spacer so it expands and left-aligns over the
        // name column, exactly like the data rows' text stack does.
        let model = NSStackView(views: [headerLabel("Model"), NSView()])
        model.orientation = .horizontal
        model.alignment = .centerY
        model.spacing = 0
        let engine = fixedWidth(headerLabel("Engine"), engineColumnWidth)
        let status = fixedWidth(headerLabel("Status"), statusColumnWidth)
        let action = fixedWidth(headerLabel("Action"), actionColumnWidth)

        let stack = NSStackView(views: [iconSpacer, model, engine, status, action])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = columnSpacing
        stack.edgeInsets = NSEdgeInsets(top: 0, left: rowContentLeftInset, bottom: 4, right: rowContentRightInset)
        return ColumnHeaderRowView(content: stack)
    }

    private func makeModelRow(_ row: PreferencesModelRow) -> NSView {
        let icon = ModelIconView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: iconColumnWidth).isActive = true
        icon.heightAnchor.constraint(equalToConstant: iconColumnWidth).isActive = true
        // Icon must not absorb the row's slack, or the name column gets pushed right.
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let nameLabel = NSTextField(labelWithString: row.displayName)
        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Row text must never squash vertically: when the window is squeezed the layout
        // engine relieves pressure at the softest spot, and label intrinsic heights
        // (default 750) were losing to the page chrome's required constraints.
        nameLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let detailLabel = NSTextField(labelWithString: row.descriptionText)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let textStack = NSStackView(views: [nameLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The name column is the flexible one: it greedily absorbs the row's slack so the
        // icon stays left and the Engine/Status/Action columns stay put.
        textStack.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        if firstTextStackView == nil {
            firstTextStackView = textStack
        }

        let engineLabel = NSTextField(labelWithString: row.engineName)
        engineLabel.font = .systemFont(ofSize: 12)
        engineLabel.textColor = .secondaryLabelColor
        engineLabel.lineBreakMode = .byTruncatingTail

        let statusCell = makeStatusCell(row)
        let actionCell = makeActionCell(row)

        let rowStack = NSStackView(views: [
            icon,
            textStack,
            fixedWidth(engineLabel, engineColumnWidth, align: .left),
            fixedWidth(statusCell, statusColumnWidth, align: .left),
            fixedWidth(actionCell, actionColumnWidth),
        ])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.distribution = .fill
        rowStack.spacing = columnSpacing
        let rowVerticalInset: CGFloat = 13
        rowStack.edgeInsets = NSEdgeInsets(
            top: rowVerticalInset,
            left: rowContentLeftInset,
            bottom: rowVerticalInset,
            right: rowContentRightInset
        )

        let rowContainer = ModelRowBackgroundView(content: rowStack, isSelected: row.isSelected)
        // A stack's edge insets and centerY alignment are softer than required, so a
        // height-squeezed window silently collapses them (squashed rows, clipped text).
        // Give the row a required floor — insets plus its tallest column — so the
        // pressure lands on the scroll viewport, which can actually scroll.
        NSLayoutConstraint.activate([
            rowContainer.heightAnchor.constraint(
                greaterThanOrEqualTo: textStack.heightAnchor, constant: rowVerticalInset * 2
            ),
            rowContainer.heightAnchor.constraint(
                greaterThanOrEqualTo: statusCell.heightAnchor, constant: rowVerticalInset * 2
            ),
        ])
        if firstSectionCard == nil {
            firstSectionCard = rowContainer
        }
        if firstActionView == nil {
            firstActionView = actionCell
            firstActionRowView = rowContainer
        }
        if row.isSelected {
            selectedRowHasAction = true
        }
        return rowContainer
    }

    private func makeStatusCell(_ row: PreferencesModelRow) -> NSView {
        let primary = NSStackView()
        primary.orientation = .horizontal
        primary.alignment = .centerY
        primary.spacing = 6

        if !row.isDownloading {
            let dot = StatusDotView(color: statusDotColor(for: row))
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            primary.addArrangedSubview(dot)
        }

        let statusLabel = NSTextField(labelWithString: row.isDownloading ? downloadHeadline(row) : row.statusText)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .labelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        primary.addArrangedSubview(statusLabel)

        let column = NSStackView(views: [primary])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 3

        if row.isDownloading, let fraction = progressFraction(from: row.downloadProgressText) {
            let bar = MiniProgressBar(fraction: fraction)
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.widthAnchor.constraint(equalToConstant: statusColumnWidth - 12).isActive = true
            bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
            column.addArrangedSubview(bar)
        }

        if let secondary = statusSecondaryText(row) {
            let sizeLabel = NSTextField(labelWithString: secondary)
            sizeLabel.font = .systemFont(ofSize: 11)
            sizeLabel.textColor = .secondaryLabelColor
            sizeLabel.lineBreakMode = .byTruncatingTail
            column.addArrangedSubview(sizeLabel)
        }
        return column
    }

    private func makeActionCell(_ row: PreferencesModelRow) -> NSView {
        let leading: NSView
        // The active (installed + selected) model shows a coral "Active" marker rather than a
        // disabled "Use" button, which used to read as broken/greyed-out.
        if row.isInstalled, row.isSelected, !row.isDownloading {
            leading = makeActiveMarker()
        } else {
            let button = NSButton(title: actionButtonTitle(row), target: self, action: nil)
            button.identifier = NSUserInterfaceItemIdentifier(row.id)
            PreferencesPageSupport.configureSecondaryButton(button)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: rowActionButtonWidth).isActive = true

            if row.isDownloading {
                button.action = #selector(cancelDownloadAction(_:))
                button.isEnabled = isDownloadInProgress
            } else if row.isInstalled {
                button.action = #selector(selectModelAction(_:))
                button.isEnabled = row.canSelect
            } else {
                button.action = #selector(downloadModelAction(_:))
                button.isEnabled = row.canDownload && !isDownloadInProgress
            }
            leading = button
        }

        return leading
    }

    /// Coral "✓ Active" marker for the currently-selected model row.
    private func makeActiveMarker() -> NSView {
        let check = NSImageView(image: NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: "Active model"
        ) ?? NSImage())
        check.contentTintColor = PreferencesPageSupport.accentColor
        check.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        check.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Active")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = PreferencesPageSupport.accentColor

        let marker = NSStackView(views: [check, label])
        marker.orientation = .horizontal
        marker.alignment = .centerY
        marker.spacing = 4
        marker.translatesAutoresizingMaskIntoConstraints = false
        marker.widthAnchor.constraint(equalToConstant: rowActionButtonWidth).isActive = true
        return marker
    }

    // MARK: - Row content helpers

    private func actionButtonTitle(_ row: PreferencesModelRow) -> String {
        if row.isDownloading { return "Cancel" }
        if row.isInstalled { return "Use" }
        return "Download"
    }

    private func statusDotColor(for row: PreferencesModelRow) -> NSColor {
        if row.isInstalled { return .systemGreen }
        if row.isCancelled { return .systemOrange }
        return .tertiaryLabelColor
    }

    private func downloadHeadline(_ row: PreferencesModelRow) -> String {
        if let fraction = progressFraction(from: row.downloadProgressText) {
            return "Downloading \(Int((fraction * 100).rounded()))%"
        }
        return "Downloading"
    }

    /// The secondary status line: the byte counter while downloading, otherwise the size.
    private func statusSecondaryText(_ row: PreferencesModelRow) -> String? {
        if row.isDownloading {
            return byteCounter(from: row.downloadProgressText) ?? row.sizeText
        }
        return row.sizeText
    }

    private func progressFraction(from text: String?) -> Double? {
        guard
            let text,
            let range = text.range(of: #"\d+(?=%)"#, options: .regularExpression),
            let value = Double(text[range])
        else {
            return nil
        }
        return min(1, max(0, value / 100))
    }

    /// Extracts "630/1500 MB" -> "630 MB of 1.5 GB"-style counter from progress text.
    private func byteCounter(from text: String?) -> String? {
        guard
            let text,
            let open = text.firstIndex(of: "("),
            let close = text.firstIndex(of: ")"),
            open < close
        else {
            return nil
        }
        return String(text[text.index(after: open)..<close])
    }

    // MARK: - Actions

    @objc private func modelPickerChanged(_ sender: NSPopUpButton) {
        guard let id = pickerIDByIndex[sender.indexOfSelectedItem] else { return }
        selectModel(id)
    }

    @objc private func filterChanged(_ sender: NSSearchField) {
        filterQuery = sender.stringValue
        rebuild()
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

    // MARK: - Layout helpers

    private func fixedWidth(_ view: NSView, _ width: CGFloat, align: NSLayoutConstraint.Attribute = .left) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        container.widthAnchor.constraint(equalToConstant: width).isActive = true
        container.setContentHuggingPriority(.required, for: .horizontal)
        container.setContentCompressionResistancePriority(.required, for: .horizontal)
        var constraints: [NSLayoutConstraint] = [
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]
        switch align {
        case .right:
            constraints.append(view.trailingAnchor.constraint(equalTo: container.trailingAnchor))
            constraints.append(view.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor))
        default:
            constraints.append(view.leadingAnchor.constraint(equalTo: container.leadingAnchor))
            constraints.append(view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        return container
    }

    private func makeSeparatorRow() -> NSView {
        PreferencesPageSupport.makeInsetSeparator()
    }

    private func collectColumnHeaderTitles(in view: NSView, into titles: inout [String]) {
        if view is ColumnHeaderRowView {
            collectLabels(in: view, into: &titles)
            return
        }
        for subview in view.subviews {
            collectColumnHeaderTitles(in: subview, into: &titles)
        }
    }

    private func collectLabels(in view: NSView, into titles: inout [String]) {
        if let field = view as? NSTextField, !field.stringValue.isEmpty {
            titles.append(field.stringValue)
        }
        for subview in view.subviews {
            collectLabels(in: subview, into: &titles)
        }
    }
}

/// Marker view so tests can find the column-header row.
private final class ColumnHeaderRowView: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
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
}

private final class StatusDotView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        layer?.cornerRadius = bounds.height / 2
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = color.cgColor
        }
    }
}

private extension NSView {
    func countDescendants<T: NSView>(ofType type: T.Type) -> Int {
        subviews.reduce(self is T ? 1 : 0) { count, subview in
            count + subview.countDescendants(ofType: type)
        }
    }
}
