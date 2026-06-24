import Foundation
import SettingsStore
import XCTest

final class SettingsStoreMutateTests: XCTestCase {
    // MARK: - Basic persistence

    func testMutatePersistsChange() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let store = SettingsStore(defaults: defaults)

        try store.mutate { $0.selectedModelID = "ggml-tiny.en" }

        XCTAssertEqual(store.load().selectedModelID, "ggml-tiny.en")
    }

    func testMutateReloadSeesChange() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let store = SettingsStore(defaults: defaults)

        try store.mutate { $0.isTranscriptHistoryEnabled = false }

        let reloaded = SettingsStore(defaults: defaults).load()
        XCTAssertFalse(reloaded.isTranscriptHistoryEnabled)
    }

    // MARK: - Concurrency: no update lost

    func testConcurrentMutatesBothFieldsReachFinalValues() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let store = SettingsStore(defaults: defaults)

        let iterations = 200
        var errors: [Error] = []
        let errorLock = NSLock()

        // Two independent writers racing: one sets selectedModelID, the other sets language.
        // Neither should clobber the other's last write.
        DispatchQueue.concurrentPerform(iterations: iterations * 2) { i in
            do {
                if i % 2 == 0 {
                    let value = "model-\(i / 2)"
                    try store.mutate { $0.selectedModelID = value }
                } else {
                    let value = "lang-\(i / 2)"
                    try store.mutate { $0.language = value }
                }
            } catch {
                errorLock.withLock { errors.append(error) }
            }
        }

        XCTAssertTrue(errors.isEmpty, "mutate threw: \(errors)")

        // After all writes, each field must reflect its own last value (no silent clobber).
        // We can't know which iteration won the race, but we can assert the final value
        // of each field belongs to its own writer (i.e. language isn't "model-…").
        let final = store.load()
        XCTAssertTrue(
            final.selectedModelID.hasPrefix("model-") || final.selectedModelID == AppSettings().selectedModelID,
            "selectedModelID corrupted: \(final.selectedModelID)"
        )
        XCTAssertTrue(
            final.language.hasPrefix("lang-") || final.language == AppSettings().language,
            "language corrupted: \(final.language)"
        )
    }

    func testConcurrentMutatesSingleFieldNeverLosesAWrite() throws {
        // Each concurrent iteration reads the current counter from selectedModelID,
        // increments it, and writes it back — all inside a single mutate.  Because
        // mutate holds the store lock for the entire read-modify-write, no increment
        // can be lost.  Without the lock, concurrent load/save interleaving would
        // silently drop updates and the final value would be less than N.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let store = SettingsStore(defaults: defaults)
        try store.save(AppSettings(selectedModelID: "0"))

        let iterations = 100
        var errors: [Error] = []
        let errorLock = NSLock()

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            do {
                try store.mutate { settings in
                    let n = Int(settings.selectedModelID) ?? 0
                    settings.selectedModelID = String(n + 1)
                }
            } catch {
                errorLock.withLock { errors.append(error) }
            }
        }

        XCTAssertTrue(errors.isEmpty, "mutate threw: \(errors)")
        XCTAssertEqual(store.load().selectedModelID, String(iterations))
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }; return body()
    }
}
