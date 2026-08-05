import Foundation

/// Ties the network checker, the on-disk cache, and the two UI surfaces (the
/// status-menu item and the About page) together. Background checks run at most
/// once a day and stay silent; the manual "Check for Updates…" path always runs
/// and shows a modal. Either way the cached "update available" state is
/// refreshed and `onAvailableReleaseChange` fires so the surfaces re-render.
final class UpdateCheckCoordinator {
    /// The running build's version, normalized once at init (it never changes) so
    /// every `availableRelease` read — surfaces query it on menu opens and
    /// preferences refreshes — avoids re-stripping the `v` prefix each time.
    private let normalizedCurrentVersion: String
    private let store: UpdateCheckStore
    private let makeChecker: (String) -> UpdateChecker
    private let present: (Result<UpdateCheckOutcome, Error>) -> Void
    private let now: () -> Date
    private let notifyOnMain: (@escaping () -> Void) -> Void

    /// Fired on the main queue whenever a check refreshes the cached release.
    /// Not called for the initial cached value — read `availableRelease` for
    /// that when wiring surfaces up at launch.
    var onAvailableReleaseChange: ((UpdateRelease?) -> Void)?

    init(
        currentVersion: String,
        store: UpdateCheckStore,
        now: @escaping () -> Date = Date.init,
        makeChecker: @escaping (String) -> UpdateChecker = { UpdateChecker(currentVersion: $0) },
        present: @escaping (Result<UpdateCheckOutcome, Error>) -> Void = UpdateCheckPresenter.present,
        notifyOnMain: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }
    ) {
        normalizedCurrentVersion = UpdateChecker.normalizedVersion(currentVersion)
        self.store = store
        self.now = now
        self.makeChecker = makeChecker
        self.present = present
        self.notifyOnMain = notifyOnMain
    }

    /// The release cached from a prior run, so surfaces render at launch without
    /// waiting on the network — but only while it is genuinely newer than the
    /// running build. A prior version caches the release it found; after the user
    /// installs it, that cache lingers until the next daily check clears it, so we
    /// re-validate here. Otherwise the indicator keeps saying "update available"
    /// for the very version now running.
    var availableRelease: UpdateRelease? {
        guard let cached = store.availableRelease,
              UpdateChecker.isVersion(
                  UpdateChecker.normalizedVersion(cached.version),
                  newerThan: normalizedCurrentVersion
              )
        else { return nil }
        return cached
    }

    /// The daily background check. No-ops when a check ran within the window.
    func checkInBackgroundIfDue() {
        guard UpdateChecker.shouldCheck(lastCheckDate: store.lastCheckDate, now: now()) else { return }
        runCheck(presenting: false)
    }

    /// The user-initiated "Check for Updates…" path: always runs, always shows
    /// the result in a modal.
    func checkNow() {
        runCheck(presenting: true)
    }

    private func runCheck(presenting: Bool) {
        makeChecker(normalizedCurrentVersion).check { [weak self] result in
            self?.notifyOnMain {
                self?.handle(result, presenting: presenting)
            }
        }
    }

    private func handle(_ result: Result<UpdateCheckOutcome, Error>, presenting: Bool) {
        if case let .success(outcome) = result {
            store.record(checkedAt: now(), availableRelease: outcome.availableRelease)
            onAvailableReleaseChange?(outcome.availableRelease)
        }
        if presenting {
            present(result)
        }
    }
}
