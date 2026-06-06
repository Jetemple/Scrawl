@testable import AppUI
import SettingsStore
import TranscriptHistoryStore
import XCTest

final class TranscriptHistoryCoordinatorTests: XCTestCase {
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
