import AppKit

struct UpdateRelease: Equatable {
    let version: String
    let pageURL: URL
}

enum UpdateCheckOutcome: Equatable {
    case upToDate(currentVersion: String)
    case updateAvailable(UpdateRelease)

    /// The release to surface, or nil when the running build is current. Lets
    /// callers fold a check result straight into the cached "update available"
    /// state that drives the menu and About indicators.
    var availableRelease: UpdateRelease? {
        switch self {
        case .upToDate: nil
        case let .updateAvailable(release): release
        }
    }
}

/// Asks GitHub for the newest published release and compares it against the
/// running version. There is no background polling: the check runs only when
/// the user picks "Check for Updates…" from the status menu.
final class UpdateChecker {
    typealias Fetch = (URLRequest, @escaping (Result<Data, Error>) -> Void) -> Void

    enum CheckError: Error, Equatable {
        case malformedResponse
    }

    static let latestReleaseURL = URL(string: "https://api.github.com/repos/Jetemple/Scrawl/releases/latest")!

    /// How long a background check result stays fresh before another is due.
    static let backgroundCheckInterval: TimeInterval = 24 * 60 * 60

    /// Gates the automatic check so it runs at most once a day: always on the
    /// first launch (no prior check), then once the interval has elapsed. The
    /// manual "Check for Updates…" path ignores this and always runs.
    static func shouldCheck(
        lastCheckDate: Date?,
        now: Date,
        interval: TimeInterval = UpdateChecker.backgroundCheckInterval
    ) -> Bool {
        guard let lastCheckDate else { return true }
        return now.timeIntervalSince(lastCheckDate) >= interval
    }

    private let currentVersion: String
    private let fetch: Fetch

    init(currentVersion: String, fetch: @escaping Fetch = UpdateChecker.urlSessionFetch) {
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    /// Calls back on whatever queue the fetcher completes on; UI callers hop
    /// to the main queue themselves.
    func check(completion: @escaping (Result<UpdateCheckOutcome, Error>) -> Void) {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let currentVersion = currentVersion
        fetch(request) { result in
            switch result {
            case let .success(data):
                completion(Self.outcome(fromReleaseData: data, currentVersion: currentVersion))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    static func outcome(fromReleaseData data: Data, currentVersion: String) -> Result<UpdateCheckOutcome, Error> {
        guard let release = try? JSONDecoder().decode(LatestReleasePayload.self, from: data),
              let pageURL = URL(string: release.htmlURL)
        else {
            return .failure(CheckError.malformedResponse)
        }
        let latestVersion = normalizedVersion(release.tagName)
        if isVersion(latestVersion, newerThan: normalizedVersion(currentVersion)) {
            return .success(.updateAvailable(UpdateRelease(version: latestVersion, pageURL: pageURL)))
        }
        return .success(.upToDate(currentVersion: currentVersion))
    }

    /// Release tags are "v0.0.12"; the bundle version is "0.0.12".
    static func normalizedVersion(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    /// Numeric component-wise comparison so "0.0.10" beats "0.0.9". Missing
    /// components count as zero; non-numeric components count as zero too,
    /// which keeps prerelease-style tags from ever looking newer.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = numericComponents(of: candidate)
        let currentParts = numericComponents(of: current)
        for index in 0..<max(candidateParts.count, currentParts.count) {
            let lhs = index < candidateParts.count ? candidateParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs != rhs {
                return lhs > rhs
            }
        }
        return false
    }

    private static func numericComponents(of version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }

    private static func urlSessionFetch(request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(data ?? Data()))
            }
        }.resume()
    }

    private struct LatestReleasePayload: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}

/// The modal shown when the user explicitly asks to check. Background checks
/// stay silent and only refresh the menu/About indicators.
enum UpdateCheckPresenter {
    static func present(_ result: Result<UpdateCheckOutcome, Error>) {
        let alert = NSAlert()
        alert.icon = ScrawlBrandIcon.image()
        switch result {
        case let .success(.upToDate(currentVersion)):
            alert.messageText = "Scrawl Is Up to Date"
            alert.informativeText = "Version \(currentVersion) is the newest release."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        case let .success(.updateAvailable(release)):
            alert.messageText = "Scrawl \(release.version) Is Available"
            alert.informativeText = "Open the release page to download it, or run \"brew upgrade --cask scrawl\"."
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }
        case let .failure(error):
            print("[Scrawl] Update check failed: \(error)")
            alert.messageText = "Couldn't Check for Updates"
            alert.informativeText = "Scrawl couldn't reach GitHub. Try again later."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
