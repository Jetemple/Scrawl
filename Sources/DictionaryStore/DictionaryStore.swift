import Foundation

public struct DictionaryEntry: Codable, Equatable, Sendable {
    public var wrong: String
    public var correct: String

    public init(wrong: String, correct: String) {
        self.wrong = wrong
        self.correct = correct
    }
}

public protocol DictionaryStoring: Sendable {
    func entries() -> [DictionaryEntry]
    func save(_ entries: [DictionaryEntry]) throws
    func addOrReplace(wrong: String, correct: String) throws
    func delete(wrongValues: Set<String>) throws
    func replace(originalWrong: String, wrong: String, correct: String) throws
    func apply(to text: String) -> String
}

private enum DictionaryEntriesMutation {
    static func addingOrReplacing(
        entries: [DictionaryEntry],
        wrong: String,
        correct: String
    ) -> [DictionaryEntry]? {
        let trimmedWrong = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCorrect = correct.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWrong.isEmpty, !trimmedCorrect.isEmpty else {
            return nil
        }

        var updated = entries
        if let index = updated.firstIndex(where: { $0.wrong.caseInsensitiveCompare(trimmedWrong) == .orderedSame }) {
            updated[index] = DictionaryEntry(wrong: trimmedWrong, correct: trimmedCorrect)
        } else {
            updated.append(DictionaryEntry(wrong: trimmedWrong, correct: trimmedCorrect))
        }
        return updated
    }

    static func deleting(entries: [DictionaryEntry], wrongValues: Set<String>) -> [DictionaryEntry] {
        entries.filter { entry in
            !wrongValues.contains { wrongValue in
                entry.wrong.caseInsensitiveCompare(wrongValue) == .orderedSame
            }
        }
    }

    static func replacing(
        entries: [DictionaryEntry],
        originalWrong: String,
        wrong: String,
        correct: String
    ) -> [DictionaryEntry]? {
        let trimmedOriginalWrong = originalWrong.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWrong = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCorrect = correct.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginalWrong.isEmpty, !trimmedWrong.isEmpty, !trimmedCorrect.isEmpty else {
            return nil
        }

        let originalIndex = entries.firstIndex {
            $0.wrong.caseInsensitiveCompare(trimmedOriginalWrong) == .orderedSame
        }
        let collisionIndex = entries.firstIndex {
            $0.wrong.caseInsensitiveCompare(trimmedWrong) == .orderedSame
        }
        let preferredIndex = originalIndex ?? collisionIndex ?? entries.endIndex
        let insertionIndex = entries[..<preferredIndex].count { entry in
            entry.wrong.caseInsensitiveCompare(trimmedOriginalWrong) != .orderedSame
                && entry.wrong.caseInsensitiveCompare(trimmedWrong) != .orderedSame
        }

        var updated = entries.filter { entry in
            entry.wrong.caseInsensitiveCompare(trimmedOriginalWrong) != .orderedSame
                && entry.wrong.caseInsensitiveCompare(trimmedWrong) != .orderedSame
        }
        updated.insert(DictionaryEntry(wrong: trimmedWrong, correct: trimmedCorrect), at: insertionIndex)
        return updated
    }
}

