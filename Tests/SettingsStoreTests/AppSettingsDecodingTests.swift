import SettingsStore
import XCTest

final class AppSettingsDecodingTests: XCTestCase {
    func testModelOffloadDefaultsToFiveMinutes() {
        XCTAssertEqual(AppSettings().modelOffloadPolicy, .fiveMinutes)
        XCTAssertEqual(AppSettings().modelOffloadPolicy.idleSeconds, 300)
    }

    func testModelOffloadPolicyRoundTrips() throws {
        let data = try JSONEncoder().encode(AppSettings(modelOffloadPolicy: .never))

        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data).modelOffloadPolicy, .never)
    }

    func testLegacySettingsDefaultModelOffloadToFiveMinutes() throws {
        let data = try XCTUnwrap("""
        {"defaultModelID":"tiny.en","selectedModelID":"tiny.en","language":"en"}
        """.data(using: .utf8))

        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data).modelOffloadPolicy, .fiveMinutes)
    }

    func testTranscriptHistoryIsEnabledByDefault() {
        XCTAssertTrue(AppSettings().isTranscriptHistoryEnabled)
    }

    func testNoStoredSettingsDefaultTranscriptHistoryEnabled() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        XCTAssertTrue(SettingsStore(defaults: defaults).load().isTranscriptHistoryEnabled)
    }

    func testLegacySettingsDecodeWithTranscriptHistoryEnabled() throws {
        let data = try XCTUnwrap("""
        {"defaultModelID":"tiny.en","selectedModelID":"tiny.en","language":"en"}
        """.data(using: .utf8))

        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: data).isTranscriptHistoryEnabled)
    }

    func testExplicitlyDisabledTranscriptHistoryRoundTrips() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SettingsStore(defaults: defaults)

        try store.save(AppSettings(isTranscriptHistoryEnabled: false))

        XCTAssertFalse(store.load().isTranscriptHistoryEnabled)
    }

    func testMalformedSettingsRetainSeparatelyPersistedDisabledTranscriptHistory() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SettingsStore(defaults: defaults)
        try store.save(AppSettings(isTranscriptHistoryEnabled: false))
        defaults.set(Data("malformed".utf8), forKey: "scrawl.settings.v1")

        XCTAssertFalse(store.load().isTranscriptHistoryEnabled)
    }

    func testMalformedSettingsWithoutSeparatePrivacyValueFailClosed() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(Data("malformed".utf8), forKey: "scrawl.settings.v1")

        XCTAssertFalse(SettingsStore(defaults: defaults).load().isTranscriptHistoryEnabled)
    }

    func testStaleLoadDoesNotOverwriteNewerDisabledPrivacyValue() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(try JSONEncoder().encode(AppSettings(isTranscriptHistoryEnabled: true)), forKey: "scrawl.settings.v1")
        defaults.set(false, forKey: "scrawl.settings.transcriptHistoryEnabled")

        _ = SettingsStore(defaults: defaults).load()

        XCTAssertFalse(defaults.bool(forKey: "scrawl.settings.transcriptHistoryEnabled"))
    }

    func testKeepTranscriptsInClipboardHistoryDefaultsToFalse() {
        XCTAssertFalse(AppSettings().keepTranscriptsInClipboardHistory)
    }

    func testKeepTranscriptsInClipboardHistoryRoundTrips() throws {
        let data = try JSONEncoder().encode(AppSettings(keepTranscriptsInClipboardHistory: true))
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: data).keepTranscriptsInClipboardHistory)
    }

    func testLegacyJSONWithoutClipboardHistoryKeyDecodesToFalse() throws {
        let data = try XCTUnwrap("""
        {"defaultModelID":"tiny.en","selectedModelID":"tiny.en","language":"en"}
        """.data(using: .utf8))
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: data).keepTranscriptsInClipboardHistory)
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
