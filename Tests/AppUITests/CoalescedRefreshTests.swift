@testable import AppUI
import XCTest

final class CoalescedRefreshTests: XCTestCase {
    func testRequestOutsideBatchPerformsImmediately() {
        var performCount = 0
        let refresh = CoalescedRefresh { performCount += 1 }

        refresh.request()

        XCTAssertEqual(performCount, 1)
    }

    func testMultipleRequestsInsideBatchPerformOnceAtEnd() {
        var performCount = 0
        let refresh = CoalescedRefresh { performCount += 1 }

        refresh.batch {
            refresh.request()
            refresh.request()
            refresh.request()
            XCTAssertEqual(performCount, 0, "refresh must be deferred until the batch ends")
        }

        XCTAssertEqual(performCount, 1)
    }

    func testBatchWithoutRequestsDoesNotPerform() {
        var performCount = 0
        let refresh = CoalescedRefresh { performCount += 1 }

        refresh.batch {}

        XCTAssertEqual(performCount, 0)
    }

    func testNestedBatchesFoldIntoOutermost() {
        var performCount = 0
        let refresh = CoalescedRefresh { performCount += 1 }

        refresh.batch {
            refresh.request()
            refresh.batch {
                refresh.request()
            }
            XCTAssertEqual(performCount, 0, "inner batch end must not flush while outer batch is open")
        }

        XCTAssertEqual(performCount, 1)
    }

    func testRequestsAfterBatchPerformImmediatelyAgain() {
        var performCount = 0
        let refresh = CoalescedRefresh { performCount += 1 }

        refresh.batch { refresh.request() }
        refresh.request()

        XCTAssertEqual(performCount, 2)
    }
}
