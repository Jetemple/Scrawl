import AppKit

extension StatusBarAppDelegate {
    /// Surfaces any release cached from a prior run, runs the daily background
    /// check, and schedules a periodic re-check. The interval poll is coarse —
    /// the once-a-day gate in the coordinator decides whether each tick actually
    /// hits the network, so a missed tick (sleep, a short session) just folds
    /// into the next one.
    func startUpdateChecking() {
        applyAvailableUpdate(updateCheckCoordinator.availableRelease)
        updateCheckCoordinator.checkInBackgroundIfDue()
        let timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.updateCheckCoordinator.checkInBackgroundIfDue()
        }
        timer.tolerance = 30 * 60
        updateCheckTimer = timer
    }

    @objc func checkForUpdates(_: Any?) {
        updateCheckCoordinator.checkNow()
    }

    @objc func openAvailableUpdate(_: Any?) {
        guard let release = updateCheckCoordinator.availableRelease else { return }
        NSWorkspace.shared.open(release.pageURL)
    }

    /// Reflects the cached "update available" state onto both surfaces: the
    /// coral status-menu item (hidden when current) and the About page.
    func applyAvailableUpdate(_ release: UpdateRelease?) {
        if let release, let item = updateAvailableItem {
            item.attributedTitle = NSAttributedString(
                string: "Update available: \(release.version)",
                attributes: [.foregroundColor: PreferencesPageSupport.accentColor]
            )
            item.isHidden = false
        } else {
            updateAvailableItem?.isHidden = true
        }
        preferencesWindowController?.showAvailableUpdate(release)
    }
}
