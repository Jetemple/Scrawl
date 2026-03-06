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
    func apply(to text: String) -> String
}

public extension DictionaryStoring {
    func addOrReplace(wrong: String, correct: String) throws {
        let trimmedWrong = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCorrect = correct.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWrong.isEmpty, !trimmedCorrect.isEmpty else {
            return
        }

        var current = entries()
        if let index = current.firstIndex(where: { $0.wrong.caseInsensitiveCompare(trimmedWrong) == .orderedSame }) {
            current[index] = DictionaryEntry(wrong: trimmedWrong, correct: trimmedCorrect)
        } else {
            current.append(DictionaryEntry(wrong: trimmedWrong, correct: trimmedCorrect))
        }
        try save(current)
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

    public func apply(to text: String) -> String {
        let entries = entries()
        return DictionaryReplacer.apply(entries: entries, to: text)
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

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
        cachedEntries = entries
    }

    public func apply(to text: String) -> String {
        let entries = entries()
        return DictionaryReplacer.apply(entries: entries, to: text)
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
