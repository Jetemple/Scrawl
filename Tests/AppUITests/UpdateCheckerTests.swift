@testable import AppUI
import XCTest

final class UpdateCheckerTests: XCTestCase {
    func testRequestsLatestReleaseEndpointWithGitHubAcceptHeader() {
        var capturedRequest: URLRequest?
        let checker = UpdateChecker(currentVersion: "0.0.12") { request, completion in
            capturedRequest = request
            completion(.success(Self.releaseData(tag: "v0.0.12")))
        }

        checker.check { _ in }

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.github.com/repos/Jetemple/Scrawl/releases/latest")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
    }

    func testReportsUpdateWhenLatestTagIsNewer() {
        let outcome = check(currentVersion: "0.0.12", latestTag: "v0.0.13")

        XCTAssertEqual(
            outcome,
            .updateAvailable(UpdateRelease(version: "0.0.13", pageURL: Self.releasePageURL))
        )
    }

    func testReportsUpToDateWhenLatestTagMatchesCurrentVersion() {
        XCTAssertEqual(check(currentVersion: "0.0.12", latestTag: "v0.0.12"), .upToDate(currentVersion: "0.0.12"))
    }

    func testReportsUpToDateWhenLatestTagIsOlder() {
        XCTAssertEqual(check(currentVersion: "0.0.12", latestTag: "v0.0.11"), .upToDate(currentVersion: "0.0.12"))
    }

    func testComparesVersionComponentsNumericallyNotLexically() {
        XCTAssertEqual(
            check(currentVersion: "0.0.9", latestTag: "v0.0.10"),
            .updateAvailable(UpdateRelease(version: "0.0.10", pageURL: Self.releasePageURL))
        )
        XCTAssertEqual(check(currentVersion: "0.0.10", latestTag: "v0.0.9"), .upToDate(currentVersion: "0.0.10"))
    }

    func testTreatsMissingComponentsAsZero() {
        XCTAssertEqual(
            check(currentVersion: "1.0", latestTag: "v1.0.1"),
            .updateAvailable(UpdateRelease(version: "1.0.1", pageURL: Self.releasePageURL))
        )
        XCTAssertEqual(check(currentVersion: "1.0.0", latestTag: "v1.0"), .upToDate(currentVersion: "1.0.0"))
    }

    func testAcceptsTagsWithoutVersionPrefix() {
        XCTAssertEqual(
            check(currentVersion: "0.0.12", latestTag: "0.0.13"),
            .updateAvailable(UpdateRelease(version: "0.0.13", pageURL: Self.releasePageURL))
        )
    }

    func testFailsOnMalformedPayload() {
        let checker = UpdateChecker(currentVersion: "0.0.12") { _, completion in
            completion(.success(Data("not json".utf8)))
        }
        var received: Result<UpdateCheckOutcome, Error>?

        checker.check { received = $0 }

        guard case let .failure(error) = received else {
            return XCTFail("Expected a failure, got \(String(describing: received))")
        }
        XCTAssertEqual(error as? UpdateChecker.CheckError, .malformedResponse)
    }

    func testPropagatesFetchError() {
        struct FetchFailure: Error {}
        let checker = UpdateChecker(currentVersion: "0.0.12") { _, completion in
            completion(.failure(FetchFailure()))
        }
        var received: Result<UpdateCheckOutcome, Error>?

        checker.check { received = $0 }

        guard case let .failure(error) = received else {
            return XCTFail("Expected a failure, got \(String(describing: received))")
        }
        XCTAssertTrue(error is FetchFailure)
    }

    func testChecksWhenNeverCheckedBefore() {
        XCTAssertTrue(UpdateChecker.shouldCheck(lastCheckDate: nil, now: Self.noon))
    }

    func testChecksAgainOnceADayHasPassed() {
        let yesterday = Self.noon.addingTimeInterval(-24 * 60 * 60)
        XCTAssertTrue(UpdateChecker.shouldCheck(lastCheckDate: yesterday, now: Self.noon))
    }

    func testSkipsCheckWithinTheDailyWindow() {
        let anHourAgo = Self.noon.addingTimeInterval(-60 * 60)
        XCTAssertFalse(UpdateChecker.shouldCheck(lastCheckDate: anHourAgo, now: Self.noon))
    }

    func testAvailableReleaseIsNilWhenUpToDate() {
        XCTAssertNil(UpdateCheckOutcome.upToDate(currentVersion: "0.0.12").availableRelease)
    }

    func testAvailableReleaseCarriesTheReleaseWhenAnUpdateExists() {
        let release = UpdateRelease(version: "0.0.13", pageURL: Self.releasePageURL)
        XCTAssertEqual(UpdateCheckOutcome.updateAvailable(release).availableRelease, release)
    }

    private static let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private static let releasePageURL = URL(string: "https://github.com/Jetemple/Scrawl/releases/tag/latest")!

    private static func releaseData(tag: String) -> Data {
        Data("{\"tag_name\": \"\(tag)\", \"html_url\": \"\(releasePageURL.absoluteString)\"}".utf8)
    }

    private func check(currentVersion: String, latestTag: String) -> UpdateCheckOutcome? {
        let checker = UpdateChecker(currentVersion: currentVersion) { _, completion in
            completion(.success(Self.releaseData(tag: latestTag)))
        }
        var received: Result<UpdateCheckOutcome, Error>?
        checker.check { received = $0 }
        guard case let .success(outcome) = received else {
            XCTFail("Expected success, got \(String(describing: received))")
            return nil
        }
        return outcome
    }
}
