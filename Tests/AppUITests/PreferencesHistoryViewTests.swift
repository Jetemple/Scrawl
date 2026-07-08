import AppKit
@testable import AppUI
import TranscriptHistoryStore
import XCTest

final class PreferencesHistoryViewTests: XCTestCase {
    @MainActor
    private func makeView() -> PreferencesHistoryView {
        PreferencesHistoryView(actions: .init(
            setEnabled: { _ in },
            copy: { _ in },
            repaste: { _ in },
            delete: { _ in }
        ))
    }

    private func record(_ text: String) -> TranscriptRecord {
        TranscriptRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(abs(text.hashValue % 10))") ?? UUID(),
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            text: text,
            recordingDurationMS: 2000,
            transcriptionLatencyMS: 350
        )
    }

    @MainActor
    func testUpdateWithUnchangedInputsSkipsContentReload() {
        let view = makeView()
        let records = [record("first transcript"), record("second transcript")]

        view.update(records: records, isEnabled: true, loadErrorDescription: nil)
        let reloadsAfterFirstUpdate = view.contentReloadCount

        view.update(records: records, isEnabled: true, loadErrorDescription: nil)
        view.update(records: records, isEnabled: true, loadErrorDescription: nil)

        XCTAssertEqual(
            view.contentReloadCount, reloadsAfterFirstUpdate,
            "identical history snapshots must not reload the transcript table"
        )
    }

    @MainActor
    func testUnchangedEnabledSnapshotResyncsToggleStateAfterCancelledDisable() throws {
        let view = makeView()
        let records = [record("first transcript")]
        view.update(records: records, isEnabled: true, loadErrorDescription: nil)
        let toggle = try XCTUnwrap(view.button(titled: "Save transcript history"))

        toggle.performClick(nil)
        XCTAssertEqual(toggle.state, .off)

        view.update(records: records, isEnabled: true, loadErrorDescription: nil)

        XCTAssertEqual(toggle.state, .on)
    }

    @MainActor
    func testUpdateWithChangedRecordsReloadsContent() {
        let view = makeView()
        view.update(records: [record("first transcript")], isEnabled: true, loadErrorDescription: nil)
        let reloadsAfterFirstUpdate = view.contentReloadCount

        view.update(
            records: [record("first transcript"), record("another transcript")],
            isEnabled: true,
            loadErrorDescription: nil
        )

        XCTAssertEqual(view.contentReloadCount, reloadsAfterFirstUpdate + 1)
        XCTAssertEqual(view.visibleRecordIDs.count, 2)
    }

    @MainActor
    func testUpdateWithToggledEnabledStateStillApplies() {
        let view = makeView()
        let records = [record("first transcript")]
        view.update(records: records, isEnabled: true, loadErrorDescription: nil)

        view.update(records: records, isEnabled: false, loadErrorDescription: nil)

        XCTAssertEqual(view.state, .disabled)
    }
}

private extension NSView {
    func button(titled title: String) -> NSButton? {
        if let button = self as? NSButton, button.title == title {
            return button
        }
        return subviews.lazy.compactMap { $0.button(titled: title) }.first
    }
}
