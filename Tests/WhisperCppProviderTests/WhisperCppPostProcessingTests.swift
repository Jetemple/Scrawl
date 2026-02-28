import XCTest
@testable import WhisperCppProvider

final class WhisperCppPostProcessingTests: XCTestCase {
    func testBlankAudioMarkerIsTreatedAsNoSpeech() {
        XCTAssertTrue(WhisperCppProvider.isNoSpeechTranscript("[BLANK_AUDIO]"))
        XCTAssertTrue(WhisperCppProvider.isNoSpeechTranscript(" [ no_speech ] "))
        XCTAssertTrue(WhisperCppProvider.isNoSpeechTranscript("[MUSIC]\n[NOISE]"))
    }

    func testNormalTranscriptIsNotTreatedAsNoSpeech() {
        XCTAssertFalse(WhisperCppProvider.isNoSpeechTranscript("Hello this is a test"))
    }
}
