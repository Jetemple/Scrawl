import AppKit
import Permissions
import SettingsStore

final class PreferencesGeneralView: NSView {
    private let readinessLabel = NSTextField(labelWithString: "")
    private let hotkeyLabel = NSTextField(labelWithString: "")
    private let microphoneLabel = NSTextField(labelWithString: "")
    private let accessibilityLabel = NSTextField(labelWithString: "")
    private let microphoneButton = NSButton(title: "Request", target: nil, action: nil)
    private let accessibilityButton = NSButton(title: "Open Prompt", target: nil, action: nil)
    private let hotkeyButton = NSButton(title: "Set Hotkey…", target: nil, action: nil)
    private let offloadPopup = NSPopUpButton()
    private let clipboardHistoryCheckbox = NSButton(checkboxWithTitle: "Keep transcripts in clipboard history", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let setHotkey: () -> Void
    private let requestMicrophone: () -> Void
    private let requestAccessibility: () -> Void
    private let setModelOffloadPolicy: (ModelOffloadPolicy) -> Void
    private let setKeepTranscriptsInClipboardHistory: (Bool) -> Void
    private let setLaunchAtLogin: (Bool) -> Void

    var modelOffloadChoices: [String] {
        offloadPopup.itemTitles
    }

    var selectedModelOffloadPolicy: ModelOffloadPolicy? {
        guard offloadPopup.indexOfSelectedItem >= 0 else { return nil }
        return ModelOffloadPolicy.allCases[offloadPopup.indexOfSelectedItem]
    }

    init(
        setHotkey: @escaping () -> Void,
        requestMicrophone: @escaping () -> Void,
        requestAccessibility: @escaping () -> Void,
        setModelOffloadPolicy: @escaping (ModelOffloadPolicy) -> Void,
        setKeepTranscriptsInClipboardHistory: @escaping (Bool) -> Void = { _ in },
        setLaunchAtLogin: @escaping (Bool) -> Void = { _ in }
    ) {
        self.setHotkey = setHotkey
        self.requestMicrophone = requestMicrophone
        self.requestAccessibility = requestAccessibility
        self.setModelOffloadPolicy = setModelOffloadPolicy
        self.setKeepTranscriptsInClipboardHistory = setKeepTranscriptsInClipboardHistory
        self.setLaunchAtLogin = setLaunchAtLogin
        super.init(frame: .zero)

        PreferencesPageSupport.configureSecondaryButton(microphoneButton)
        PreferencesPageSupport.configureSecondaryButton(accessibilityButton)
        PreferencesPageSupport.configureSecondaryButton(hotkeyButton)

        microphoneButton.target = self
        microphoneButton.action = #selector(requestMicrophoneAccess(_:))
        accessibilityButton.target = self
        accessibilityButton.action = #selector(requestAccessibilityAccess(_:))
        hotkeyButton.target = self
        hotkeyButton.action = #selector(setHotkeyAction(_:))
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
        clipboardGroup.edgeInsets = NSEdgeInsets(
            top: 11,
            left: PreferencesPageSupport.rowInset,
            bottom: 11,
            right: PreferencesPageSupport.rowInset
        )
        // A vertical stack won't stretch under the group's `.width` alignment, so pin it left
        // inside a full-width horizontal row (the trailing spacer absorbs the slack), matching
        // how the key/value rows and section headers lay out.
        let clipboardRow = NSStackView(views: [clipboardGroup, NSView()])
        clipboardRow.orientation = .horizontal
        clipboardRow.alignment = .top
        clipboardRow.spacing = 0

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged(_:))
        launchAtLoginCheckbox.font = .systemFont(ofSize: 13)

        let launchAtLoginSubtitle = NSTextField(labelWithString: "Start Scrawl automatically when you sign in.")
        launchAtLoginSubtitle.font = .systemFont(ofSize: 11)
        launchAtLoginSubtitle.textColor = .secondaryLabelColor

        let launchAtLoginGroup = NSStackView(views: [launchAtLoginCheckbox, launchAtLoginSubtitle])
        launchAtLoginGroup.orientation = .vertical
        launchAtLoginGroup.alignment = .leading
        launchAtLoginGroup.spacing = 3
        launchAtLoginGroup.edgeInsets = NSEdgeInsets(
            top: 11,
            left: PreferencesPageSupport.rowInset,
            bottom: 11,
            right: PreferencesPageSupport.rowInset
        )
        let launchAtLoginRow = NSStackView(views: [launchAtLoginGroup, NSView()])
        launchAtLoginRow.orientation = .horizontal
        launchAtLoginRow.alignment = .top
        launchAtLoginRow.spacing = 0

        let hotkeyInstructions = NSTextField(wrappingLabelWithString: """
        Hold the hotkey while speaking, then release to transcribe. \
        Double-tap to keep recording hands-free, then tap again to stop.
        """)
        hotkeyInstructions.font = .systemFont(ofSize: 11)
        hotkeyInstructions.textColor = .secondaryLabelColor
        let hotkeyInstructionsRow = NSStackView(views: [hotkeyInstructions, NSView()])
        hotkeyInstructionsRow.orientation = .horizontal
        hotkeyInstructionsRow.alignment = .top
        hotkeyInstructionsRow.spacing = 0
        hotkeyInstructionsRow.edgeInsets = NSEdgeInsets(
            top: 0,
            left: PreferencesPageSupport.rowInset,
            bottom: 0,
            right: PreferencesPageSupport.rowInset
        )

        let page = PreferencesPageSupport.makePage(
            title: "General",
            description: "Readiness and defaults.",
            content: [
                PreferencesPageSupport.makeGroup(header: "Transcription", rows: [
                    PreferencesPageSupport.makeSettingRow(title: "Readiness", detail: readinessLabel),
                    PreferencesPageSupport.makeSettingRow(title: "Hotkey", detail: hotkeyLabel, action: hotkeyButton),
                    PreferencesPageSupport.makeSettingRow(
                        title: "Offload model",
                        // The popup value (Immediately / 1 minute / … / Never) already states
                        // the timing, so no static detail — a fixed "After inactivity" label
                        // contradicted the "Immediately" and "Never" choices.
                        detail: NSTextField(labelWithString: ""),
                        action: offloadPopup
                    ),
                ]),
                hotkeyInstructionsRow,
                PreferencesPageSupport.makeGroup(header: "Permissions", rows: [
                    PreferencesPageSupport.makeSettingRow(title: "Microphone", detail: microphoneLabel, action: microphoneButton),
                    PreferencesPageSupport.makeSettingRow(title: "Accessibility", detail: accessibilityLabel, action: accessibilityButton),
                ]),
                PreferencesPageSupport.makeGroup(header: "Options", rows: [
                    clipboardRow,
                    launchAtLoginRow,
                ]),
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
        isCapturingHotkey: Bool,
        launchAtLoginEnabled: Bool
    ) {
        hotkeyLabel.stringValue = isCapturingHotkey ? "Waiting for input..." : settings.hotkey.displayName
        hotkeyButton.title = isCapturingHotkey ? "Cancel Capture" : "Set Hotkey…"
        updatePermissionLabel(microphoneLabel, status: microphoneStatus)
        updatePermissionLabel(accessibilityLabel, status: accessibilityStatus)

        let isReady = microphoneStatus == .authorized && accessibilityStatus == .authorized
        readinessLabel.stringValue = isReady ? "Ready to transcribe" : "Permissions required"
        readinessLabel.textColor = isReady ? .systemGreen : .secondaryLabelColor

        microphoneButton.isHidden = microphoneStatus == .authorized
        accessibilityButton.isHidden = accessibilityStatus == .authorized
        offloadPopup.selectItem(at: ModelOffloadPolicy.allCases.firstIndex(of: settings.modelOffloadPolicy) ?? 0)
        clipboardHistoryCheckbox.state = settings.keepTranscriptsInClipboardHistory ? .on : .off
        launchAtLoginCheckbox.state = launchAtLoginEnabled ? .on : .off
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

    var isLaunchAtLoginEnabled: Bool {
        launchAtLoginCheckbox.state == .on
    }

    @objc private func setHotkeyAction(_: NSButton) {
        setHotkey()
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

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        setLaunchAtLogin(sender.state == .on)
    }
}
