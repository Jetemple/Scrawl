@testable import AppUI
import XCTest

final class PreparationRefreshGateTests: XCTestCase {
    func testFirstEventAlwaysRefreshes() {
        var gate = PreparationRefreshGate()
        XCTAssertTrue(gate.shouldRefresh(rowText: "Preparing"))
    }

    func testRepeatedIdenticalRowTextDoesNotRefresh() {
        var gate = PreparationRefreshGate()
        XCTAssertTrue(gate.shouldRefresh(rowText: "Preparing"))
        // The optimize phase fires ~18 progress callbacks/sec that all collapse to the same
        // row text; only the first should refresh the preferences window.
        for _ in 0..<20 {
            XCTAssertFalse(gate.shouldRefresh(rowText: "Preparing"))
        }
    }

    func testChangedRowTextRefreshesAgain() {
        var gate = PreparationRefreshGate()
        XCTAssertTrue(gate.shouldRefresh(rowText: "Downloading 1%"))
        XCTAssertFalse(gate.shouldRefresh(rowText: "Downloading 1%"))
        XCTAssertTrue(gate.shouldRefresh(rowText: "Downloading 2%"))
        XCTAssertTrue(gate.shouldRefresh(rowText: "Preparing"))
    }

    func testResetMakesTheNextEventRefreshEvenIfUnchanged() {
        var gate = PreparationRefreshGate()
        XCTAssertTrue(gate.shouldRefresh(rowText: "Preparing"))
        XCTAssertFalse(gate.shouldRefresh(rowText: "Preparing"))
        gate.reset()
        XCTAssertTrue(gate.shouldRefresh(rowText: "Preparing"), "a new preparation session must refresh")
    }

    func testNilRowTextIsTreatedLikeAnyValue() {
        var gate = PreparationRefreshGate()
        XCTAssertTrue(gate.shouldRefresh(rowText: nil))
        XCTAssertFalse(gate.shouldRefresh(rowText: nil))
        XCTAssertTrue(gate.shouldRefresh(rowText: "Preparing"))
    }
}
