@testable import TextOutput
import XCTest

final class TextOutputErrorTests: XCTestCase {
    private static let allCases: [TextOutputError] = [
        .accessibilityPermissionRequired,
        .failedToWritePasteboard,
        .failedToCreateEventSource,
        .secureInputActive,
    ]

    func testEveryErrorHasAHumanReadableDescription() {
        for error in Self.allCases {
            let description = error.errorDescription
            XCTAssertNotNil(description, "\(error) has no errorDescription")
            // The raw Swift case name must never leak to the user as the message.
            XCTAssertFalse(description?.contains("secureInputActive") ?? false)
            XCTAssertFalse(description?.contains("accessibilityPermissionRequired") ?? false)
            XCTAssertGreaterThan(description?.count ?? 0, 12, "\(error) description is too terse to be a real sentence")
        }
    }

    func testSecureInputMessageNamesTheFeatureAndRecovery() {
        let description = TextOutputError.secureInputActive.errorDescription ?? ""
        // The common real cause is a terminal or password manager holding secure input —
        // not a focused password field — so name the macOS feature and tell the user how
        // to recover the text they just dictated.
        XCTAssertTrue(description.contains("Secure Keyboard Entry"), "should name the macOS feature: \(description)")
        XCTAssertTrue(description.contains("⌘V"), "should tell the user to press Cmd-V: \(description)")
        XCTAssertTrue(description.localizedCaseInsensitiveContains("clipboard"), "should mention the clipboard: \(description)")
    }

    func testAccessibilityMessagePointsToSettings() {
        let description = TextOutputError.accessibilityPermissionRequired.errorDescription ?? ""
        XCTAssertTrue(description.localizedCaseInsensitiveContains("accessibility"), "should mention Accessibility: \(description)")
    }
}
