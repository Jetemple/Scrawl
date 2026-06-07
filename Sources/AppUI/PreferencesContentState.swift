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

    static func filteredVocabulary(terms: [VocabularyTerm], query: String) -> [VocabularyTerm] {
        let query = normalizedQuery(query)
        guard !query.isEmpty else { return terms }
        return terms.filter { $0.value.localizedStandardContains(query) }
    }

    static func historyMetrics(for record: TranscriptRecord) -> String {
        let wordCount = record.text.split(whereSeparator: \.isWhitespace).count
        var metrics = ["\(wordCount) \(wordCount == 1 ? "word" : "words")"]
        if let durationMS = record.recordingDurationMS, durationMS > 0 {
            metrics.append("\(formattedDuration(durationMS)) recording")
            metrics.append("\(Int((Double(wordCount) * 60_000 / Double(durationMS)).rounded())) WPM")
        }
        if let latencyMS = record.transcriptionLatencyMS, latencyMS > 0 {
            metrics.append("transcribed in \(formattedDuration(latencyMS))")
        }
        return metrics.joined(separator: " · ")
    }

    static func vocabularyPrompt(
        terms: [VocabularyTerm],
        maximumLength: Int = 500
    ) -> String? {
        var seen: Set<String> = []
        var accepted: [String] = []
        let prefix = "Preferred vocabulary: "

        for term in terms {
            let value = term.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value.lowercased()).inserted else { continue }
            let candidate = prefix + (accepted + [value]).joined(separator: ", ")
            guard candidate.count <= maximumLength else { continue }
            accepted.append(value)
        }

        guard !accepted.isEmpty else { return nil }
        return prefix + accepted.joined(separator: ", ")
    }

    private static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formattedDuration(_ milliseconds: Int) -> String {
        if milliseconds < 1_000 {
            return "\(milliseconds)ms"
        }
        let seconds = Double(milliseconds) / 1_000
        return seconds.rounded() == seconds
            ? "\(Int(seconds))s"
            : String(format: "%.1fs", seconds)
    }
}