public final class InMemoryDictionaryStore: DictionaryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEntries: [DictionaryEntry]

    public init(entries: [DictionaryEntry] = []) {
        self.storedEntries = entries
    }

    public func entries() -> [DictionaryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storedEntries
    }

    public func save(_ entries: [DictionaryEntry]) throws {
        lock.lock()
        defer { lock.unlock() }
        storedEntries = entries
    }

    public func addOrReplace(wrong: String, correct: String) throws {
        mutateEntries {
            DictionaryEntriesMutation.addingOrReplacing(entries: $0, wrong: wrong, correct: correct)
        }
    }

    public func delete(wrongValues: Set<String>) throws {
        mutateEntries {
            DictionaryEntriesMutation.deleting(entries: $0, wrongValues: wrongValues)
        }
    }

    public func replace(originalWrong: String, wrong: String, correct: String) throws {
        mutateEntries {
            DictionaryEntriesMutation.replacing(
                entries: $0,
                originalWrong: originalWrong,
                wrong: wrong,
                correct: correct
            )
        }
    }

    public func apply(to text: String) -> String {
        let entries = entries()
        return DictionaryReplacer.apply(entries: entries, to: text)
    }

    private func mutateEntries(_ mutation: ([DictionaryEntry]) -> [DictionaryEntry]?) {
        lock.lock()
        defer { lock.unlock() }
        if let updatedEntries = mutation(storedEntries) {
            storedEntries = updatedEntries
        }
    }
}

public final class JSONDictionaryStore: DictionaryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private var cachedEntries: [DictionaryEntry]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.cachedEntries = []

        if let loaded = try? Self.loadFromDisk(fileURL: fileURL) {
            self.cachedEntries = loaded
        }
    }

    public func entries() -> [DictionaryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return cachedEntries
    }

    public func save(_ entries: [DictionaryEntry]) throws {
        lock.lock()
        defer { lock.unlock() }
        try persist(entries)
        cachedEntries = entries
    }

    public func addOrReplace(wrong: String, correct: String) throws {
        try mutateEntries {
            DictionaryEntriesMutation.addingOrReplacing(entries: $0, wrong: wrong, correct: correct)
        }
    }

    public func delete(wrongValues: Set<String>) throws {
        try mutateEntries {
            DictionaryEntriesMutation.deleting(entries: $0, wrongValues: wrongValues)
        }
    }

    public func replace(originalWrong: String, wrong: String, correct: String) throws {
        try mutateEntries {
            DictionaryEntriesMutation.replacing(
                entries: $0,
                originalWrong: originalWrong,
                wrong: wrong,
                correct: correct
            )
        }
    }

    public func apply(to text: String) -> String {
        let entries = entries()
        return DictionaryReplacer.apply(entries: entries, to: text)
    }

    private func mutateEntries(_ mutation: ([DictionaryEntry]) -> [DictionaryEntry]?) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let updatedEntries = mutation(cachedEntries) else {
            return
        }
        try persist(updatedEntries)
        cachedEntries = updatedEntries
    }

    private func persist(_ entries: [DictionaryEntry]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func loadFromDisk(fileURL: URL) throws -> [DictionaryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([DictionaryEntry].self, from: data)
    }
}

public enum DictionaryReplacer {
    public static func apply(entries: [DictionaryEntry], to text: String) -> String {
        var output = text
        for entry in entries where !entry.wrong.isEmpty {
            output = replacingCaseInsensitive(entry.wrong, with: entry.correct, in: output)
        }
        return output
    }

    private static func replacingCaseInsensitive(_ source: String, with replacement: String, in text: String) -> String {
        var working = text
        var searchStart = working.startIndex
        while searchStart < working.endIndex,
              let range = working.range(of: source, options: [.caseInsensitive], range: searchStart..<working.endIndex) {
            let original = String(working[range])
            let replacementWithCase = applyCaseStyle(from: original, to: replacement)
            working.replaceSubrange(range, with: replacementWithCase)
            searchStart = working.index(range.lowerBound, offsetBy: replacementWithCase.count, limitedBy: working.endIndex) ?? working.endIndex
        }
        return working
    }

    private static func applyCaseStyle(from original: String, to replacement: String) -> String {
        if original == original.uppercased() {
            return replacement.uppercased()
        }
        if original == original.lowercased() {
            return replacement.lowercased()
        }
        if original.prefix(1) == original.prefix(1).uppercased(),
           original.dropFirst() == original.dropFirst().lowercased() {
            return replacement.prefix(1).uppercased() + replacement.dropFirst().lowercased()
        }
        return replacement
    }
}
