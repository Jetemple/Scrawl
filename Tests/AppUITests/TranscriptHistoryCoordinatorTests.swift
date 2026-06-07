@testable import AppUI
import SettingsStore
import TranscriptHistoryStore
import XCTest

final class TranscriptHistoryCoordinatorTests: XCTestCase {
    func testAddStoresPerformanceMetrics() throws {
        let settingsStore = makeSettingsStore()
        let historyStore = InMemoryTranscriptHistoryStore()
        let coordinator = TranscriptHistoryCoordinator(settingsStore: settingsStore, historyStore: historyStore)

        try coordinator.add(text: "hello world", recordingDurationMS: 2_000, transcriptionLatencyMS: 500)

        let record = try XCTUnwrap(historyStore.records().first)
        XCTAssertEqual(record.recordingDurationMS, 2_000)
        XCTAssertEqual(record.transcriptionLatencyMS, 500)
    }

    func testAddDoesNothingWhenHistoryIsDisabled() throws {
        let settingsStore = makeSettingsStore()
        try settingsStore.save(AppSettings(isTranscriptHistoryEnabled: false))
        let historyStore = InMemoryTranscriptHistoryStore()
        let coordinator = TranscriptHistoryCoordinator(settingsStore: settingsStore, historyStore: historyStore)

        try coordinator.add(text: "private", createdAt: .now)

        XCTAssertTrue(historyStore.records().isEmpty)
    }

    func testAddStoresRecordWhenHistoryIsEnabled() throws {
        let settingsStore = makeSettingsStore()
        let historyStore = InMemoryTranscriptHistoryStore()
        let coordinator = TranscriptHistoryCoordinator(settingsStore: settingsStore, historyStore: historyStore)
        let createdAt = Date(timeIntervalSince1970: 123)

        try coordinator.add(text: "remember me", createdAt: createdAt)

        let record = try XCTUnwrap(historyStore.records().first)
        XCTAssertEqual(record.text, "remember me")
        XCTAssertEqual(record.createdAt, createdAt)
    }

    func testDisableClearsRecordsBeforeSavingDisabledSetting() throws {
        let settingsStore = makeSettingsStore()
        let historyStore = InMemoryTranscriptHistoryStore(records: [
            TranscriptRecord(id: UUID(), createdAt: .now, text: "delete me")
        ])
        let coordinator = TranscriptHistoryCoordinator(settingsStore: settingsStore, historyStore: historyStore)

        try coordinator.setEnabled(false)

        XCTAssertTrue(historyStore.records().isEmpty)
        XCTAssertFalse(settingsStore.load().isTranscriptHistoryEnabled)
    }

    func testDisableLeavesSettingEnabledWhenClearFails() throws {
        let settingsStore = makeSettingsStore()
        let coordinator = TranscriptHistoryCoordinator(
            settingsStore: settingsStore,
            historyStore: FailingClearHistoryStore()
        )

        XCTAssertThrowsError(try coordinator.setEnabled(false))
        XCTAssertTrue(settingsStore.load().isTranscriptHistoryEnabled)
    }

    func testEnablePreservesRecordsAndSavesEnabledSetting() throws {
        let settingsStore = makeSettingsStore()
        try settingsStore.save(AppSettings(isTranscriptHistoryEnabled: false))
        let record = TranscriptRecord(id: UUID(), createdAt: .now, text: "preserve me")
        let historyStore = InMemoryTranscriptHistoryStore(records: [record])
        let coordinator = TranscriptHistoryCoordinator(settingsStore: settingsStore, historyStore: historyStore)

        try coordinator.setEnabled(true)

        XCTAssertEqual(historyStore.records(), [record])
        XCTAssertTrue(settingsStore.load().isTranscriptHistoryEnabled)
    }

    func testDisableWaitsForInFlightAddThenClearsIt() throws {
        let settingsStore = makeSettingsStore()
        let historyStore = BlockingAddHistoryStore()
        let coordinator = TranscriptHistoryCoordinator(settingsStore: settingsStore, historyStore: historyStore)
        let addFinished = DispatchGroup()
        let disableFinished = DispatchGroup()
        let disableStarted = DispatchSemaphore(value: 0)
        addFinished.enter()
        disableFinished.enter()

        DispatchQueue.global().async {
            try? coordinator.add(text: "in flight")
            addFinished.leave()
        }
        XCTAssertTrue(historyStore.waitUntilAddIsBlocked())

        DispatchQueue.global().async {
            disableStarted.signal()
            try? coordinator.setEnabled(false)
            disableFinished.leave()
        }

        XCTAssertEqual(disableStarted.wait(timeout: .now() + 1), .success)
        XCTAssertFalse(historyStore.waitUntilClearStarts(timeout: 0.1))
        XCTAssertEqual(disableFinished.wait(timeout: .now() + 0.1), .timedOut)
        historyStore.releaseAdd()
        XCTAssertEqual(addFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(disableFinished.wait(timeout: .now() + 1), .success)
        XCTAssertTrue(historyStore.waitUntilClearStarts(timeout: 1))

        XCTAssertTrue(historyStore.records().isEmpty)
        XCTAssertFalse(settingsStore.load().isTranscriptHistoryEnabled)
    }

    private func makeSettingsStore() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }
}

private struct FailingClearHistoryStore: TranscriptHistoryStoring {
    enum Failure: Error {
        case clear
    }

    func records() -> [TranscriptRecord] { [] }
    func add(_ record: TranscriptRecord) throws {}
    func delete(ids: Set<UUID>) throws {}
    func clear() throws { throw Failure.clear }
}

private final class BlockingAddHistoryStore: TranscriptHistoryStoring, @unchecked Sendable {
    private let addStarted = DispatchSemaphore(value: 0)
    private let allowAdd = DispatchSemaphore(value: 0)
    private let clearStarted = DispatchGroup()
    private let lock = NSLock()
    private var storedRecords: [TranscriptRecord] = []

    init() {
        clearStarted.enter()
    }

    func records() -> [TranscriptRecord] {
        lock.withLock { storedRecords }
    }

    func add(_ record: TranscriptRecord) throws {
        addStarted.signal()
        allowAdd.wait()
        lock.withLock {
            storedRecords.append(record)
        }
    }

    func delete(ids: Set<UUID>) throws {
        lock.withLock {
            storedRecords.removeAll { ids.contains($0.id) }
        }
    }

    func clear() throws {
        clearStarted.leave()
        lock.withLock {
            storedRecords.removeAll()
        }
    }

    func waitUntilAddIsBlocked() -> Bool {
        addStarted.wait(timeout: .now() + 1) == .success
    }

    func releaseAdd() {
        allowAdd.signal()
    }

    func waitUntilClearStarts(timeout: TimeInterval) -> Bool {
        clearStarted.wait(timeout: .now() + timeout) == .success
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
