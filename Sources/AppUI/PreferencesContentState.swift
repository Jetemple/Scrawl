import DictionaryStore
import Foundation
import TranscriptHistoryStore

enum PreferencesContentState {
    static func filteredHistory(records: [TranscriptRecord], query: String) -> [TranscriptRecord] {
        guard !query.isEmpty else {
            return records
        }

        return records.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    static func resolvedHistorySelection(
        currentID: UUID?,
        visibleRecords: [TranscriptRecord]
    ) -> UUID? {
        if let currentID, visibleRecords.contains(where: { $0.id == currentID }) {
            return currentID
        }

        return visibleRecords.first?.id
    }

    static func filteredDictionary(entries: [DictionaryEntry], query: String) -> [DictionaryEntry] {
        guard !query.isEmpty else {
            return entries
        }

        return entries.filter {
            $0.wrong.localizedCaseInsensitiveContains(query)
                || $0.correct.localizedCaseInsensitiveContains(query)
        }
    }
}
