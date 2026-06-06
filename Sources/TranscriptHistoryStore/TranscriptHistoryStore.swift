import Foundation

public struct TranscriptRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let text: String

    public init(id: UUID, createdAt: Date, text: String) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
    }
}

public protocol TranscriptHistoryStoring: Sendable {
    var loadErrorDescription: String? { get }
    func records() -> [TranscriptRecord]
    func add(_ record: TranscriptRecord) throws
    func delete(ids: Set<UUID>) throws
    func clear() throws
}

public extension TranscriptHistoryStoring {
    var loadErrorDescription: String? { nil }
}

public final class InMemoryTranscriptHistoryStore: TranscriptHistoryStoring, @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var cachedRecords: [TranscriptRecord]

    public init(records: [TranscriptRecord] = [], limit: Int = 100) {
        self.limit = max(0, limit)
        cachedRecords = Self.normalize(records, limit: self.limit)
    }

    public var loadErrorDescription: String? { nil }

    public func records() -> [TranscriptRecord] {
        lock.withLock {
            cachedRecords
        }
    }

    public func add(_ record: TranscriptRecord) throws {
        lock.withLock {
            cachedRecords = Self.normalize(cachedRecords + [record], limit: limit)
        }
    }

    public func delete(ids: Set<UUID>) throws {
        lock.withLock {
            cachedRecords.removeAll { ids.contains($0.id) }
        }
    }

    public func clear() throws {
        lock.withLock {
            cachedRecords.removeAll()
        }
    }

    fileprivate static func normalize(_ records: [TranscriptRecord], limit: Int) -> [TranscriptRecord] {
        Array(records
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit))
    }
}

/// The live app should own one instance; writes are serialized within an instance, not across instances.
public final class JSONTranscriptHistoryStore: TranscriptHistoryStoring, @unchecked Sendable {
    private let fileURL: URL
    private let limit: Int
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private var cachedRecords: [TranscriptRecord]
    private var loadError: Error?

    public init(fileURL: URL, limit: Int = 100) {
        self.fileURL = fileURL
        self.limit = max(0, limit)

        do {
            let data = try Data(contentsOf: fileURL)
            let records = try JSONDecoder().decode([TranscriptRecord].self, from: data)
            cachedRecords = InMemoryTranscriptHistoryStore.normalize(records, limit: self.limit)
            loadError = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            cachedRecords = []
            loadError = nil
        } catch {
            cachedRecords = []
            loadError = error
        }
    }

    public func records() -> [TranscriptRecord] {
        lock.withLock {
            cachedRecords
        }
    }

    public var loadErrorDescription: String? {
        lock.withLock {
            loadError.map(Self.describe)
        }
    }

    public func add(_ record: TranscriptRecord) throws {
        try mutate { records in
            records.append(record)
        }
    }

    public func delete(ids: Set<UUID>) throws {
        try mutate { records in
            records.removeAll { ids.contains($0.id) }
        }
    }

    public func clear() throws {
        try mutate(allowLoadErrorRecovery: true) { records in
            records.removeAll()
        }
    }

    private func mutate(
        allowLoadErrorRecovery: Bool = false,
        _ mutation: (inout [TranscriptRecord]) -> Void
    ) throws {
        try lock.withLock {
            if !allowLoadErrorRecovery, let loadError {
                throw loadError
            }

            var newRecords = cachedRecords
            mutation(&newRecords)
            newRecords = InMemoryTranscriptHistoryStore.normalize(newRecords, limit: limit)

            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(newRecords).write(to: fileURL, options: .atomic)
            cachedRecords = newRecords
            loadError = nil
        }
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
