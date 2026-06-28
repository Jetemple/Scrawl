@testable import TextOutput
import XCTest

final class AXTextInsertionPolicyTests: XCTestCase {
    func testAllowsPlainTextField() {
        XCTAssertTrue(AXTextInsertionPolicy.allowsInsertion(role: "AXTextField", subrole: nil))
    }

    func testAllowsTextArea() {
        XCTAssertTrue(AXTextInsertionPolicy.allowsInsertion(role: "AXTextArea", subrole: nil))
    }

    func testAllowsComboBox() {
        XCTAssertTrue(AXTextInsertionPolicy.allowsInsertion(role: "AXComboBox", subrole: nil))
    }

    func testRejectsSecureTextField() {
        // The whole point of the guard: never insert dictation into a password field.
        XCTAssertFalse(AXTextInsertionPolicy.allowsInsertion(role: "AXTextField", subrole: "AXSecureTextField"))
    }

    func testRejectsNonTextRole() {
        XCTAssertFalse(AXTextInsertionPolicy.allowsInsertion(role: "AXButton", subrole: nil))
    }

    func testRejectsNilRole() {
        XCTAssertFalse(AXTextInsertionPolicy.allowsInsertion(role: nil, subrole: nil))
    }
}

private final class StubInserter: FocusedTextInserting, @unchecked Sendable {
    let result: Bool
    private(set) var received: String?
    init(result: Bool) {
        self.result = result
    }

    func insertReplacingSelection(_ text: String) -> Bool {
        received = text
        return result
    }
}

final class PasteboardTextOutputSecureInputTests: XCTestCase {
    private func makePasteboard(seed: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString(seed, forType: .string)
        return pasteboard
    }

    func testSecureInputInsertsViaAccessibilityAndLeavesClipboardAlone() async throws {
        let pasteboard = makePasteboard(seed: "original")
        let inserter = StubInserter(result: true)
        let output = PasteboardTextOutput(
            pasteboard: pasteboard,
            focusedTextInserter: inserter,
            isAccessibilityTrusted: { true },
            isSecureInputActive: { true }
        )

        try await output.output("hello world", markPrivate: true)

        XCTAssertEqual(inserter.received, "hello world")
        // Direct AX insertion succeeded, so the clipboard must be left untouched.
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testSecureInputFallsBackToClipboardWhenNoSafeField() async {
        let pasteboard = makePasteboard(seed: "original")
        let inserter = StubInserter(result: false)
        let output = PasteboardTextOutput(
            pasteboard: pasteboard,
            focusedTextInserter: inserter,
            isAccessibilityTrusted: { true },
            isSecureInputActive: { true }
        )

        do {
            try await output.output("hello world", markPrivate: true)
            XCTFail("expected secureInputActive to be thrown when no safe field is available")
        } catch {
            XCTAssertEqual(error as? TextOutputError, .secureInputActive)
        }
        // No safe target — the transcript is parked on the clipboard for manual paste.
        XCTAssertEqual(pasteboard.string(forType: .string), "hello world")
    }
}
