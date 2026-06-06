import Foundation
import TranscriptHistoryStore
import XCTest

final class TranscriptHistoryStoreTests: XCTestCase {
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

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }
}
