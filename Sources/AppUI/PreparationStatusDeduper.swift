enum PreparationStatusDeduper {
    static func shouldApply(_ text: String, latestStatusText: String) -> Bool {
        !(text.hasPrefix("Preparing Parakeet") && text == latestStatusText)
    }
}
