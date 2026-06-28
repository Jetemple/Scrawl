import Foundation

/// Wording for the "delete model" confirmation. Built-in (catalog) models can be
/// downloaded again from Settings, so deleting one only frees disk. A user-imported
/// model has no download source — Scrawl can't get it back — so the copy must not
/// promise a re-download. Kept pure so both branches are covered by tests.
enum ModelDeletionPrompt {
    /// - Parameters:
    ///   - sizeNote: pre-formatted size suffix like " (466 MB)", or "" when unknown.
    ///   - isBuiltIn: true when the model is in the downloadable catalog.
    static func informativeText(sizeNote: String, isBuiltIn: Bool) -> String {
        let base = "This removes the model file\(sizeNote) from your Mac."
        if isBuiltIn {
            return "\(base) You can download it again anytime in Settings → Models."
        }
        return "\(base) You added this model yourself, so you'll need to add the file again to use it later."
    }
}
