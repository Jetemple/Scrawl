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
    private let microphoneAction: ClosureAction
    private let accessibilityAction: ClosureAction

    init(requestMicrophone: @escaping () -> Void, requestAccessibility: @escaping () -> Void) {
        microphoneAction = ClosureAction(requestMicrophone)
        accessibilityAction = ClosureAction(requestAccessibility)
        super.init(frame: .zero)

        PreferencesPageSupport.configureSecondaryButton(microphoneButton)
        PreferencesPageSupport.configureSecondaryButton(accessibilityButton)

        microphoneButton.target = microphoneAction
        microphoneButton.action = #selector(ClosureAction.perform(_:))
        accessibilityButton.target = accessibilityAction
        accessibilityButton.action = #selector(ClosureAction.perform(_:))

        let page = PreferencesPageSupport.makePage(
            title: "General",
            description: "Scrawl readiness and current transcription setup.",
            content: [
                PreferencesPageSupport.makeGroup(rows: [
                    PreferencesPageSupport.makeSettingRow(title: "Readiness", detail: readinessLabel),
                    PreferencesPageSupport.makeSettingRow(title: "Model", detail: modelLabel),
                    PreferencesPageSupport.makeSettingRow(title: "Hotkey", detail: hotkeyLabel)
                ]),
                PreferencesPageSupport.makeGroup(rows: [
                    PreferencesPageSupport.makeSettingRow(title: "Microphone", detail: microphoneLabel, action: microphoneButton),
                    PreferencesPageSupport.makeSettingRow(title: "Accessibility", detail: accessibilityLabel, action: accessibilityButton)
                ])
            ]
        )
        PreferencesPageSupport.fill(self, with: page)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
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
}
