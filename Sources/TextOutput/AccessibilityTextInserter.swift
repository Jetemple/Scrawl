import ApplicationServices
import Foundation

/// Inserts text directly into the system's focused UI element. Unlike a synthesized ⌘V
/// (`CGEvent`), the Accessibility API is NOT blocked by macOS Secure Keyboard Entry, so this
/// is how Scrawl can still type for you when a terminal or password manager has secure input on.
public protocol FocusedTextInserting: Sendable {
    /// Replaces the focused element's current selection (or inserts at the caret) with `text`.
    /// Returns `true` only if the text was actually inserted into a verified, non-secure field.
    func insertReplacingSelection(_ text: String) -> Bool
}

/// Decides whether a focused element is a safe place to insert dictation. Pure and exhaustively
/// tested, because this is the guard that keeps spoken text out of password fields.
public enum AXTextInsertionPolicy {
    /// AX roles whose value is editable plain text we can safely write into.
    static let insertableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

    /// The subrole macOS reports for a password field (`NSSecureTextField`). Never insert here.
    static let secureTextFieldSubrole = "AXSecureTextField"

    public static func allowsInsertion(role: String?, subrole: String?) -> Bool {
        guard let role, insertableRoles.contains(role) else { return false }
        if subrole == secureTextFieldSubrole { return false }
        return true
    }
}

/// Real `FocusedTextInserting` backed by the macOS Accessibility API. Requires Accessibility
/// permission (the same grant auto-paste already needs). Fails closed: any AX error, a
/// non-text or secure field, or an un-settable value all return `false` so the caller falls
/// back to the clipboard.
public struct AccessibilityFocusedTextInserter: FocusedTextInserting {
    public init() {}

    public func insertReplacingSelection(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return false }

        // swiftlint:disable:next force_cast
        let element = focused as! AXUIElement
        let role = copyStringAttribute(element, kAXRoleAttribute)
        let subrole = copyStringAttribute(element, kAXSubroleAttribute)
        guard AXTextInsertionPolicy.allowsInsertion(role: role, subrole: subrole) else { return false }

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue
        else { return false }

        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    private func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
