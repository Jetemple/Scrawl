import DictionaryStore
import Foundation
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

    func testConcurrentAddsUseAtomicMutationAndDoNotLoseEitherEntry() throws {
        let store = CoordinatedDictionaryStore()
        let firstFinished = expectation(description: "first add finished")
        let secondFinished = expectation(description: "second add finished")
        let secondStarted = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            try? store.addOrReplace(wrong: "alpha", correct: "Alpha")
            firstFinished.fulfill()
        }
        XCTAssertEqual(store.firstMutationStarted.wait(timeout: .now() + 1), .success)

        DispatchQueue.global().async {
            secondStarted.signal()
            try? store.addOrReplace(wrong: "bravo", correct: "Bravo")
            secondFinished.fulfill()
        }
        XCTAssertEqual(secondStarted.wait(timeout: .now() + 1), .success)
        store.allowFirstMutation.signal()

        wait(for: [firstFinished, secondFinished], timeout: 2)
        XCTAssertEqual(Set(store.entries().map(\.wrong)), Set(["alpha", "bravo"]))
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
}

private final class CoordinatedDictionaryStore: DictionaryStoring, @unchecked Sendable {
    let firstMutationStarted = DispatchSemaphore(value: 0)
    let allowFirstMutation = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var isFirstMutation = true
    private var storedEntries: [DictionaryEntry] = []

    func entries() -> [DictionaryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storedEntries
    }

    func mutateEntries(_ mutation: (inout [DictionaryEntry]) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        if isFirstMutation {
            isFirstMutation = false
            firstMutationStarted.signal()
            allowFirstMutation.wait()
        }
        mutation(&storedEntries)
    }

    func apply(to text: String) -> String {
        DictionaryReplacer.apply(entries: entries(), to: text)
    }
}
