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
