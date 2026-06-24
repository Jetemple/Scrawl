import AppKit
import Permissions
import SettingsStore

final class PreferencesGeneralView: NSView {
    private let readinessLabel = NSTextField(labelWithString: "")
    private let modelLabel = NSTextField(labelWithString: "")
    private let hotkeyLabel = NSTextField(labelWithString: "")
    private let microphoneLabel = NSTextField(labelWithString: "")
    private let accessibilityLabel = NSTextField(labelWithString: "")
    private let microphoneButton = NSButton(title: "Request", target: nil, action: nil)
    private let accessibilityButton = NSButton(title: "Open Prompt", target: nil, action: nil)
    private let offloadPopup = NSPopUpButton()
    private let clipboardHistoryCheckbox = NSButton(checkboxWithTitle: "Keep transcripts in clipboard history", target: nil, action: nil)
    private let requestMicrophone: () -> Void
    private let requestAccessibility: () -> Void
    private let setModelOffloadPolicy: (ModelOffloadPolicy) -> Void
    private let setKeepTranscriptsInClipboardHistory: (Bool) -> Void

    var modelOffloadChoices: [String] {
        offloadPopup.itemTitles
    }

    var selectedModelOffloadPolicy: ModelOffloadPolicy? {
        guard offloadPopup.indexOfSelectedItem >= 0 else { return nil }
        return ModelOffloadPolicy.allCases[offloadPopup.indexOfSelectedItem]
    }

    init(
        requestMicrophone: @escaping () -> Void,
        requestAccessibility: @escaping () -> Void,
        setModelOffloadPolicy: @escaping (ModelOffloadPolicy) -> Void,
        setKeepTranscriptsInClipboardHistory: @escaping (Bool) -> Void = { _ in }
    ) {
        self.requestMicrophone = requestMicrophone
        self.requestAccessibility = requestAccessibility
        self.setModelOffloadPolicy = setModelOffloadPolicy
        self.setKeepTranscriptsInClipboardHistory = setKeepTranscriptsInClipboardHistory
        super.init(frame: .zero)

        PreferencesPageSupport.configureSecondaryButton(microphoneButton)
        PreferencesPageSupport.configureSecondaryButton(accessibilityButton)

        microphoneButton.target = self
        microphoneButton.action = #selector(requestMicrophoneAccess(_:))
        accessibilityButton.target = self
        accessibilityButton.action = #selector(requestAccessibilityAccess(_:))
        offloadPopup.addItems(withTitles: ModelOffloadPolicy.allCases.map(\.displayName))
        offloadPopup.controlSize = .small
        offloadPopup.target = self
        offloadPopup.action = #selector(modelOffloadChanged(_:))

        clipboardHistoryCheckbox.target = self
        clipboardHistoryCheckbox.action = #selector(clipboardHistoryChanged(_:))
        clipboardHistoryCheckbox.font = .systemFont(ofSize: 13)

        let clipboardHistorySubtitle = NSTextField(labelWithString: "Allows clipboard managers to save your dictations")
        clipboardHistorySubtitle.font = .systemFont(ofSize: 11)
        clipboardHistorySubtitle.textColor = .secondaryLabelColor

        let clipboardGroup = NSStackView(views: [clipboardHistoryCheckbox, clipboardHistorySubtitle])
        clipboardGroup.orientation = .vertical
        clipboardGroup.alignment = .leading
        clipboardGroup.spacing = 3

        let page = PreferencesPageSupport.makePage(
            title: "General",
            description: "Scrawl readiness and current transcription setup.",
            content: [
                PreferencesPageSupport.makeGroup(rows: [
                    PreferencesPageSupport.makeSettingRow(title: "Readiness", detail: readinessLabel),
                    PreferencesPageSupport.makeSettingRow(title: "Model", detail: modelLabel),
                    PreferencesPageSupport.makeSettingRow(title: "Hotkey", detail: hotkeyLabel),
                    PreferencesPageSupport.makeSettingRow(
                        title: "Offload model",
                        // The popup value (Immediately / 1 minute / … / Never) already states
                        // the timing, so no static detail — a fixed "After inactivity" label
                        // contradicted the "Immediately" and "Never" choices.
                        detail: NSTextField(labelWithString: ""),
                        action: offloadPopup
                    ),
                ]),
                PreferencesPageSupport.makeGroup(rows: [
                    PreferencesPageSupport.makeSettingRow(title: "Microphone", detail: microphoneLabel, action: microphoneButton),
                    PreferencesPageSupport.makeSettingRow(title: "Accessibility", detail: accessibilityLabel, action: accessibilityButton),
                ]),
                clipboardGroup,
            ]
        )
        PreferencesPageSupport.fill(self, with: page)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        settings: AppSettings,
        microphoneStatus: PermissionStatus,
        accessibilityStatus: PermissionStatus,
        isCapturingHotkey: Bool
    ) {
        modelLabel.stringValue = PreferencesModelState.displayName(forInstalledModelID: settings.modelID)
        hotkeyLabel.stringValue = isCapturingHotkey ? "Waiting for input..." : settings.hotkey.displayName
        updatePermissionLabel(microphoneLabel, status: microphoneStatus)
        updatePermissionLabel(accessibilityLabel, status: accessibilityStatus)

        let isReady = microphoneStatus == .authorized && accessibilityStatus == .authorized
        readinessLabel.stringValue = isReady ? "Ready to transcribe" : "Permissions required"
        readinessLabel.textColor = isReady ? .systemGreen : .secondaryLabelColor

        microphoneButton.isHidden = microphoneStatus == .authorized
        accessibilityButton.isHidden = accessibilityStatus == .authorized
        offloadPopup.selectItem(at: ModelOffloadPolicy.allCases.firstIndex(of: settings.modelOffloadPolicy) ?? 0)
        clipboardHistoryCheckbox.state = settings.keepTranscriptsInClipboardHistory ? .on : .off
    }

    func selectModelOffloadPolicy(_ policy: ModelOffloadPolicy) {
        offloadPopup.selectItem(at: ModelOffloadPolicy.allCases.firstIndex(of: policy) ?? 0)
        setModelOffloadPolicy(policy)
    }

    private func updatePermissionLabel(_ label: NSTextField, status: PermissionStatus) {
        switch status {
        case .authorized:
            label.stringValue = "Authorized"
            label.textColor = .systemGreen
        case .denied:
            label.stringValue = "Denied"
            label.textColor = .systemRed
        case .notDetermined:
            label.stringValue = "Not Requested"
            label.textColor = .secondaryLabelColor
        }
    }

    var isClipboardHistoryEnabled: Bool {
        clipboardHistoryCheckbox.state == .on
    }

    @objc private func requestMicrophoneAccess(_: NSButton) {
        requestMicrophone()
    }

    @objc private func requestAccessibilityAccess(_: NSButton) {
        requestAccessibility()
    }

    @objc private func modelOffloadChanged(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0 else { return }
        setModelOffloadPolicy(ModelOffloadPolicy.allCases[sender.indexOfSelectedItem])
    }

    @objc private func clipboardHistoryChanged(_ sender: NSButton) {
        setKeepTranscriptsInClipboardHistory(sender.state == .on)
    }
}
