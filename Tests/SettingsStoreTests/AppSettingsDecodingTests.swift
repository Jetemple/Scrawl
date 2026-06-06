import SettingsStore
import XCTest

final class AppSettingsDecodingTests: XCTestCase {
    func testTranscriptHistoryIsEnabledByDefault() {
        XCTAssertTrue(AppSettings().isTranscriptHistoryEnabled)
    }

    func testLegacySettingsDecodeWithTranscriptHistoryEnabled() throws {
        let data = try XCTUnwrap("""
        {"defaultModelID":"tiny.en","selectedModelID":"tiny.en","language":"en"}
        """.data(using: .utf8))

        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: data).isTranscriptHistoryEnabled)
    }

    func testDecodesLegacyHotkeyDescription() throws {
        let json = """
        {
          "defaultModelID": "tiny.en",
          "selectedModelID": "tiny.en",
          "language": "en",
          "hotkeyDescription": "Right Option"
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.hotkey.keyCode, 61)
        XCTAssertTrue(decoded.hotkey.isModifierKey)
        XCTAssertEqual(decoded.hotkey.displayName, "Right Option")
    }
}
