/// Collapses the ~18 Parakeet preparation progress callbacks per second down to the
/// handful that actually change what the preferences window shows.
///
/// The window renders preparation as the coarse `modelRowProgressText` ("Preparing",
/// "Downloading N%"). Progress callbacks fire far faster than that text changes —
/// during the optimize phase it stays "Preparing" the whole time — so refreshing the
/// window on every callback rebuilds an identical snapshot ~18x/sec and saturates the
/// main thread. This gate refreshes only when the row text differs from the last one
/// that triggered a refresh. `reset()` starts a fresh session so the next event always
/// refreshes. Mirrors `PreparationStatusDeduper` (which dedupes the menu status text).
struct PreparationRefreshGate {
    private var hasRefreshed = false
    private var lastRowText: String?

    /// Returns true when `rowText` differs from the last value that refreshed (or when no
    /// event has refreshed since the last `reset()`), and records it as the new baseline.
    mutating func shouldRefresh(rowText: String?) -> Bool {
        if hasRefreshed, lastRowText == rowText {
            return false
        }
        hasRefreshed = true
        lastRowText = rowText
        return true
    }

    /// Forgets the baseline so the next event refreshes; call when a preparation session
    /// starts or is cancelled.
    mutating func reset() {
        hasRefreshed = false
        lastRowText = nil
    }
}
