import AppKit
import Permissions
import SettingsStore

final class PreferencesGeneralView: NSView {
    private static let hotkeyHelpLines = [
        "Press and hold: Record until release.",
        "Double-tap: Record until you tap again.",
    ]

    private let hotkeyLabel = NSTextField(labelWithString: "")
    private let microphoneLabel = NSTextField(labelWithString: "")
    private let accessibilityLabel = NSTextField(labelWithString: "")
    private let microphoneButton = NSButton(title: "Grant Access…", target: nil, action: nil)
    private let accessibilityButton = NSButton(title: "Grant Access…", target: nil, action: nil)
    private let hotkeyButton = NSButton(title: "Set Hotkey…", target: nil, action: nil)
    private let offloadPopup = NSPopUpButton()
    private let maxRecordingPopup = NSPopUpButton()
    private let clipboardHistoryCheckbox = NSButton(checkboxWithTitle: "Keep transcripts in clipboard history", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let setHotkey: () -> Void
    private let requestMicrophone: () -> Void
    private let requestAccessibility: () -> Void
    private let setModelOffloadPolicy: (ModelOffloadPolicy) -> Void
    private let setMaxRecordingDuration: (MaxRecordingDuration) -> Void
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
        setMaxRecordingDuration: @escaping (MaxRecordingDuration) -> Void = { _ in },
        setKeepTranscriptsInClipboardHistory: @escaping (Bool) -> Void = { _ in },
        setLaunchAtLogin: @escaping (Bool) -> Void = { _ in }
    ) {
        self.setHotkey = setHotkey
        self.requestMicrophone = requestMicrophone
        self.requestAccessibility = requestAccessibility
        self.setModelOffloadPolicy = setModelOffloadPolicy
        self.setMaxRecordingDuration = setMaxRecordingDuration
        self.setKeepTranscriptsInClipboardHistory = setKeepTranscriptsInClipboardHistory
        self.setLaunchAtLogin = setLaunchAtLogin
        super.init(frame: .zero)

        PreferencesPageSupport.configureSecondaryButton(microphoneButton)
        PreferencesPageSupport.configureSecondaryButton(accessibilityButton)
        PreferencesPageSupport.configureSecondaryButton(hotkeyButton)

        microphoneButton.target = self
        microphoneButton.action = #selector(requestMicrophoneAccess(_:))
        // The two grant buttons share a title, so tests address them by identifier.
        microphoneButton.identifier = NSUserInterfaceItemIdentifier("grant-microphone-access")
        accessibilityButton.target = self
        accessibilityButton.action = #selector(requestAccessibilityAccess(_:))
        accessibilityButton.identifier = NSUserInterfaceItemIdentifier("grant-accessibility-access")
        hotkeyButton.target = self
        hotkeyButton.action = #selector(setHotkeyAction(_:))
        let hotkeyUsageHint = "Hold to dictate. Double-tap to lock recording."
        hotkeyButton.toolTip = hotkeyUsageHint
        hotkeyLabel.toolTip = hotkeyUsageHint
        offloadPopup.addItems(withTitles: ModelOffloadPolicy.allCases.map(\.displayName))
        offloadPopup.controlSize = .small
        offloadPopup.target = self
        offloadPopup.action = #selector(modelOffloadChanged(_:))
        offloadPopup.toolTip = "Frees memory by unloading the idle model after this long. The next dictation loads it again."

        maxRecordingPopup.addItems(withTitles: MaxRecordingDuration.allCases.map(\.displayName))
        maxRecordingPopup.controlSize = .small
        maxRecordingPopup.target = self
        maxRecordingPopup.action = #selector(maxRecordingChanged(_:))
        maxRecordingPopup.toolTip = "Recordings stop automatically after this long, so a missed release can't record forever."

        // Each popup sizes to its own widest menu item ("10 minutes" vs "15 minutes"),
        // which leaves the stacked pair at visibly different widths; pin both to the wider.
        let popupWidth = ceil(max(offloadPopup.intrinsicContentSize.width, maxRecordingPopup.intrinsicContentSize.width))
        for popup in [offloadPopup, maxRecordingPopup] {
            popup.translatesAutoresizingMaskIntoConstraints = false
            popup.widthAnchor.constraint(equalToConstant: popupWidth).isActive = true
        }

        clipboardHistoryCheckbox.target = self
        clipboardHistoryCheckbox.action = #selector(clipboardHistoryChanged(_:))
        clipboardHistoryCheckbox.font = .systemFont(ofSize: 13)
        clipboardHistoryCheckbox.toolTip = "Allows clipboard managers to save your dictations."
        let clipboardRow = Self.makeCompactCheckboxRow(clipboardHistoryCheckbox)

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged(_:))
        launchAtLoginCheckbox.font = .systemFont(ofSize: 13)
        launchAtLoginCheckbox.toolTip = "Start Scrawl automatically when you sign in."
        let launchAtLoginRow = Self.makeCompactCheckboxRow(launchAtLoginCheckbox)

        let page = PreferencesPageSupport.makePage(
            content: [
                PreferencesPageSupport.makeGroup(header: "Transcription", rows: [
                    PreferencesPageSupport.makeSettingRow(
                        title: "Hotkey",
                        detail: hotkeyLabel,
                        action: hotkeyButton,
                        helpLines: Self.hotkeyHelpLines
                    ),
                    PreferencesPageSupport.makeSettingControlRow(title: "Max recording length", control: maxRecordingPopup),
                    PreferencesPageSupport.makeSettingControlRow(title: "Offload model after", control: offloadPopup),
                ]),
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
        hotkeyLabel.stringValue = isCapturingHotkey ? "Waiting for input…" : settings.hotkey.displayName
        hotkeyButton.title = isCapturingHotkey ? "Cancel Capture" : "Set Hotkey…"
        updatePermissionLabel(microphoneLabel, status: microphoneStatus)
        updatePermissionLabel(accessibilityLabel, status: accessibilityStatus)

        microphoneButton.isHidden = microphoneStatus == .authorized
        accessibilityButton.isHidden = accessibilityStatus == .authorized
        offloadPopup.selectItem(at: ModelOffloadPolicy.allCases.firstIndex(of: settings.modelOffloadPolicy) ?? 0)
        maxRecordingPopup.selectItem(at: MaxRecordingDuration.allCases.firstIndex(of: settings.maxRecordingDuration) ?? 0)
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
            label.textColor = Self.authorizedStatusColor
        case .denied:
            label.stringValue = "Denied"
            label.textColor = PreferencesPageSupport.accentColor
        case .notDetermined:
            label.stringValue = "Not Requested"
            label.textColor = .secondaryLabelColor
        }
    }

    private static var authorizedStatusColor: NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(srgbRed: 0.42, green: 0.78, blue: 0.48, alpha: 1)
            }
            return NSColor(srgbRed: 0.14, green: 0.48, blue: 0.24, alpha: 1)
        }
    }

    private static func makeCompactCheckboxRow(_ checkbox: NSButton) -> NSView {
        checkbox.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [checkbox, NSView()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        row.edgeInsets = NSEdgeInsets(
            top: 8,
            left: PreferencesPageSupport.rowInset,
            bottom: 8,
            right: PreferencesPageSupport.rowInset
        )
        return row
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

    @objc private func maxRecordingChanged(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0 else { return }
        setMaxRecordingDuration(MaxRecordingDuration.allCases[sender.indexOfSelectedItem])
    }

    @objc private func clipboardHistoryChanged(_ sender: NSButton) {
        setKeepTranscriptsInClipboardHistory(sender.state == .on)
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        setLaunchAtLogin(sender.state == .on)
    }
}
