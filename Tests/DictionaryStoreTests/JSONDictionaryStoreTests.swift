import DictionaryStore
import Foundation
import XCTest

final class JSONDictionaryStoreTests: XCTestCase {
    // MARK: - Corrupt file: mutations refused, file preserved

    func testCorruptFileExposesLoadErrorDescription() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "dictionary.json")
        try Data("not json{{{".utf8).write(to: fileURL)

        let store = JSONDictionaryStore(fileURL: fileURL)

        XCTAssertNotNil(store.loadErrorDescription)
    }

    func testCorruptFileAddTermRefusesAndPreservesFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "dictionary.json")
        let garbageData = Data("not json{{{".utf8)
        try garbageData.write(to: fileURL)

        let store = JSONDictionaryStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.addTerm("Kubernetes"))
        XCTAssertEqual(try Data(contentsOf: fileURL), garbageData)
    }

    func testCorruptFileAddOrReplaceRefusesAndPreservesFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "dictionary.json")
        let garbageData = Data("not json{{{".utf8)
        try garbageData.write(to: fileURL)

        let store = JSONDictionaryStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.addOrReplace(wrong: "wispr", correct: "Whisper"))
        XCTAssertEqual(try Data(contentsOf: fileURL), garbageData)
    }

    func testCorruptFileDeleteTermsRefusesAndPreservesFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "dictionary.json")
        let garbageData = Data("not json{{{".utf8)
        try garbageData.write(to: fileURL)

        let store = JSONDictionaryStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.deleteTerms(["anything"]))
        XCTAssertEqual(try Data(contentsOf: fileURL), garbageData)
    }

    func testCorruptFileSaveRefusesAndPreservesFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "dictionary.json")
        let garbageData = Data("not json{{{".utf8)
        try garbageData.write(to: fileURL)

        let store = JSONDictionaryStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.save([DictionaryEntry(wrong: "wispr", correct: "Whisper")]))
        XCTAssertEqual(try Data(contentsOf: fileURL), garbageData)
    }

    // MARK: - Clear: backs up corrupt file, recovers, allows future mutations

    func testClearOnCorruptFileCopiesBackupBeforeOverwriting() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "dictionary.json")
        let garbageData = Data("not json{{{".utf8)
        try garbageData.write(to: fileURL)

        let store = JSONDictionaryStore(fileURL: fileURL)
        try store.clear()

        let bakURL = directory.appending(path: "dictionary.json.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakURL.path), "backup file must exist")
        XCTAssertEqual(try Data(contentsOf: bakURL), garbageData, "backup must contain original corrupt data")
    }

    func testClearOnCorruptFileRecoversSoFutureMutationsSucceed() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "dictionary.json")
        try Data("not json{{{".utf8).write(to: fileURL)

        let store = JSONDictionaryStore(fileURL: fileURL)
        try store.clear()

        XCTAssertNil(store.loadErrorDescription)
        try store.addTerm("Kubernetes")
        XCTAssertEqual(store.terms().map(\.value), ["Kubernetes"])
        XCTAssertEqual(JSONDictionaryStore(fileURL: fileURL).terms().map(\.value), ["Kubernetes"])
    }

    func testClearOnCleanFileDoesNotCreateBackup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "dictionary.json")
        let store = JSONDictionaryStore(fileURL: fileURL)
        try store.addTerm("Anduril")

        try store.clear()

        let bakURL = directory.appending(path: "dictionary.json.bak")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bakURL.path), "no backup for clean file")
        XCTAssertTrue(store.terms().isEmpty)
    }

    // MARK: - In-memory store has no load error

    func testInMemoryStoreHasNoLoadError() {
        XCTAssertNil(InMemoryDictionaryStore().loadErrorDescription)
    }

    // MARK: - Normal round-trip still works after adding clear()

    func testClearPersistsEmptyStoreAcrossInstances() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "dictionary.json")
        let store = JSONDictionaryStore(fileURL: fileURL)
        try store.addTerm("Anduril")
        try store.addTerm("Postgres")

        try store.clear()

        XCTAssertTrue(store.terms().isEmpty)
        XCTAssertTrue(JSONDictionaryStore(fileURL: fileURL).terms().isEmpty)
    }

    // MARK: - Helpers

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }
}
