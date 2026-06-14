@testable import AppUI
import XCTest

final class AccessibilityPromptDecisionTests: XCTestCase {
    func testAuthorizedNeedsNoPrompt() {
        XCTAssertEqual(
            AccessibilityPromptDecision.decide(isAuthorized: true, hasShownSystemPrompt: false),
            .alreadyAuthorized
        )
        XCTAssertEqual(
            AccessibilityPromptDecision.decide(isAuthorized: true, hasShownSystemPrompt: true),
            .alreadyAuthorized
        )
    }

    // First request: show the system prompt ONLY. It already offers "Open System Settings",
    // so the app must not also open Settings — that's the double-open the user reported.
    func testFirstRequestShowsSystemPromptOnly() {
        XCTAssertEqual(
            AccessibilityPromptDecision.decide(isAuthorized: false, hasShownSystemPrompt: false),
            .showSystemPrompt
        )
    }

    // Already showed the prompt and still denied: macOS won't re-show it, so Settings is
    // the only way forward.
    func testRepeatRequestOpensSettings() {
        XCTAssertEqual(
            AccessibilityPromptDecision.decide(isAuthorized: false, hasShownSystemPrompt: true),
            .openSettings
        )
    }
}
