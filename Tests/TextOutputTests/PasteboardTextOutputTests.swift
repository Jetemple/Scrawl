@testable import TextOutput
import XCTest

final class PasteboardTextOutputTests: XCTestCase {
    func testTranscriptWriteMarksTransientAndConcealed() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        PasteboardTextOutput.writeTranscript("hello world", to: pasteboard)
        let item = pasteboard.pasteboardItems?.first
        XCTAssertEqual(item?.string(forType: .string), "hello world")
        XCTAssertTrue(item?.types.contains(.init("org.nspasteboard.TransientType")) ?? false)
        XCTAssertTrue(item?.types.contains(.init("org.nspasteboard.ConcealedType")) ?? false)
    }

    func testWriteTranscriptWithMarkPrivateFalseOmitsMarkers() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        PasteboardTextOutput.writeTranscript("hello world", to: pasteboard, markPrivate: false)
        let item = pasteboard.pasteboardItems?.first
        XCTAssertEqual(item?.string(forType: .string), "hello world")
        XCTAssertFalse(item?.types.contains(.init("org.nspasteboard.TransientType")) ?? true)
        XCTAssertFalse(item?.types.contains(.init("org.nspasteboard.ConcealedType")) ?? true)
    }

    func testWriteTranscriptWithMarkPrivateTrueIncludesMarkers() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        PasteboardTextOutput.writeTranscript("hello world", to: pasteboard, markPrivate: true)
        let item = pasteboard.pasteboardItems?.first
        XCTAssertTrue(item?.types.contains(.init("org.nspasteboard.TransientType")) ?? false)
        XCTAssertTrue(item?.types.contains(.init("org.nspasteboard.ConcealedType")) ?? false)
    }

    func testRestoreSkippedWhenPasteboardChangedExternally() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        PasteboardTextOutput.writeTranscript("transcript", to: pasteboard)
        let countAfterWrite = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("user copied this meanwhile", forType: .string)
        snapshot.restoreIfUnchanged(into: pasteboard, expectedChangeCount: countAfterWrite)
        XCTAssertEqual(pasteboard.string(forType: .string), "user copied this meanwhile")
    }

    func testRestoreAppliedWhenChangeCountMatches() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        PasteboardTextOutput.writeTranscript("transcript", to: pasteboard)
        let countAfterWrite = pasteboard.changeCount
        snapshot.restoreIfUnchanged(into: pasteboard, expectedChangeCount: countAfterWrite)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }
}
