import DictionaryStore
import Foundation
import TranscriptHistoryStore

enum PreferencesContentState {
    enum HistoryMenuState: Equatable {
        case disabled
        case unavailable
        case empty
        case records([TranscriptRecord])
    }

    static func historyMenuState(
        isEnabled: Bool,
        loadErrorDescription: String?,
        records: [TranscriptRecord]
    ) -> HistoryMenuState {
        guard isEnabled else {
            return .disabled
        }
        guard loadErrorDescription == nil else {
            return .unavailable
        }
        guard !records.isEmpty else {
            return .empty
        }
        return .records(Array(records.prefix(12)))
    }

    static func filteredHistory(records: [TranscriptRecord], query: String) -> [TranscriptRecord] {
        let query = normalizedQuery(query)
        guard !query.isEmpty else {
            return records
        }

        return records.filter { $0.text.localizedStandardContains(query) }
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
        let query = normalizedQuery(query)
        guard !query.isEmpty else {
            return entries
        }

        return entries.filter {
            $0.wrong.localizedStandardContains(query)
                || $0.correct.localizedStandardContains(query)
        }
    }

    private static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
