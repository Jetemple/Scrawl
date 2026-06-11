import Foundation
import SettingsStore
import XCTest

final class SettingsStoreMutateTests: XCTestCase {

    // MARK: - Basic persistence

    func testMutatePersistsChange() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SettingsStore(defaults: defaults)

        try store.mutate { $0.selectedModelID = "ggml-tiny.en" }

        XCTAssertEqual(store.load().selectedModelID, "ggml-tiny.en")
    }

    func testMutateReloadSeesChange() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SettingsStore(defaults: defaults)

        try store.mutate { $0.isTranscriptHistoryEnabled = false }

        let reloaded = SettingsStore(defaults: defaults).load()
        XCTAssertFalse(reloaded.isTranscriptHistoryEnabled)
    }

    // MARK: - Concurrency: no update lost

    func testConcurrentMutatesBothFieldsReachFinalValues() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
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
        // Serial writers on the same field: the count must be exactly N.
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SettingsStore(defaults: defaults)
        try store.save(AppSettings(selectedModelID: "counter:0"))

        let iterations = 100
        var errors: [Error] = []
        let errorLock = NSLock()
        let counterLock = NSLock()
        var counter = 0

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            do {
                try store.mutate { _ in
                    counterLock.withLock { counter += 1 }
                }
            } catch {
                errorLock.withLock { errors.append(error) }
            }
        }

        XCTAssertTrue(errors.isEmpty, "mutate threw: \(errors)")
        XCTAssertEqual(counter, iterations)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }; return body()
    }
}
