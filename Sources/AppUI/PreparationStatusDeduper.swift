enum PreparationStatusDeduper {
    static func shouldApply(_ text: String, latestStatusText: String) -> Bool {
        !(isParakeetPreparationStatus(text) && text == latestStatusText)
    }

    private static func isParakeetPreparationStatus(_ text: String) -> Bool {
        text.hasPrefix("Setting up Parakeet")
            || text.hasPrefix("Loading Parakeet")
            || text.hasPrefix("Downloading Parakeet model")
            || text.hasPrefix("Optimizing Parakeet")
    }
}
