/// Pure decision for how to guide the user toward granting Accessibility, given the
/// current authorization state and whether the macOS system prompt has already been
/// shown this session. Side-effect-free so it is unit-testable.
///
/// The macOS prompt (shown by `AXIsProcessTrustedWithOptions(prompt:)`) already includes
/// an "Open System Settings" button and only appears once per TCC record, so the first
/// request must show the prompt *only* — opening Settings as well pops the notification
/// AND the Settings page at once. Settings is the fallback for a later, still-denied retry.
enum AccessibilityPromptDecision: Equatable {
    case alreadyAuthorized
    case showSystemPrompt
    case openSettings

    static func decide(isAuthorized: Bool, hasShownSystemPrompt: Bool) -> AccessibilityPromptDecision {
        if isAuthorized {
            return .alreadyAuthorized
        }
        return hasShownSystemPrompt ? .openSettings : .showSystemPrompt
    }
}
