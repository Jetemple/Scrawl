import Foundation
import SettingsStore
import TranscriptHistoryStore

/// The live app must own one instance and route all transcript-history mutations through it.
final class TranscriptHistoryCoordinator: @unchecked Sendable {
    let settingsStore: SettingsStore
    let historyStore: any TranscriptHistoryStoring
    private let lock = NSLock()

    init(settingsStore: SettingsStore, historyStore: any TranscriptHistoryStoring) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
    }

    func add(
        text: String,
        createdAt: Date = .now,
        recordingDurationMS: Int? = nil,
        transcriptionLatencyMS: Int? = nil
    ) throws {
        try lock.withLock {
            guard settingsStore.load().isTranscriptHistoryEnabled else { return }
            try historyStore.add(TranscriptRecord(
                id: UUID(),
                createdAt: createdAt,
                text: text,
                recordingDurationMS: recordingDurationMS,
                transcriptionLatencyMS: transcriptionLatencyMS
            ))
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        try lock.withLock {
            if !enabled {
                try historyStore.clear()
            }
            try settingsStore.mutate { $0.isTranscriptHistoryEnabled = enabled }
        }
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
