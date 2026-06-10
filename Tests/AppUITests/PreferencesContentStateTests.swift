@testable import AppUI
import DictionaryStore
import Foundation
import TranscriptHistoryStore
import XCTest

final class PreferencesContentStateTests: XCTestCase {
    func testVocabularyPromptNormalizesDeduplicatesAndBoundsTerms() {
        let prompt = PreferencesContentState.vocabularyPrompt(
            terms: [
                VocabularyTerm(value: " Anduril "),
                VocabularyTerm(value: "anduril"),
                VocabularyTerm(value: "Postgres"),
                VocabularyTerm(value: String(repeating: "x", count: 500))
            ],
            maximumLength: 48
        )

        XCTAssertEqual(prompt, "Preferred vocabulary: Anduril, Postgres")
    }

    func testVocabularyPromptIsNilWithoutUsableTerms() {
        XCTAssertNil(PreferencesContentState.vocabularyPrompt(terms: [VocabularyTerm(value: "  ")]))
    }

    func testHistoryMetricsIncludeAvailablePerformanceData() {
        let record = TranscriptRecord(
            id: UUID(),
            createdAt: .now,
            text: "one two three four",
            recordingDurationMS: 2_000,
            transcriptionLatencyMS: 1_400
        )

        XCTAssertEqual(
            PreferencesContentState.historyMetrics(for: record),
            "2s audio · 1.4s processing"
        )
    }

    func testHistoryMetricsOmitUnavailableLegacyPerformanceData() {
        let record = TranscriptRecord(id: UUID(), createdAt: .now, text: "one two")

        XCTAssertEqual(PreferencesContentState.historyMetrics(for: record), "")
    }

    func testFilteredVocabularyMatchesPreferredTerms() {
        let terms = [VocabularyTerm(value: "Anduril"), VocabularyTerm(value: "Postgres")]

        XCTAssertEqual(PreferencesContentState.filteredVocabulary(terms: terms, query: "and").map(\.value), ["Anduril"])
    }

    func testHistoryMenuStateIsDisabledBeforeConsideringStoreHealth() {
        XCTAssertEqual(
            PreferencesContentState.historyMenuState(
                isEnabled: false,
                loadErrorDescription: "corrupt",
                records: []
            ),
            .disabled
        )
    }

    func testHistoryMenuStateIsUnavailableForLoadFailure() {
        XCTAssertEqual(
            PreferencesContentState.historyMenuState(
                isEnabled: true,
                loadErrorDescription: "corrupt",
                records: []
            ),
            .unavailable
        )
    }

    func testHistoryMenuStateIsEmptyForHealthyEmptyStore() {
        XCTAssertEqual(
            PreferencesContentState.historyMenuState(
                isEnabled: true,
                loadErrorDescription: nil,
                records: []
            ),
            .empty
        )
    }

    func testHistoryMenuStateContainsNewestTwelveRecords() {
        let records = (0..<15).map {
            TranscriptRecord(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: TimeInterval(15 - $0)),
                text: "\($0)"
            )
        }

