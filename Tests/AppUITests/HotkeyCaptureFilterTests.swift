@testable import AppUI
import XCTest

final class HotkeyCaptureFilterTests: XCTestCase {
    // MARK: - Accepted keys

    func testFunctionKeyF5IsAccepted() throws {
        // F5 keyCode = 96; characters = NSF5FunctionKey scalar (0xF708)
        let f5Chars = try String(XCTUnwrap(UnicodeScalar(0xF708)))
        XCTAssertTrue(HotkeyCaptureFilter.isAccepted(keyCode: 96, characters: f5Chars))
    }

    func testFunctionKeyF1IsAccepted() throws {
        let f1Chars = try String(XCTUnwrap(UnicodeScalar(0xF704)))
        XCTAssertTrue(HotkeyCaptureFilter.isAccepted(keyCode: 122, characters: f1Chars))
    }

    func testFunctionKeyF12IsAccepted() throws {
        let f12Chars = try String(XCTUnwrap(UnicodeScalar(0xF70F)))
        XCTAssertTrue(HotkeyCaptureFilter.isAccepted(keyCode: 111, characters: f12Chars))
    }

    func testNilCharactersIsAccepted() {
        // Some special keys produce no characters at all
        XCTAssertTrue(HotkeyCaptureFilter.isAccepted(keyCode: 63, characters: nil))
    }

    func testEmptyCharactersIsAccepted() {
        XCTAssertTrue(HotkeyCaptureFilter.isAccepted(keyCode: 63, characters: ""))
    }

    // MARK: - Rejected keys

    func testLetterRIsRejected() {
        XCTAssertFalse(HotkeyCaptureFilter.isAccepted(keyCode: 15, characters: "r"))
    }

    func testUppercaseRIsRejected() {
        XCTAssertFalse(HotkeyCaptureFilter.isAccepted(keyCode: 15, characters: "R"))
    }

    func testSpaceIsRejected() {
        XCTAssertFalse(HotkeyCaptureFilter.isAccepted(keyCode: 49, characters: " "))
    }

    func testPeriodIsRejected() {
        XCTAssertFalse(HotkeyCaptureFilter.isAccepted(keyCode: 47, characters: "."))
    }

    func testCommaIsRejected() {
        XCTAssertFalse(HotkeyCaptureFilter.isAccepted(keyCode: 43, characters: ","))
    }

    func testDigitIsRejected() {
        XCTAssertFalse(HotkeyCaptureFilter.isAccepted(keyCode: 29, characters: "0"))
    }

    // MARK: - Arrow keys (rejected per policy)

    func testUpArrowIsRejected() throws {
        // NSUpArrowFunctionKey = 0xF700
        let upArrowChars = try String(XCTUnwrap(UnicodeScalar(0xF700)))
        XCTAssertFalse(HotkeyCaptureFilter.isAccepted(keyCode: 126, characters: upArrowChars))
    }

    func testDownArrowIsRejected() throws {
        let downArrowChars = try String(XCTUnwrap(UnicodeScalar(0xF701)))
        XCTAssertFalse(HotkeyCaptureFilter.isAccepted(keyCode: 125, characters: downArrowChars))
    }

    func testLeftArrowIsRejected() throws {
        let leftArrowChars = try String(XCTUnwrap(UnicodeScalar(0xF702)))
        XCTAssertFalse(HotkeyCaptureFilter.isAccepted(keyCode: 123, characters: leftArrowChars))
    }

    func testRightArrowIsRejected() throws {
        let rightArrowChars = try String(XCTUnwrap(UnicodeScalar(0xF703)))
        XCTAssertFalse(HotkeyCaptureFilter.isAccepted(keyCode: 124, characters: rightArrowChars))
    }

    // MARK: - Edge cases

    func testFunctionKeyJustAboveArrowRangeIsAccepted() throws {
        // 0xF704 = NSF1FunctionKey — just above arrow range, should be accepted
        let f1Chars = try String(XCTUnwrap(UnicodeScalar(0xF704)))
        XCTAssertTrue(HotkeyCaptureFilter.isAccepted(keyCode: 122, characters: f1Chars))
    }

    func testDeleteFunctionKeyIsAccepted() throws {
        // NSDeleteFunctionKey = 0xF728
        let deleteChars = try String(XCTUnwrap(UnicodeScalar(0xF728)))
        XCTAssertTrue(HotkeyCaptureFilter.isAccepted(keyCode: 117, characters: deleteChars))
    }
}
