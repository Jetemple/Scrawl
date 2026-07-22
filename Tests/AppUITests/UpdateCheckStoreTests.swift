@testable import AppUI
import XCTest

final class UpdateCheckStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "scrawl.update.tests.\(UUID().uuidString)")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().description)
        defaults = nil
        super.tearDown()
    }

    func testStartsEmpty() {
        let store = UpdateCheckStore(defaults: defaults)

        XCTAssertNil(store.lastCheckDate)
        XCTAssertNil(store.availableRelease)
    }

    func testRecordsAnAvailableReleaseAcrossInstances() {
        let release = UpdateRelease(version: "0.0.13", pageURL: Self.pageURL)
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)

        UpdateCheckStore(defaults: defaults).record(checkedAt: checkedAt, availableRelease: release)

        let reloaded = UpdateCheckStore(defaults: defaults)
        XCTAssertEqual(reloaded.lastCheckDate, checkedAt)
        XCTAssertEqual(reloaded.availableRelease, release)
    }

    func testRecordingUpToDateClearsAPreviouslyCachedRelease() {
        let store = UpdateCheckStore(defaults: defaults)
        store.record(checkedAt: Date(timeIntervalSince1970: 1), availableRelease: UpdateRelease(version: "0.0.13", pageURL: Self.pageURL))

        store.record(checkedAt: Date(timeIntervalSince1970: 2), availableRelease: nil)

        XCTAssertNil(UpdateCheckStore(defaults: defaults).availableRelease)
        XCTAssertEqual(UpdateCheckStore(defaults: defaults).lastCheckDate, Date(timeIntervalSince1970: 2))
    }

    private static let pageURL = URL(string: "https://github.com/Jetemple/Scrawl/releases/tag/v0.0.13")!
}
