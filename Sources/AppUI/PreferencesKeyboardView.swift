import AppKit
import SettingsStore

final class PreferencesKeyboardView: NSView {
    private let hotkeyLabel = NSTextField(labelWithString: "")
    private let captureButton = NSButton(title: "Set Hotkey…", target: nil, action: nil)
    private let setHotkey: () -> Void

    init(setHotkey: @escaping () -> Void) {
        self.setHotkey = setHotkey
        super.init(frame: .zero)

        PreferencesPageSupport.configureSecondaryButton(captureButton)
        captureButton.target = self
        captureButton.action = #selector(setHotkeyAction(_:))

        let instructions = NSTextField(wrappingLabelWithString: """
        Hold the hotkey while speaking, then release to transcribe.
        Double-tap to keep recording hands-free.
        Tap again to stop and transcribe.
        """)
        instructions.textColor = .secondaryLabelColor
        instructions.font = .systemFont(ofSize: 12)

        let page = PreferencesPageSupport.makePage(
            title: "Input",
            description: "Hotkey and recording behavior.",
            content: [
                PreferencesPageSupport.makeGroup(rows: [
                    PreferencesPageSupport.makeSettingRow(title: "Current Hotkey", detail: hotkeyLabel, action: captureButton),
                ]),
                instructions,
            ]
        )
        PreferencesPageSupport.fill(self, with: page)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(hotkey: HotkeySetting, isCapturing: Bool) {
        hotkeyLabel.stringValue = isCapturing ? "Waiting for input..." : hotkey.displayName
        captureButton.title = isCapturing ? "Cancel Capture" : "Set Hotkey…"
    }

    @objc private func setHotkeyAction(_: NSButton) {
        setHotkey()
    }
}
