import Foundation
import HotkeyEngine
import XCTest

final class HotkeyGestureStateMachineTests: XCTestCase {
    func testHoldStartsAndStopsRecording() {
        let machine = HotkeyGestureStateMachine(
            config: HotkeyGestureConfig(holdThreshold: 0.18, doubleTapGap: 0.30)
        )
        let t0 = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertEqual(machine.keyDown(at: t0), [])
        XCTAssertEqual(machine.tick(at: t0.addingTimeInterval(0.19)), [.startHoldRecording])
        XCTAssertEqual(machine.keyUp(at: t0.addingTimeInterval(0.21)), [.stopHoldRecording])
    }

    func testDoubleTapStartsToggleRecording() {
        let machine = HotkeyGestureStateMachine(
            config: HotkeyGestureConfig(holdThreshold: 0.18, doubleTapGap: 0.30)
        )
        let t0 = Date(timeIntervalSinceReferenceDate: 200)

        XCTAssertEqual(machine.keyDown(at: t0), [])
        XCTAssertEqual(machine.keyUp(at: t0.addingTimeInterval(0.08)), [])
        XCTAssertEqual(machine.keyDown(at: t0.addingTimeInterval(0.16)), [])
        XCTAssertEqual(machine.keyUp(at: t0.addingTimeInterval(0.22)), [.startToggleRecording])
    }

    func testSingleTapStopsToggleRecording() {
        let machine = HotkeyGestureStateMachine(
            config: HotkeyGestureConfig(holdThreshold: 0.18, doubleTapGap: 0.30)
        )
        let t0 = Date(timeIntervalSinceReferenceDate: 300)

        XCTAssertEqual(machine.keyDown(at: t0), [])
        XCTAssertEqual(machine.keyUp(at: t0.addingTimeInterval(0.08)), [])
        XCTAssertEqual(machine.keyDown(at: t0.addingTimeInterval(0.16)), [])
        XCTAssertEqual(machine.keyUp(at: t0.addingTimeInterval(0.22)), [.startToggleRecording])

        XCTAssertEqual(machine.keyDown(at: t0.addingTimeInterval(0.50)), [])
        XCTAssertEqual(machine.keyUp(at: t0.addingTimeInterval(0.56)), [.stopToggleRecording])
    }

    func testKeyUpAtThresholdWithoutTickDoesNotStartAndStop() {
        let machine = HotkeyGestureStateMachine(
            config: HotkeyGestureConfig(holdThreshold: 0.18, doubleTapGap: 0.30)
        )
        let t0 = Date(timeIntervalSinceReferenceDate: 500)

        XCTAssertEqual(machine.keyDown(at: t0), [])
        // Release after hold threshold but before tick fires — should not emit start+stop together
        XCTAssertEqual(machine.keyUp(at: t0.addingTimeInterval(0.20)), [])
        // State should have gone to waitingForSecondTap, then expired
        XCTAssertEqual(machine.tick(at: t0.addingTimeInterval(0.60)), [])
    }

    func testSingleTapExpiresWithoutSideEffects() {
        let machine = HotkeyGestureStateMachine(
            config: HotkeyGestureConfig(holdThreshold: 0.18, doubleTapGap: 0.30)
        )
        let t0 = Date(timeIntervalSinceReferenceDate: 400)

        XCTAssertEqual(machine.keyDown(at: t0), [])
        XCTAssertEqual(machine.keyUp(at: t0.addingTimeInterval(0.05)), [])
        XCTAssertEqual(machine.tick(at: t0.addingTimeInterval(0.50)), [])
        XCTAssertEqual(machine.keyUp(at: t0.addingTimeInterval(0.51)), [])
    }

    func testNextDeadlineTracksHoldThreshold() throws {
        let machine = HotkeyGestureStateMachine(
            config: HotkeyGestureConfig(holdThreshold: 0.18, doubleTapGap: 0.30)
        )
        let t0 = Date(timeIntervalSinceReferenceDate: 600)

        XCTAssertEqual(machine.keyDown(at: t0), [])
        let deadline = try XCTUnwrap(machine.nextActionDeadline(at: t0))
        XCTAssertEqual(deadline.timeIntervalSinceReferenceDate, t0.addingTimeInterval(0.18).timeIntervalSinceReferenceDate, accuracy: 0.000_001)
        XCTAssertEqual(machine.tick(at: deadline.addingTimeInterval(0.001)), [.startHoldRecording])
        XCTAssertNil(machine.nextActionDeadline(at: deadline.addingTimeInterval(0.001)))
    }

    func testNextDeadlineTracksSecondTapExpiry() throws {
        let machine = HotkeyGestureStateMachine(
            config: HotkeyGestureConfig(holdThreshold: 0.18, doubleTapGap: 0.30)
        )
        let t0 = Date(timeIntervalSinceReferenceDate: 700)

        XCTAssertEqual(machine.keyDown(at: t0), [])
        XCTAssertEqual(machine.keyUp(at: t0.addingTimeInterval(0.05)), [])
        let deadline = try XCTUnwrap(machine.nextActionDeadline(at: t0.addingTimeInterval(0.05)))
        XCTAssertEqual(deadline.timeIntervalSinceReferenceDate, t0.addingTimeInterval(0.35).timeIntervalSinceReferenceDate, accuracy: 0.000_001)
        XCTAssertEqual(machine.tick(at: t0.addingTimeInterval(0.36)), [])
        XCTAssertNil(machine.nextActionDeadline(at: t0.addingTimeInterval(0.36)))
    }
}
