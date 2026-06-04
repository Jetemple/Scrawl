import AppKit
import Permissions
import SettingsStore

final class PreferencesWindowController: NSWindowController {
    struct Actions {
        let selectModel: (String) -> Void
        let downloadModel: (DownloadableModel) -> Void
        let deleteSelectedModel: () -> Void
        let setHotkey: () -> Void
        let requestMicrophone: () -> Void
        let requestAccessibility: () -> Void
    }

    struct Snapshot {
        let settings: AppSettings
        let downloadableModels: [DownloadableModel]
        let modelRows: [PreferencesModelRow]
        let microphoneStatus: PermissionStatus
        let accessibilityStatus: PermissionStatus
        let isCapturingHotkey: Bool
        let isModelDownloadInProgress: Bool
    }

    private enum Section: Int, CaseIterable {
        case general
        case models
        case hotkey

        var title: String {
            switch self {
            case .general:
                return "General"
            case .models:
                return "Models"
            case .hotkey:
                return "Hotkey"
            }
        }
    }

    private let actions: Actions
    private var downloadableModelsByID: [String: DownloadableModel] = [:]
    private var sectionViews: [Section: NSView] = [:]
    private var selectedSection = Section.general
    private var didCenterWindow = false

    private lazy var segmentedControl: NSSegmentedControl = {
        let control = NSSegmentedControl(
            labels: Section.allCases.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(selectSection(_:))
        )
        control.selectedSegment = selectedSection.rawValue
        control.translatesAutoresizingMaskIntoConstraints = false
        control.segmentStyle = .rounded
        return control
    }()

    private let contentContainer = NSView()

    private let currentModelValueLabel = NSTextField(labelWithString: "")
    private let generalHotkeyValueLabel = NSTextField(labelWithString: "")
    private let microphoneStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let microphoneButton = NSButton(title: "Request", target: nil, action: nil)
    private let accessibilityButton = NSButton(title: "Open Prompt", target: nil, action: nil)

    private let modelsStack = NSStackView()
    private let deleteSelectedModelButton = NSButton(title: "Delete Selected", target: nil, action: nil)

    private let hotkeyValueLabel = NSTextField(labelWithString: "")
    private let captureHotkeyButton = NSButton(title: "Set Hotkey...", target: nil, action: nil)

