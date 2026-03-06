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
}
