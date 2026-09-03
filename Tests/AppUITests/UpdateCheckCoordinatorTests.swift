@testable import AppUI
import XCTest

final class UpdateCheckCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: UpdateCheckStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "scrawl.coordinator.tests.\(UUID().uuidString)")
        store = UpdateCheckStore(defaults: defaults)
    }

    override func tearDown() {
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testBackgroundCheckSkipsWhenWithinTheDailyWindow() {
        store.record(checkedAt: Self.noon.addingTimeInterval(-60), availableRelease: nil)
        var checkerBuilt = false
        let coordinator = makeCoordinator(fetchResult: .success(Self.upToDateData)) { checkerBuilt = true }

        coordinator.checkInBackgroundIfDue()

        XCTAssertFalse(checkerBuilt, "A check within the daily window should not touch the network")
    }

    func testBackgroundCheckRunsWhenDueAndCachesTheReleaseWithoutPresenting() {
        var presented: [Result<UpdateCheckOutcome, Error>] = []
        var changes: [UpdateRelease?] = []
        let coordinator = makeCoordinator(
            fetchResult: .success(Self.updateAvailableData),
            present: { presented.append($0) }
        )
        coordinator.onAvailableReleaseChange = { changes.append($0) }

        coordinator.checkInBackgroundIfDue()

        XCTAssertEqual(changes, [UpdateRelease(version: "9.9.9", pageURL: Self.pageURL)])
        XCTAssertEqual(store.availableRelease, UpdateRelease(version: "9.9.9", pageURL: Self.pageURL))
        XCTAssertEqual(store.lastCheckDate, Self.noon)
        XCTAssertTrue(presented.isEmpty, "Background checks stay silent")
    }

    func testManualCheckPresentsAndRefreshesTheCache() {
        var presented: [Result<UpdateCheckOutcome, Error>] = []
        let coordinator = makeCoordinator(
            fetchResult: .success(Self.updateAvailableData),
            present: { presented.append($0) }
        )

        coordinator.checkNow()

        XCTAssertEqual(presented.count, 1)
        XCTAssertEqual(store.availableRelease, UpdateRelease(version: "9.9.9", pageURL: Self.pageURL))
    }

    func testCheckClearsAStaleCachedReleaseWhenNowUpToDate() {
        store.record(
            checkedAt: Self.noon.addingTimeInterval(-Self.day),
            availableRelease: UpdateRelease(version: "9.9.9", pageURL: Self.pageURL)
        )
        var changes: [UpdateRelease?] = []
        let coordinator = makeCoordinator(fetchResult: .success(Self.upToDateData))
        coordinator.onAvailableReleaseChange = { changes.append($0) }

        coordinator.checkInBackgroundIfDue()

        XCTAssertEqual(changes, [UpdateRelease?.none])
        XCTAssertNil(store.availableRelease)
    }

    func testFailedCheckDoesNotTouchTheCacheButStillPresentsWhenManual() {
        store.record(
            checkedAt: Self.noon.addingTimeInterval(-Self.day),
            availableRelease: UpdateRelease(version: "9.9.9", pageURL: Self.pageURL)
        )
        struct FetchFailure: Error {}
        var presented: [Result<UpdateCheckOutcome, Error>] = []
        var changes: [UpdateRelease?] = []
        let coordinator = makeCoordinator(
            fetchResult: .failure(FetchFailure()),
            present: { presented.append($0) }
        )
        coordinator.onAvailableReleaseChange = { changes.append($0) }

        coordinator.checkNow()

        XCTAssertEqual(presented.count, 1)
        XCTAssertTrue(changes.isEmpty, "A failed check leaves the cache alone")
        XCTAssertEqual(store.availableRelease, UpdateRelease(version: "9.9.9", pageURL: Self.pageURL))
    }

    func testCachedReleaseAtOrBelowCurrentVersionIsNotSurfaced() {
        // A prior build cached this release; the user has since updated to it (or past
        // it). Until the next daily check clears the cache, the indicator must already
        // read "up to date" — the getter re-validates against the running version.
        store.record(
            checkedAt: Self.noon.addingTimeInterval(-60),
            availableRelease: UpdateRelease(version: "1.0.0", pageURL: Self.pageURL)
        )
        let coordinator = makeCoordinator(fetchResult: .success(Self.upToDateData))

        XCTAssertNil(coordinator.availableRelease, "The running build's own version is not an available update")
    }

    func testCachedReleaseOlderThanCurrentVersionIsNotSurfaced() {
        // The user didn't just install the cached release — they're running a build
        // that is already newer than it (jumped several releases, or a newer build
        // from another channel). An older cached release is still stale and must not
        // be surfaced as an update.
        store.record(
            checkedAt: Self.noon.addingTimeInterval(-60),
            availableRelease: UpdateRelease(version: "0.0.9", pageURL: Self.pageURL)
        )
        let coordinator = makeCoordinator(fetchResult: .success(Self.upToDateData))

        XCTAssertNil(coordinator.availableRelease, "A cached release older than the running build is not an update")
    }

    func testCachedReleaseWithVPrefixMatchingCurrentVersionIsNotSurfaced() {
        // The cache can hold a "v"-prefixed version (a legacy build stored it
        // unnormalized). The getter must normalize before comparing, so a cached
        // "v1.0.0" is treated as equal to the running "1.0.0", not newer.
        store.record(
            checkedAt: Self.noon.addingTimeInterval(-60),
            availableRelease: UpdateRelease(version: "v1.0.0", pageURL: Self.pageURL)
        )
        let coordinator = makeCoordinator(fetchResult: .success(Self.upToDateData))

        XCTAssertNil(coordinator.availableRelease, "A 'v'-prefixed cached release matching the running version is not an update")
    }

    func testCachedReleaseNewerThanCurrentVersionIsSurfaced() {
        store.record(
            checkedAt: Self.noon.addingTimeInterval(-60),
            availableRelease: UpdateRelease(version: "9.9.9", pageURL: Self.pageURL)
        )
        let coordinator = makeCoordinator(fetchResult: .success(Self.upToDateData))

        XCTAssertEqual(
            coordinator.availableRelease,
            UpdateRelease(version: "9.9.9", pageURL: Self.pageURL),
            "A genuinely newer cached release still renders at launch"
        )
    }

    private func makeCoordinator(
        fetchResult: Result<Data, Error>,
        present: @escaping (Result<UpdateCheckOutcome, Error>) -> Void = { _ in },
        onCheckerBuilt: @escaping () -> Void = {}
    ) -> UpdateCheckCoordinator {
        UpdateCheckCoordinator(
            currentVersion: "1.0.0",
            store: store,
            now: { Self.noon },
            makeChecker: { version in
                onCheckerBuilt()
                return UpdateChecker(currentVersion: version) { _, completion in
                    completion(fetchResult)
                }
            },
            present: present,
            notifyOnMain: { $0() }
        )
    }

    private static let noon = Date(timeIntervalSince1970: 1_700_000_000)
    private static let day: TimeInterval = 24 * 60 * 60
    private static let pageURL = URL(string: "https://github.com/Jetemple/Scrawl/releases/tag/v9.9.9")!
    private static let upToDateData = Data("{\"tag_name\": \"v0.0.1\", \"html_url\": \"\(pageURL.absoluteString)\"}".utf8)
    private static let updateAvailableData = Data("{\"tag_name\": \"v9.9.9\", \"html_url\": \"\(pageURL.absoluteString)\"}".utf8)
}
