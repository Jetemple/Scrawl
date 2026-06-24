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

    /// ggml's GGML_FILE_MAGIC (0x67676D6C) is written little-endian, so a real
    /// whisper.cpp model file begins with the bytes 0x6C 0x6D 0x67 0x67 ("lmgg" on
    /// disk). These bytes are taken from the actual ggml-tiny.en.bin header.
    private static let realGGMLHeader: [UInt8] = [0x6C, 0x6D, 0x67, 0x67]

    func testAcceptsFileStartingWithRealGGMLMagic() throws {
        let url = try writeFile("model.bin", bytes: Self.realGGMLHeader + [0x98, 0xCA, 0x00, 0x00])
        XCTAssertTrue(WhisperModelFile.hasGGMLMagic(at: url))
    }

    func testAcceptsFileThatIsExactlyTheMagic() throws {
        let url = try writeFile("tiny.bin", bytes: Self.realGGMLHeader)
        XCTAssertTrue(WhisperModelFile.hasGGMLMagic(at: url))
    }

    func testRejectsReversedMagicByteOrder() throws {
        // Guards the bug where the magic was checked in big-endian order
        // (0x67 0x67 0x6D 0x6C), which rejected every real model.
        let url = try writeFile("reversed.bin", bytes: [0x67, 0x67, 0x6D, 0x6C, 0x00, 0x00])
        XCTAssertFalse(WhisperModelFile.hasGGMLMagic(at: url))
    }

    func testRejectsTextFile() throws {
        let url = try writeFile("notes.txt", bytes: Array("hello world".utf8))
        XCTAssertFalse(WhisperModelFile.hasGGMLMagic(at: url))
    }

    func testRejectsFileShorterThanMagic() throws {
        let url = try writeFile("short.bin", bytes: [0x6C, 0x6D])
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
