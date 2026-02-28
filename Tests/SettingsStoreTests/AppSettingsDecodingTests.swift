import SettingsStore
import XCTest

final class AppSettingsDecodingTests: XCTestCase {
    func testDecodesLegacyHotkeyDescription() throws {
        let json = """
        {
          "defaultModelID": "tiny.en",
          "selectedModelID": "tiny.en",
          "language": "en",
          "hotkeyDescription": "Right Option",
          "pasteOnlyModeEnabled": true
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.hotkey.keyCode, 61)
        XCTAssertTrue(decoded.hotkey.isModifierKey)
        XCTAssertEqual(decoded.hotkey.displayName, "Right Option")
    }
}
