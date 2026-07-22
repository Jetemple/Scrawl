import Foundation

/// Persists the background update-check bookkeeping: when the last check ran
/// (to gate the daily cadence) and the newest release seen (so the menu and
/// About indicators render instantly without re-hitting GitHub). This is
/// app-managed cache, not a user preference, so it lives outside AppSettings.
final class UpdateCheckStore {
    private let defaults: UserDefaults
    private static let lastCheckKey = "scrawl.update.lastCheckDate"
    private static let versionKey = "scrawl.update.availableVersion"
    private static let pageURLKey = "scrawl.update.availablePageURL"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastCheckDate: Date? {
        defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    var availableRelease: UpdateRelease? {
        guard let version = defaults.string(forKey: Self.versionKey),
              let urlString = defaults.string(forKey: Self.pageURLKey),
              let pageURL = URL(string: urlString)
        else {
            return nil
        }
        return UpdateRelease(version: version, pageURL: pageURL)
    }

    /// Stamps the check time and caches the available release, or clears the
    /// cache when `availableRelease` is nil (the build is now current).
    func record(checkedAt: Date, availableRelease release: UpdateRelease?) {
        defaults.set(checkedAt, forKey: Self.lastCheckKey)
        if let release {
            defaults.set(release.version, forKey: Self.versionKey)
            defaults.set(release.pageURL.absoluteString, forKey: Self.pageURLKey)
        } else {
            defaults.removeObject(forKey: Self.versionKey)
            defaults.removeObject(forKey: Self.pageURLKey)
        }
    }
}
