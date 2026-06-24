@testable import AppUI
import Foundation
import XCTest

final class WhisperModelFileTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("whisper-model-file-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeFile(_ name: String, bytes: [UInt8]) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    func testAcceptsFileStartingWithGGMLMagic() throws {
        // "ggml" magic followed by arbitrary payload.
        let url = try writeFile("model.bin", bytes: [0x67, 0x67, 0x6D, 0x6C, 0x00, 0x01, 0x02])
        XCTAssertTrue(WhisperModelFile.hasGGMLMagic(at: url))
    }

    func testAcceptsFileThatIsExactlyTheMagic() throws {
        let url = try writeFile("tiny.bin", bytes: [0x67, 0x67, 0x6D, 0x6C])
        XCTAssertTrue(WhisperModelFile.hasGGMLMagic(at: url))
    }

    func testRejectsTextFile() throws {
        let url = try writeFile("notes.txt", bytes: Array("hello world".utf8))
        XCTAssertFalse(WhisperModelFile.hasGGMLMagic(at: url))
    }

    func testRejectsFileShorterThanMagic() throws {
        let url = try writeFile("short.bin", bytes: [0x67, 0x67])
        XCTAssertFalse(WhisperModelFile.hasGGMLMagic(at: url))
    }

    func testRejectsEmptyFile() throws {
        let url = try writeFile("empty.bin", bytes: [])
        XCTAssertFalse(WhisperModelFile.hasGGMLMagic(at: url))
    }

    func testRejectsMissingFile() {
        let url = tempDir.appendingPathComponent("does-not-exist.bin")
        XCTAssertFalse(WhisperModelFile.hasGGMLMagic(at: url))
    }
}
