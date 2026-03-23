import AppKit
import SettingsStore

struct HotkeyModifierDefinition: Equatable {
    let keyCode: UInt16
    let displayName: String
    let flag: NSEvent.ModifierFlags

    var hotkey: HotkeySetting {
        HotkeySetting(
            keyCode: keyCode,
            isModifierKey: true,
            displayName: displayName
        )
    }
}

enum SupportedHotkeyModifiers {
    private static let definitionsByKeyCode: [UInt16: HotkeyModifierDefinition] = [
        54: HotkeyModifierDefinition(keyCode: 54, displayName: "Right \u{2318} Command", flag: .command),
        55: HotkeyModifierDefinition(keyCode: 55, displayName: "Left \u{2318} Command", flag: .command),
        56: HotkeyModifierDefinition(keyCode: 56, displayName: "Left \u{21E7} Shift", flag: .shift),
        58: HotkeyModifierDefinition(keyCode: 58, displayName: "Left \u{2325} Option", flag: .option),
        59: HotkeyModifierDefinition(keyCode: 59, displayName: "Left \u{2303} Control", flag: .control),
        60: HotkeyModifierDefinition(keyCode: 60, displayName: "Right \u{21E7} Shift", flag: .shift),
        61: HotkeyModifierDefinition(keyCode: 61, displayName: "Right \u{2325} Option", flag: .option),
        62: HotkeyModifierDefinition(keyCode: 62, displayName: "Right \u{2303} Control", flag: .control),
        63: HotkeyModifierDefinition(keyCode: 63, displayName: "Fn", flag: .function)
    ]

    static func hotkey(for keyCode: UInt16) -> HotkeySetting? {
        definitionsByKeyCode[keyCode]?.hotkey
    }

    static func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        definitionsByKeyCode[keyCode]?.flag
    }
}
