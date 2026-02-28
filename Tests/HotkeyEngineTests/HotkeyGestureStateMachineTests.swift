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
}