        XCTAssertEqual(
            PreferencesContentState.historyMenuState(
                isEnabled: true,
                loadErrorDescription: nil,
                records: records
            ),
            .records(Array(records.prefix(12)))
        )
    }

    func testFilteredHistoryReturnsAllRecordsForEmptyQueryAndPreservesOrder() {
        let records = [
            record(id: "00000000-0000-0000-0000-000000000001", text: "First"),
            record(id: "00000000-0000-0000-0000-000000000002", text: "Second")
        ]

        XCTAssertEqual(PreferencesContentState.filteredHistory(records: records, query: ""), records)
    }

    func testFilteredHistoryMatchesTextCaseInsensitivelyAndPreservesOrder() {
        let matchingFirst = record(id: "00000000-0000-0000-0000-000000000001", text: "Kubernetes notes")
        let nonmatching = record(id: "00000000-0000-0000-0000-000000000002", text: "Swift notes")
        let matchingLast = record(id: "00000000-0000-0000-0000-000000000003", text: "More KUBERNETES")

        XCTAssertEqual(
            PreferencesContentState.filteredHistory(
                records: [matchingFirst, nonmatching, matchingLast],
                query: "kubernetes"
            ),
            [matchingFirst, matchingLast]
        )
    }

    func testFilteredHistoryNormalizesWhitespaceOnlyAndPaddedQueries() {
        let matching = record(id: "00000000-0000-0000-0000-000000000001", text: "Kubernetes notes")
        let nonmatching = record(id: "00000000-0000-0000-0000-000000000002", text: "Swift notes")
        let records = [matching, nonmatching]

        XCTAssertEqual(PreferencesContentState.filteredHistory(records: records, query: " \n\t "), records)
        XCTAssertEqual(
            PreferencesContentState.filteredHistory(records: records, query: "  Kubernetes\n"),
            [matching]
        )
    }

    func testFilteredHistoryUsesLocalizedStandardMatching() {
        let matching = record(id: "00000000-0000-0000-0000-000000000001", text: "Résumé notes")

        XCTAssertEqual(
            PreferencesContentState.filteredHistory(records: [matching], query: "resume"),
            [matching]
        )
    }

    func testResolvedHistorySelectionRetainsVisibleCurrentSelection() {
        let first = record(id: "00000000-0000-0000-0000-000000000001", text: "First")
        let current = record(id: "00000000-0000-0000-0000-000000000002", text: "Current")

        XCTAssertEqual(
            PreferencesContentState.resolvedHistorySelection(
                currentID: current.id,
                visibleRecords: [first, current]
            ),
            current.id
        )
    }

    func testResolvedHistorySelectionFallsBackToFirstVisibleRecord() {
        let first = record(id: "00000000-0000-0000-0000-000000000001", text: "First")
        let second = record(id: "00000000-0000-0000-0000-000000000002", text: "Second")
        let hiddenID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

        XCTAssertEqual(
            PreferencesContentState.resolvedHistorySelection(
                currentID: hiddenID,
                visibleRecords: [first, second]
            ),
            first.id
        )
    }

    func testResolvedHistorySelectionReturnsNilForEmptyResults() {
        XCTAssertNil(
            PreferencesContentState.resolvedHistorySelection(
                currentID: UUID(),
                visibleRecords: []
            )
        )
    }

    func testFilteredDictionaryMatchesWrongOrCorrectCaseInsensitivelyAndPreservesOrder() {
        let wrongMatch = DictionaryEntry(wrong: "kuber netties", correct: "Kubernetes")
        let nonmatching = DictionaryEntry(wrong: "pie torch", correct: "PyTorch")
        let correctMatch = DictionaryEntry(wrong: "whispr", correct: "KUBERNETES Whisper")

        XCTAssertEqual(
            PreferencesContentState.filteredDictionary(
                entries: [wrongMatch, nonmatching, correctMatch],
                query: "kubernetes"
            ),
            [wrongMatch, correctMatch]
        )
    }

    func testFilteredDictionaryReturnsAllForEmptyQueryAndEmptyForNoMatches() {
        let entries = [
            DictionaryEntry(wrong: "wispr", correct: "Whisper"),
            DictionaryEntry(wrong: "pie torch", correct: "PyTorch")
        ]

        XCTAssertEqual(PreferencesContentState.filteredDictionary(entries: entries, query: ""), entries)
        XCTAssertEqual(PreferencesContentState.filteredDictionary(entries: entries, query: "missing"), [])
    }

    func testFilteredDictionaryNormalizesWhitespaceOnlyAndPaddedQueries() {
        let matching = DictionaryEntry(wrong: "kuber netties", correct: "Kubernetes")
        let nonmatching = DictionaryEntry(wrong: "pie torch", correct: "PyTorch")
        let entries = [matching, nonmatching]

        XCTAssertEqual(PreferencesContentState.filteredDictionary(entries: entries, query: " \n\t "), entries)
        XCTAssertEqual(
            PreferencesContentState.filteredDictionary(entries: entries, query: "\n Kubernetes  "),
            [matching]
        )
    }

    func testFilteredDictionaryUsesLocalizedStandardMatchingForBothColumns() {
        let wrongMatch = DictionaryEntry(wrong: "Résumé", correct: "CV")
        let correctMatch = DictionaryEntry(wrong: "CV", correct: "Résumé")

        XCTAssertEqual(
            PreferencesContentState.filteredDictionary(entries: [wrongMatch, correctMatch], query: "resume"),
            [wrongMatch, correctMatch]
        )
    }

    private func record(id: String, text: String) -> TranscriptRecord {
        TranscriptRecord(id: UUID(uuidString: id)!, createdAt: .distantPast, text: text)
    }
}
