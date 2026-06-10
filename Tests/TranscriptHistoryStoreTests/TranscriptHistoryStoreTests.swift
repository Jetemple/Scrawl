import Foundation
import TranscriptHistoryStore
import XCTest

final class TranscriptHistoryStoreTests: XCTestCase {
    func testJSONStorePersistsPerformanceMetricsAndDecodesLegacyRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let fileURL = directory.appending(path: "history.json")
        let store = JSONTranscriptHistoryStore(fileURL: fileURL)
        let measured = TranscriptRecord(
            id: UUID(),
            createdAt: .now,
            text: "measured",
            recordingDurationMS: 12_000,
            transcriptionLatencyMS: 1_400
        )

        try store.add(measured)
        XCTAssertEqual(JSONTranscriptHistoryStore(fileURL: fileURL).records(), [measured])

        let legacy = """
        [{"id":"00000000-0000-0000-0000-000000000001","createdAt":0,"text":"legacy"}]
        """.data(using: .utf8)!
        try legacy.write(to: fileURL)
        let decodedLegacy = try XCTUnwrap(JSONTranscriptHistoryStore(fileURL: fileURL).records().first)
        XCTAssertNil(decodedLegacy.recordingDurationMS)
        XCTAssertNil(decodedLegacy.transcriptionLatencyMS)
    }

    func testAddStoresNewestFirstAndCapsAtLimit() throws {
        let store = InMemoryTranscriptHistoryStore(limit: 3)

        for index in 0..<4 {
            try store.add(TranscriptRecord(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                text: "\(index)"
            ))
        }

        XCTAssertEqual(store.records().map(\.text), ["3", "2", "1"])
    }

    func testDeleteAndClearRemoveRecords() throws {
        let first = TranscriptRecord(id: UUID(), createdAt: .distantPast, text: "first")
        let second = TranscriptRecord(id: UUID(), createdAt: .distantFuture, text: "second")
        let store = InMemoryTranscriptHistoryStore(records: [first, second])

        try store.delete(ids: [first.id])
        XCTAssertEqual(store.records(), [second])

        try store.clear()
        XCTAssertTrue(store.records().isEmpty)
    }

    func testJSONStorePersistsRecordsAcrossInstances() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "history.json")
        let record = TranscriptRecord(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 123),
            text: "hello"
        )

        try JSONTranscriptHistoryStore(fileURL: fileURL).add(record)

        XCTAssertEqual(JSONTranscriptHistoryStore(fileURL: fileURL).records(), [record])
    }

    func testInMemoryStoreHasNoLoadError() {
        XCTAssertNil(InMemoryTranscriptHistoryStore().loadErrorDescription)
    }

    func testJSONStoreExposesInvalidFileLoadErrorUntilClearRecovers() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "history.json")
        try Data("not json".utf8).write(to: fileURL)
        let store = JSONTranscriptHistoryStore(fileURL: fileURL)

        XCTAssertNotNil(store.loadErrorDescription)

        try store.clear()

        XCTAssertNil(store.loadErrorDescription)
    }

    func testJSONDeleteAndClearPersistAcrossInstances() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "history.json")
        let first = TranscriptRecord(id: UUID(), createdAt: .distantPast, text: "first")
        let second = TranscriptRecord(id: UUID(), createdAt: .distantFuture, text: "second")
        let store = JSONTranscriptHistoryStore(fileURL: fileURL)
        try store.add(first)
        try store.add(second)

        try store.delete(ids: [first.id])
        XCTAssertEqual(JSONTranscriptHistoryStore(fileURL: fileURL).records(), [second])

        try store.clear()
        XCTAssertTrue(JSONTranscriptHistoryStore(fileURL: fileURL).records().isEmpty)
    }

    func testJSONAddAndDeleteRejectInvalidExistingFileWithoutChangingIt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "history.json")
        let invalidData = Data("not json".utf8)
        try invalidData.write(to: fileURL)
        let store = JSONTranscriptHistoryStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.add(record(text: "new")))
        XCTAssertEqual(try Data(contentsOf: fileURL), invalidData)

        XCTAssertThrowsError(try store.delete(ids: [UUID()]))
        XCTAssertEqual(try Data(contentsOf: fileURL), invalidData)
    }

    func testJSONClearRecoversFromInvalidExistingFileAndAllowsFutureAdd() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "history.json")
        try Data("not json".utf8).write(to: fileURL)
        let store = JSONTranscriptHistoryStore(fileURL: fileURL)

        try store.clear()
        let addedRecord = record(text: "after recovery")
        try store.add(addedRecord)

        XCTAssertEqual(store.records(), [addedRecord])
        XCTAssertEqual(JSONTranscriptHistoryStore(fileURL: fileURL).records(), [addedRecord])
    }

    func testFailedJSONWriteLeavesCacheUnchanged() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "history.json")
        let store = JSONTranscriptHistoryStore(fileURL: fileURL)
        let existingRecord = record(text: "existing")
        try store.add(existingRecord)

        try FileManager.default.removeItem(at: directory)
        try Data("blocks directory creation".utf8).write(to: directory)

        XCTAssertThrowsError(try store.add(record(text: "should fail")))
        XCTAssertEqual(store.records(), [existingRecord])
    }

    private func record(text: String) -> TranscriptRecord {
        TranscriptRecord(id: UUID(), createdAt: Date(), text: text)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }
}
