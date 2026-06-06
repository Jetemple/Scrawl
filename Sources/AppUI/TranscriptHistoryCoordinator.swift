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

    func add(text: String, createdAt: Date = .now) throws {
        try lock.withLock {
            guard settingsStore.load().isTranscriptHistoryEnabled else { return }
            try historyStore.add(TranscriptRecord(id: UUID(), createdAt: createdAt, text: text))
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        try lock.withLock {
            var settings = settingsStore.load()
            if !enabled {
                try historyStore.clear()
            }
            settings.isTranscriptHistoryEnabled = enabled
            try settingsStore.save(settings)
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
