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

    /// First request: show the system prompt ONLY. It already offers "Open System Settings",
    /// so the app must not also open Settings — that's the double-open the user reported.
    func testFirstRequestShowsSystemPromptOnly() {
        XCTAssertEqual(
            AccessibilityPromptDecision.decide(isAuthorized: false, hasShownSystemPrompt: false),
            .showSystemPrompt
        )
    }

    /// Already showed the prompt and still denied: macOS won't re-show it, so Settings is
    /// the only way forward.
    func testRepeatRequestOpensSettings() {
        XCTAssertEqual(
            AccessibilityPromptDecision.decide(isAuthorized: false, hasShownSystemPrompt: true),
            .openSettings
        )
    }

    /// A grant existed before but authorization is gone: the TCC record went stale
    /// (bundle replaced by brew upgrade or DMG drag-over). The record still exists, so
    /// the system prompt can never appear — skip it and guide the user to re-toggle.
    func testLostGrantSkipsSystemPromptAndOpensSettings() {
        XCTAssertEqual(
            AccessibilityPromptDecision.decide(
                isAuthorized: false,
                hasShownSystemPrompt: false,
                wasPreviouslyAuthorized: true
            ),
            .openSettingsForStaleGrant
        )
        XCTAssertEqual(
            AccessibilityPromptDecision.decide(
                isAuthorized: false,
                hasShownSystemPrompt: true,
                wasPreviouslyAuthorized: true
            ),
            .openSettingsForStaleGrant
        )
    }

    /// A prior grant changes nothing once authorization is back.
    func testPriorGrantStillAuthorized() {
        XCTAssertEqual(
            AccessibilityPromptDecision.decide(
                isAuthorized: true,
                hasShownSystemPrompt: false,
                wasPreviouslyAuthorized: true
            ),
            .alreadyAuthorized
        )
    }
}
