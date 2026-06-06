import DictionaryStore
import XCTest

final class DictionaryReplacerTests: XCTestCase {
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
            DictionaryEntry(wrong: "wispr", correct: "Whisper")
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
            DictionaryEntry(wrong: "pie torch", correct: "PyTorch"),
            DictionaryEntry(wrong: "whispr", correct: "Whisper.cpp"),
        ])
    }

    func testReplaceRemovesCaseInsensitiveCollisionWithNewWrongValue() throws {
        let store = InMemoryDictionaryStore(entries: [
            DictionaryEntry(wrong: "wispr", correct: "Whisper"),
            DictionaryEntry(wrong: "whispr", correct: "Old replacement"),
            DictionaryEntry(wrong: "pie torch", correct: "PyTorch"),
        ])

        try store.replace(originalWrong: "WISPR", wrong: " WHISPR ", correct: " Whisper.cpp ")

        XCTAssertEqual(store.entries(), [
            DictionaryEntry(wrong: "pie torch", correct: "PyTorch"),
            DictionaryEntry(wrong: "WHISPR", correct: "Whisper.cpp"),
        ])
    }
}
