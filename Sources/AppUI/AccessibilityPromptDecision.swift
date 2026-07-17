/// Pure decision for how to guide the user toward granting Accessibility, given the
/// current authorization state and whether the macOS system prompt has already been
/// shown this session. Side-effect-free so it is unit-testable.
///
/// The macOS prompt (shown by `AXIsProcessTrustedWithOptions(prompt:)`) already includes
/// an "Open System Settings" button and only appears once per TCC record, so the first
/// request must show the prompt *only* — opening Settings as well pops the notification
/// AND the Settings page at once. Settings is the fallback for a later, still-denied retry.
///
/// Once a grant existed, a lost authorization means the TCC record went stale — typically
/// after the app bundle was replaced in place (brew upgrade, DMG drag-over). System
/// Settings can still show Scrawl as enabled, and the system prompt never reappears
/// because the record exists, so the only way forward is Settings with re-toggle guidance.
enum AccessibilityPromptDecision: Equatable {
    case alreadyAuthorized
    case showSystemPrompt
    case openSettings
    case openSettingsForStaleGrant

    static func decide(
        isAuthorized: Bool,
        hasShownSystemPrompt: Bool,
        wasPreviouslyAuthorized: Bool = false
    ) -> AccessibilityPromptDecision {
        if isAuthorized {
            return .alreadyAuthorized
        }
        if wasPreviouslyAuthorized {
            return .openSettingsForStaleGrant
        }
        return hasShownSystemPrompt ? .openSettings : .showSystemPrompt
    }
}
