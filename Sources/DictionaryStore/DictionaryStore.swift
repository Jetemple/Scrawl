import Foundation

public struct DictionaryEntry: Codable, Equatable, Sendable {
    public var wrong: String
    public var correct: String

    public init(wrong: String, correct: String) {
        self.wrong = wrong
        self.correct = correct
    }
}

public struct VocabularyTerm: Codable, Equatable, Sendable {
    public var value: String

    public init(value: String) {
        self.value = value
    }
}

public protocol DictionaryStoring: Sendable {
    var loadErrorDescription: String? { get }
    func entries() -> [DictionaryEntry]
    func terms() -> [VocabularyTerm]
    func save(_ entries: [DictionaryEntry]) throws
    func addTerm(_ value: String) throws
    func replaceTerm(original: String, with value: String) throws
    func deleteTerms(_ values: Set<String>) throws
    func addOrReplace(wrong: String, correct: String) throws
    func delete(wrongValues: Set<String>) throws
    func replace(originalWrong: String, wrong: String, correct: String) throws
    func apply(to text: String) -> String
    func clear() throws
}

public extension DictionaryStoring {
    var loadErrorDescription: String? {
        nil
    }
}

private enum VocabularyTermsMutation {
    static func normalized(_ values: [String]) -> [VocabularyTerm] {
        var seen: Set<String> = []
        return values.compactMap { rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let key = value.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return VocabularyTerm(value: value)
        }
    }

    static func entries(from terms: [VocabularyTerm]) -> [DictionaryEntry] {
        terms.map { DictionaryEntry(wrong: $0.value, correct: $0.value) }
    }

    static func terms(from entries: [DictionaryEntry]) -> [VocabularyTerm] {
        normalized(entries.map(\.correct))
    }
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
        storedEntries = entries
    }

    public convenience init(terms: [VocabularyTerm]) {
        self.init(entries: VocabularyTermsMutation.entries(from: VocabularyTermsMutation.normalized(terms.map(\.value))))
    }

    public var loadErrorDescription: String? {
        nil
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

    public func terms() -> [VocabularyTerm] {
        VocabularyTermsMutation.terms(from: entries())
    }

    public func addTerm(_ value: String) throws {
        mutateTerms { $0 + [value] }
    }

    public func replaceTerm(original: String, with value: String) throws {
        mutateTerms { terms in
            terms.map { $0.caseInsensitiveCompare(original) == .orderedSame ? value : $0 }
        }
    }

    public func deleteTerms(_ values: Set<String>) throws {
        mutateTerms { terms in
            terms.filter { term in
                !values.contains { $0.caseInsensitiveCompare(term) == .orderedSame }
            }
        }
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

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        storedEntries = []
    }

    private func mutateEntries(_ mutation: ([DictionaryEntry]) -> [DictionaryEntry]?) {
        lock.lock()
        defer { lock.unlock() }
        if let updatedEntries = mutation(storedEntries) {
            storedEntries = updatedEntries
        }
    }

    private func mutateTerms(_ mutation: ([String]) -> [String]) {
        lock.lock()
        defer { lock.unlock() }
        let terms = VocabularyTermsMutation.terms(from: storedEntries).map(\.value)
        storedEntries = VocabularyTermsMutation.entries(from: VocabularyTermsMutation.normalized(mutation(terms)))
    }
}

public final class JSONDictionaryStore: DictionaryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private var cachedEntries: [DictionaryEntry]
    private var loadError: Error?

    public init(fileURL: URL) {
        self.fileURL = fileURL

        do {
            let data = try Data(contentsOf: fileURL)
            cachedEntries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
            loadError = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            cachedEntries = []
            loadError = nil
        } catch {
            cachedEntries = []
            loadError = error
        }
    }

    public var loadErrorDescription: String? {
        lock.withLock {
            loadError.map(Self.describe)
        }
    }

    public func entries() -> [DictionaryEntry] {
        lock.withLock {
            cachedEntries
        }
    }

    public func terms() -> [VocabularyTerm] {
        lock.withLock {
            VocabularyTermsMutation.terms(from: cachedEntries)
        }
    }

    public func save(_ entries: [DictionaryEntry]) throws {
        try mutate(allowLoadErrorRecovery: false) { current in
            current = entries
        }
    }

    public func addTerm(_ value: String) throws {
        try mutateTerms { $0 + [value] }
    }

    public func replaceTerm(original: String, with value: String) throws {
        try mutateTerms { terms in
            terms.map { $0.caseInsensitiveCompare(original) == .orderedSame ? value : $0 }
        }
    }

    public func deleteTerms(_ values: Set<String>) throws {
        try mutateTerms { terms in
            terms.filter { term in
                !values.contains { $0.caseInsensitiveCompare(term) == .orderedSame }
            }
        }
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

    public func clear() throws {
        try mutate(allowLoadErrorRecovery: true) { current in
            current = []
        }
    }

    private func mutate(
        allowLoadErrorRecovery: Bool = false,
        _ mutation: (inout [DictionaryEntry]) -> Void
    ) throws {
        try lock.withLock {
            if !allowLoadErrorRecovery, let loadError {
                throw loadError
            }

            if allowLoadErrorRecovery, loadError != nil {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let defaultBackupURL = URL(fileURLWithPath: fileURL.path + ".bak")
                    let bakURL = FileManager.default.fileExists(atPath: defaultBackupURL.path)
                        ? URL(fileURLWithPath: fileURL.path + ".bak-\(UUID().uuidString)")
                        : defaultBackupURL
                    try FileManager.default.copyItem(at: fileURL, to: bakURL)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bakURL.path)
                }
            }

            var newEntries = cachedEntries
            mutation(&newEntries)

            try persist(newEntries)
            cachedEntries = newEntries
            loadError = nil
        }
    }

    private func mutateEntries(_ mutation: ([DictionaryEntry]) -> [DictionaryEntry]?) throws {
        try mutate { entries in
            if let updated = mutation(entries) {
                entries = updated
            }
        }
    }

    private func mutateTerms(_ mutation: ([String]) -> [String]) throws {
        try mutateEntries { entries in
            let terms = VocabularyTermsMutation.terms(from: entries).map(\.value)
            return VocabularyTermsMutation.entries(from: VocabularyTermsMutation.normalized(mutation(terms)))
        }
    }

    private func persist(_ entries: [DictionaryEntry]) throws {
        let directory = fileURL.deletingLastPathComponent()
        // Owner-only data directory: the atomic write briefly leaves the JSON at the umask
        // default (0644) before the chmod below, so keep the enclosing directory 0700 to deny
        // cross-user traversal during that window (defense in depth).
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
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
              let range = working.range(of: source, options: [.caseInsensitive], range: searchStart..<working.endIndex)
        {
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
           original.dropFirst() == original.dropFirst().lowercased()
        {
            return replacement.prefix(1).uppercased() + replacement.dropFirst().lowercased()
        }
        return replacement
    }
}
