import AppKit
@testable import AppUI
import SettingsStore
import XCTest

final class SupportedHotkeyModifiersTests: XCTestCase {
    func testFnIsSupportedModifierHotkey() {
        let hotkey = SupportedHotkeyModifiers.hotkey(for: 63)

        XCTAssertEqual(
            hotkey,
            HotkeySetting(keyCode: 63, isModifierKey: true, displayName: "Fn")
        )
        XCTAssertEqual(SupportedHotkeyModifiers.modifierFlag(for: 63), .function)
    }

    func testUnsupportedModifierKeyCodeReturnsNil() {
        XCTAssertNil(SupportedHotkeyModifiers.hotkey(for: 57))
        XCTAssertNil(SupportedHotkeyModifiers.modifierFlag(for: 57))
    }
}
