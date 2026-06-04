@testable import AppUI
import XCTest

final class SingleInstanceLockTests: XCTestCase {
    func testSecondLockCannotAcquireSameFile() throws {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrawl-test-\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: lockURL) }

        let first = try SingleInstanceLock(lockFileURL: lockURL)
        XCTAssertTrue(try first.tryAcquire())

        let second = try SingleInstanceLock(lockFileURL: lockURL)
        XCTAssertFalse(try second.tryAcquire())
    }

    func testLockCanBeAcquiredAfterRelease() throws {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrawl-test-\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: lockURL) }

        let first = try SingleInstanceLock(lockFileURL: lockURL)
        XCTAssertTrue(try first.tryAcquire())
        first.release()

        let second = try SingleInstanceLock(lockFileURL: lockURL)
        XCTAssertTrue(try second.tryAcquire())
    }
}