    init(actions: Actions) {
        self.actions = actions

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Scrawl Settings"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 540, height: 360)
        window.identifier = NSUserInterfaceItemIdentifier("ScrawlPreferencesWindow")

        super.init(window: window)
        window.contentView = makeContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if !didCenterWindow {
            window?.center()
            didCenterWindow = true
        }
        window?.makeKeyAndOrderFront(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func update(snapshot: Snapshot) {
        downloadableModelsByID = Dictionary(uniqueKeysWithValues: snapshot.downloadableModels.map { ($0.id, $0) })

        currentModelValueLabel.stringValue = PreferencesModelState.displayName(forInstalledModelID: snapshot.settings.modelID)
        generalHotkeyValueLabel.stringValue = snapshot.isCapturingHotkey ? "Waiting for input..." : snapshot.settings.hotkey.displayName

        updateStatusLabel(microphoneStatusLabel, status: snapshot.microphoneStatus)
        microphoneButton.isHidden = snapshot.microphoneStatus == .authorized

        updateStatusLabel(accessibilityStatusLabel, status: snapshot.accessibilityStatus)
        accessibilityButton.isHidden = snapshot.accessibilityStatus == .authorized

        rebuildModelRows(from: snapshot)
        deleteSelectedModelButton.isEnabled = snapshot.modelRows.contains { $0.id == snapshot.settings.modelID && $0.isInstalled }

        hotkeyValueLabel.stringValue = snapshot.isCapturingHotkey ? "Waiting for input..." : snapshot.settings.hotkey.displayName
        captureHotkeyButton.title = snapshot.isCapturingHotkey ? "Cancel Capture" : "Set Hotkey..."
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(segmentedControl)
        root.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            segmentedControl.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            segmentedControl.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            segmentedControl.widthAnchor.constraint(equalToConstant: 250),

            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 18),
            contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        sectionViews = [
            .general: makeGeneralSection(),
            .models: makeModelsSection(),
            .hotkey: makeHotkeySection()
        ]

        for (section, view) in sectionViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isHidden = section != selectedSection
            contentContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
            ])
        }

        return root
    }

    private func makeGeneralSection() -> NSView {
        let stack = makeSectionStack()
        stack.addArrangedSubview(makeSectionTitle("Core"))
        stack.addArrangedSubview(makeSettingsGroup([
            makeSettingRow(title: "Current Model", valueLabel: currentModelValueLabel),
            makeSettingRow(title: "Hotkey", valueLabel: generalHotkeyValueLabel)
        ]))
        stack.addArrangedSubview(makeSectionTitle("Permissions"))
        stack.addArrangedSubview(makeSettingsGroup([
            makeSettingRow(title: "Microphone", valueLabel: microphoneStatusLabel, button: microphoneButton),
            makeSettingRow(title: "Accessibility", valueLabel: accessibilityStatusLabel, button: accessibilityButton)
        ]))
        stack.addArrangedSubview(NSView())

        configureSecondaryButton(microphoneButton)
        microphoneButton.target = self
        microphoneButton.action = #selector(requestMicrophone(_:))

        configureSecondaryButton(accessibilityButton)
        accessibilityButton.target = self
        accessibilityButton.action = #selector(requestAccessibility(_:))

        return makePaddedContainer(stack)
    }

    private func makeModelsSection() -> NSView {
        let stack = makeSectionStack()
        stack.addArrangedSubview(makeSectionTitle("Models"))

        modelsStack.orientation = .vertical
        modelsStack.alignment = .width
        modelsStack.spacing = 0
        modelsStack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(modelsStack)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView

        let listBackground = makeRoundedBackground()
        listBackground.addSubview(scrollView)

        stack.addArrangedSubview(listBackground)
        stack.addArrangedSubview(deleteSelectedModelButton)

        NSLayoutConstraint.activate([
            listBackground.widthAnchor.constraint(equalToConstant: 484),
            listBackground.heightAnchor.constraint(equalToConstant: 216),
            scrollView.leadingAnchor.constraint(equalTo: listBackground.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: listBackground.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: listBackground.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: listBackground.bottomAnchor),
            modelsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            modelsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            modelsStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            modelsStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            modelsStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        configureSecondaryButton(deleteSelectedModelButton)
        deleteSelectedModelButton.target = self
        deleteSelectedModelButton.action = #selector(deleteSelectedModel(_:))

        return makePaddedContainer(stack)
    }

    private func makeHotkeySection() -> NSView {
        let stack = makeSectionStack()
        stack.addArrangedSubview(makeSectionTitle("Keyboard"))
        stack.addArrangedSubview(makeSettingsGroup([
            makeSettingRow(title: "Current Hotkey", valueLabel: hotkeyValueLabel, button: captureHotkeyButton)
        ]))
        stack.addArrangedSubview(NSView())

        captureHotkeyButton.bezelStyle = .rounded
        captureHotkeyButton.controlSize = .regular
        captureHotkeyButton.target = self
        captureHotkeyButton.action = #selector(setHotkey(_:))

        return makePaddedContainer(stack)
    }

    private func makeSectionStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makePaddedContainer(_ stack: NSStackView) -> NSView {
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
        ])
        return container
    }

    private func makeSectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func makeSettingsGroup(_ rows: [NSView]) -> NSView {
        let group = makeRoundedBackground()
        group.widthAnchor.constraint(equalToConstant: 484).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(stack)

        for (index, row) in rows.enumerated() {
            stack.addArrangedSubview(row)
            if index < rows.count - 1 {
                stack.addArrangedSubview(makeSeparator())
            }
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            stack.topAnchor.constraint(equalTo: group.topAnchor),
            stack.bottomAnchor.constraint(equalTo: group.bottomAnchor)
        ])

        return group
    }

    private func makeRoundedBackground() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        view.layer?.borderWidth = 1
        return view
    }

    private func makeSettingRow(title: String, valueLabel: NSTextField, button: NSButton? = nil) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: 130).isActive = true

        valueLabel.font = .systemFont(ofSize: 13)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)

        if let button {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 106).isActive = true
            row.addArrangedSubview(button)
        }

        row.widthAnchor.constraint(greaterThanOrEqualToConstant: 484).isActive = true
        return row
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func configureSecondaryButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .small
    }

    private func updateStatusLabel(_ label: NSTextField, status: PermissionStatus) {
        label.stringValue = statusText(for: status)
        switch status {
        case .authorized:
            label.textColor = .systemGreen
        case .denied:
            label.textColor = .systemRed
        case .notDetermined:
            label.textColor = .secondaryLabelColor
        }
    }

    private func rebuildModelRows(from snapshot: Snapshot) {
        modelsStack.arrangedSubviews.forEach { view in
            modelsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !snapshot.modelRows.isEmpty else {
            let emptyLabel = NSTextField(labelWithString: "No models found")
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.alignment = .center
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            emptyLabel.heightAnchor.constraint(equalToConstant: 48).isActive = true
            modelsStack.addArrangedSubview(emptyLabel)
            return
        }

        for (index, row) in snapshot.modelRows.enumerated() {
            modelsStack.addArrangedSubview(makeModelRow(row, isDownloadBlocked: snapshot.isModelDownloadInProgress))
            if index < snapshot.modelRows.count - 1 {
                modelsStack.addArrangedSubview(makeSeparator())
            }
        }
    }

    private func makeModelRow(_ row: PreferencesModelRow, isDownloadBlocked: Bool) -> NSView {
        let nameLabel = NSTextField(labelWithString: row.displayName)
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let statusLabel = NSTextField(labelWithString: row.statusText)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = row.isSelected ? .systemBlue : .secondaryLabelColor
        statusLabel.alignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.widthAnchor.constraint(equalToConstant: 84).isActive = true

        let actionButton = NSButton(title: row.actionTitle, target: self, action: nil)
        actionButton.identifier = NSUserInterfaceItemIdentifier(row.id)
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.widthAnchor.constraint(equalToConstant: 92).isActive = true

        if row.isInstalled {
            actionButton.action = #selector(selectModel(_:))
            actionButton.isEnabled = row.canSelect
        } else {
            actionButton.action = #selector(downloadModel(_:))
            actionButton.isEnabled = row.canDownload && !isDownloadBlocked
        }

        let rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 12
        rowStack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.addArrangedSubview(nameLabel)
        rowStack.addArrangedSubview(statusLabel)
        rowStack.addArrangedSubview(actionButton)

        rowStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 484).isActive = true
        return rowStack
    }

    private func statusText(for status: PermissionStatus) -> String {
        switch status {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Requested"
        }
    }

    @objc private func selectSection(_ sender: NSSegmentedControl) {
        guard let section = Section(rawValue: sender.selectedSegment) else {
            return
        }
        selectedSection = section
        for (candidate, view) in sectionViews {
            view.isHidden = candidate != section
        }
    }

    @objc private func selectModel(_ sender: NSButton) {
        guard let modelID = sender.identifier?.rawValue else {
            return
        }
        actions.selectModel(modelID)
    }

    @objc private func downloadModel(_ sender: NSButton) {
        guard
            let modelID = sender.identifier?.rawValue,
            let model = downloadableModelsByID[modelID]
        else {
            return
        }
        actions.downloadModel(model)
    }

    @objc private func deleteSelectedModel(_ sender: NSButton) {
        actions.deleteSelectedModel()
    }

    @objc private func setHotkey(_ sender: NSButton) {
        actions.setHotkey()
    }

    @objc private func requestMicrophone(_ sender: NSButton) {
        actions.requestMicrophone()
    }

    @objc private func requestAccessibility(_ sender: NSButton) {
        actions.requestAccessibility()
    }
}
