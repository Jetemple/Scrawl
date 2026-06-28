/// Pure decision function for hotkey capture.
///
/// Accepted key categories:
/// - Modifier keys (Caps Lock, Shift, Control, Option, Command, Fn) — handled
///   via .flagsChanged events upstream; this path is for .keyDown only.
/// - Function keys F1–F20 and other keys that produce Unicode scalars in the
///   private-use range 0xF700–0xF8FF (NSFunctionKey range), which covers
///   arrow keys, Home, End, Page Up/Down, Delete, etc.
/// - Keys that produce no characters at all (characters == nil or "").
///
/// Rejected:
/// - Any key whose characters contain a scalar outside the 0xF700–0xF8FF
///   private-use range — i.e., a key that would type visible text.
///
/// Arrow-key policy: arrow keys produce characters in the 0xF700–0xF8FF range
/// (NSUpArrowFunctionKey = 0xF700, etc.) so they technically pass the filter,
/// but we reject them anyway: they are essential for text navigation across the
/// system, so binding one as the recording hotkey would break cursor movement
/// everywhere. Their scalar range 0xF700–0xF703 is treated as disallowed in
/// addition to printable keys.
///
/// Parameter design: takes plain values rather than NSEvent so the function is
/// testable without a real event object.
enum HotkeyCaptureFilter {
    /// Function-key private-use Unicode range (NSF1FunctionKey … NSDeleteFunctionKey etc.)
    private static let functionKeyScalarRange: ClosedRange<UInt32> = 0xF700...0xF8FF

    /// Arrow keys are in the low end of the function-key range (Up=0xF700, Down=0xF701,
    /// Left=0xF702, Right=0xF703).  We reject them explicitly so users cannot bind a key
    /// that is needed for text cursor movement in every app.
    private static let arrowKeyScalarRange: ClosedRange<UInt32> = 0xF700...0xF703

    /// Returns `true` if this key is acceptable as a hotkey, `false` if it should
    /// be rejected (with a message shown to the user).
    ///
    /// - Parameters:
    ///   - keyCode: The `NSEvent.keyCode` of the key-down event.
    ///   - characters: The `NSEvent.characters` string (may be nil or empty).
    static func isAccepted(keyCode _: UInt16, characters: String?) -> Bool {
        // No characters at all — a non-printing key, allow it.
        guard let chars = characters, !chars.isEmpty else {
            return true
        }

        // All scalars must be in the function-key private-use range and NOT in
        // the arrow-key sub-range.
        for scalar in chars.unicodeScalars {
            let v = scalar.value
            if !functionKeyScalarRange.contains(v) {
                // Scalar produces visible text — reject.
                return false
            }
            if arrowKeyScalarRange.contains(v) {
                // Arrow key — reject (needed for text editing everywhere).
                return false
            }
        }

        // All scalars were function-key private-use and not arrow keys — accept.
        return true
    }
}
