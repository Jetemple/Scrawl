import Foundation
import SettingsStore
import TranscriptHistoryStore

struct TranscriptHistoryCoordinator {
    let settingsStore: SettingsStore
    let historyStore: any TranscriptHistoryStoring

    func add(text: String, createdAt: Date = .now) throws {
        guard settingsStore.load().isTranscriptHistoryEnabled else { return }
        try historyStore.add(TranscriptRecord(id: UUID(), createdAt: createdAt, text: text))
    }

    func setEnabled(_ enabled: Bool) throws {
        var settings = settingsStore.load()
        if !enabled {
            try historyStore.clear()
        }
        settings.isTranscriptHistoryEnabled = enabled
        try settingsStore.save(settings)
    }
}
