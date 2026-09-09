import DictionaryStore
import Foundation
import XCTest

final class DictionaryReplacerTests: XCTestCase {
    func testVocabularyTermsNormalizeAndDeduplicateCaseInsensitively() throws {
        let store = InMemoryDictionaryStore()

        try store.addTerm(" Anduril ")
        try store.addTerm("anduril")
        try store.addTerm("Postgres")

        XCTAssertEqual(store.terms().map(\.value), ["Anduril", "Postgres"])
    }

    func testVocabularyTermsCanBeEditedAndDeleted() throws {
        let store = InMemoryDictionaryStore(terms: [
            VocabularyTerm(value: "Anduril"),
            VocabularyTerm(value: "Postgres"),
        ])

        try store.replaceTerm(original: "Anduril", with: "Kubernetes")
        try store.deleteTerms(["Postgres"])

        XCTAssertEqual(store.terms().map(\.value), ["Kubernetes"])
    }

    func testJSONVocabularyStoreMigratesLegacyCorrectValues() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let fileURL = directory.appending(path: "dictionary.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode([
            DictionaryEntry(wrong: "andrew", correct: "Anduril"),
            DictionaryEntry(wrong: "post grass", correct: "Postgres"),
            DictionaryEntry(wrong: "duplicate", correct: "anduril"),
        ]).write(to: fileURL)

        let store = JSONDictionaryStore(fileURL: fileURL)

        XCTAssertEqual(store.terms().map(\.value), ["Anduril", "Postgres"])
    }

    func testJSONVocabularyStorePersistsPreferredTerms() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let fileURL = directory.appending(path: "dictionary.json")
        let store = JSONDictionaryStore(fileURL: fileURL)

        try store.addTerm("Anduril")
        try store.addTerm("Postgres")

        XCTAssertEqual(JSONDictionaryStore(fileURL: fileURL).terms().map(\.value), ["Anduril", "Postgres"])
    }

    func testAppliesCaseInsensitiveReplacement() {
        let entries = [DictionaryEntry(wrong: "whispr", correct: "Whisper")]
        let result = DictionaryReplacer.apply(entries: entries, to: "whispr and WHISPR and Whispr")

        XCTAssertEqual(result, "whisper and WHISPER and Whisper")
    }

    func testNoChangeWhenDictionaryIsEmpty() {
        let result = DictionaryReplacer.apply(entries: [], to: "no changes expected")
        XCTAssertEqual(result, "no changes expected")
    }

    func testReplacementContainingSearchTermDoesNotLoop() {
        let entries = [DictionaryEntry(wrong: "test", correct: "testing")]
        let result = DictionaryReplacer.apply(entries: entries, to: "this is a test")
        XCTAssertEqual(result, "this is a testing")
    }

    func testAddOrReplaceUpsertsCaseInsensitive() throws {
        let store = InMemoryDictionaryStore(entries: [
            DictionaryEntry(wrong: "wispr", correct: "Whisper"),
        ])

        try store.addOrReplace(wrong: "WISPR", correct: "Whisper.cpp")

        let entries = store.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.wrong, "WISPR")
        XCTAssertEqual(entries.first?.correct, "Whisper.cpp")
    }

    func testAddOrReplaceIgnoresBlankValues() throws {
        let store = InMemoryDictionaryStore()

        try store.addOrReplace(wrong: " \n", correct: "Whisper")
        try store.addOrReplace(wrong: "wispr", correct: "\t")

        XCTAssertTrue(store.entries().isEmpty)
    }

    func testSaveRemainsAvailable() throws {
        let store: any DictionaryStoring = InMemoryDictionaryStore()
        let entries = [
            DictionaryEntry(wrong: "wispr", correct: "Whisper"),
        ]

        try store.save(entries)

        XCTAssertEqual(store.entries(), entries)
    }

    func testDeleteRemovesMatchingWrongValuesCaseInsensitive() throws {
        let store = InMemoryDictionaryStore(entries: [
            DictionaryEntry(wrong: "wispr", correct: "Whisper"),
            DictionaryEntry(wrong: "kuber netties", correct: "Kubernetes"),
            DictionaryEntry(wrong: "pie torch", correct: "PyTorch"),
        ])

        try store.delete(wrongValues: ["WISPR", "KUBER NETTIES"])

        XCTAssertEqual(store.entries(), [
            DictionaryEntry(wrong: "pie torch", correct: "PyTorch"),
        ])
    }

    func testReplaceIgnoresBlankValues() throws {
        let original = [
            DictionaryEntry(wrong: "wispr", correct: "Whisper"),
        ]
        let store = InMemoryDictionaryStore(entries: original)

        try store.replace(originalWrong: "wispr", wrong: "  ", correct: "Whisper.cpp")
        try store.replace(originalWrong: "wispr", wrong: "whispr", correct: "\n")
        try store.replace(originalWrong: " \n", wrong: "whispr", correct: "Whisper.cpp")

        XCTAssertEqual(store.entries(), original)
    }

    func testReplaceRemovesOriginalWhenWrongValueChanges() throws {
        let store = InMemoryDictionaryStore(entries: [
            DictionaryEntry(wrong: "wispr", correct: "Whisper"),
            DictionaryEntry(wrong: "pie torch", correct: "PyTorch"),
        ])

        try store.replace(originalWrong: " wispr ", wrong: " whispr ", correct: " Whisper.cpp ")

        XCTAssertEqual(store.entries(), [
            DictionaryEntry(wrong: "whispr", correct: "Whisper.cpp"),
            DictionaryEntry(wrong: "pie torch", correct: "PyTorch"),
        ])
    }

    func testReplaceRemovesCaseInsensitiveCollisionWithNewWrongValue() throws {
        let store = InMemoryDictionaryStore(entries: [
            DictionaryEntry(wrong: "alpha", correct: "Alpha"),
            DictionaryEntry(wrong: "whispr", correct: "Old replacement"),
            DictionaryEntry(wrong: "bravo", correct: "Bravo"),
            DictionaryEntry(wrong: "wispr", correct: "Whisper"),
            DictionaryEntry(wrong: "charlie", correct: "Charlie"),
        ])

        try store.replace(originalWrong: "WISPR", wrong: " WHISPR ", correct: " Whisper.cpp ")

        XCTAssertEqual(store.entries(), [
            DictionaryEntry(wrong: "alpha", correct: "Alpha"),
            DictionaryEntry(wrong: "bravo", correct: "Bravo"),
            DictionaryEntry(wrong: "WHISPR", correct: "Whisper.cpp"),
            DictionaryEntry(wrong: "charlie", correct: "Charlie"),
        ])
    }

    func testReplacePreservesOriginalPositionAndUnrelatedOrder() throws {
        let store = InMemoryDictionaryStore(entries: [
            DictionaryEntry(wrong: "alpha", correct: "Alpha"),
            DictionaryEntry(wrong: "wispr", correct: "Whisper"),
            DictionaryEntry(wrong: "bravo", correct: "Bravo"),
        ])

        try store.replace(originalWrong: "wispr", wrong: "whispr", correct: "Whisper.cpp")

        XCTAssertEqual(store.entries(), [
            DictionaryEntry(wrong: "alpha", correct: "Alpha"),
            DictionaryEntry(wrong: "whispr", correct: "Whisper.cpp"),
            DictionaryEntry(wrong: "bravo", correct: "Bravo"),
        ])
    }

    func testConcurrentAddsDoNotLoseEntries() {
        let store = InMemoryDictionaryStore()
        let expectedWrongValues = Set((0..<200).map { "entry-\($0)" })

        DispatchQueue.concurrentPerform(iterations: expectedWrongValues.count) { index in
            try! store.addOrReplace(wrong: "entry-\(index)", correct: "Entry \(index)")
        }

        XCTAssertEqual(Set(store.entries().map(\.wrong)), expectedWrongValues)
    }

    func testFailedJSONMutationLeavesCacheUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let fileURL = directory.appending(path: "dictionary.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = JSONDictionaryStore(fileURL: fileURL)
        try store.addOrReplace(wrong: "alpha", correct: "Alpha")
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(try store.addOrReplace(wrong: "bravo", correct: "Bravo"))
        XCTAssertEqual(store.entries(), [
            DictionaryEntry(wrong: "alpha", correct: "Alpha"),
        ])
    }

    func testFailedJSONSaveLeavesCacheUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let fileURL = directory.appending(path: "dictionary.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = [
            DictionaryEntry(wrong: "alpha", correct: "Alpha"),
        ]
        let store = JSONDictionaryStore(fileURL: fileURL)
        try store.save(original)
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(try store.save([
            DictionaryEntry(wrong: "bravo", correct: "Bravo"),
        ]))
        XCTAssertEqual(store.entries(), original)
    }

    func testGoldenOutputs() {
        let entries = [
            DictionaryEntry(wrong: "a", correct: "b"),
            DictionaryEntry(wrong: "b", correct: "c"),
            DictionaryEntry(wrong: "ss", correct: "SS-out"),
            DictionaryEntry(wrong: "hello", correct: "goodbye"),
        ]
        XCTAssertEqual(DictionaryReplacer.apply(entries: entries, to: "a b"), "c c") // chaining
        XCTAssertEqual(DictionaryReplacer.apply(entries: entries, to: "SS ss"), "SS-OUT ss-out")
        XCTAssertEqual(DictionaryReplacer.apply(entries: entries, to: "STRASSE"), "STRCSS-OUTE") // chained then ss
        XCTAssertEqual(DictionaryReplacer.apply(entries: entries, to: "İ"), "İ")
        XCTAssertEqual(DictionaryReplacer.apply(entries: entries, to: "hELLO hello HELLO"), "goodbye goodbye GOODBYE")
        XCTAssertEqual(DictionaryReplacer.apply(entries: entries, to: " he"), " he")
        XCTAssertEqual(DictionaryReplacer.apply(entries: entries, to: "123"), "123")
        XCTAssertEqual(DictionaryReplacer.apply(entries: entries, to: "👋 hello"), "👋 goodbye")
    }

    func testGoldenPassthroughAndOverlap() {
        XCTAssertEqual(DictionaryReplacer.apply(entries: [], to: "hello"), "hello")
        XCTAssertEqual(DictionaryReplacer.apply(entries: [DictionaryEntry(wrong: "x", correct: "y")], to: ""), "")
        XCTAssertEqual(DictionaryReplacer.apply(entries: [DictionaryEntry(wrong: "", correct: "x")], to: "abc"), "abc")
        XCTAssertEqual(DictionaryReplacer.apply(entries: [DictionaryEntry(wrong: "x", correct: "y")], to: "hello"), "hello")
        let shortFirst = [
            DictionaryEntry(wrong: "he", correct: "HA"),
            DictionaryEntry(wrong: "hello", correct: "BYE"),
        ]
        let longFirst = [
            DictionaryEntry(wrong: "hello", correct: "BYE"),
            DictionaryEntry(wrong: "he", correct: "HA"),
        ]
        XCTAssertEqual(DictionaryReplacer.apply(entries: shortFirst, to: "well hello"), "well hallo")
        XCTAssertEqual(DictionaryReplacer.apply(entries: longFirst, to: "well hello"), "well bye")
    }
}
