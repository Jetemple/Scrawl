@testable import AppUI
import Foundation
import XCTest

final class TempFileSweeperTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Matching files are removed

    func testMatchingAudioFilesAreRemoved() {
        let audioFile = tempDir.appending(path: "scrawl-audio-abc123.wav")
        FileManager.default.createFile(atPath: audioFile.path, contents: Data("audio".utf8))

        TempFileSweeper.sweep(directory: tempDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))
    }

    func testMatchingTranscriptFilesAreRemoved() {
        let transcriptFile = tempDir.appending(path: "scrawl-transcript-xyz.txt")
        FileManager.default.createFile(atPath: transcriptFile.path, contents: Data("text".utf8))

        TempFileSweeper.sweep(directory: tempDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: transcriptFile.path))
    }

    func testMatchingWhisperTempFilesAreRemoved() {
        let whisperFile = tempDir.appending(path: "scrawl-whisper-temp.txt")
        FileManager.default.createFile(atPath: whisperFile.path, contents: Data("data".utf8))

        TempFileSweeper.sweep(directory: tempDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: whisperFile.path))
    }

    func testMatchingDownloadTempFilesAreRemoved() {
        let downloadFile = tempDir.appending(path: "scrawl-download-model.bin")
        FileManager.default.createFile(atPath: downloadFile.path, contents: Data("model".utf8))

        TempFileSweeper.sweep(directory: tempDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: downloadFile.path))
    }

    // MARK: - Non-matching files are preserved

    func testNonMatchingFilesAreNotRemoved() {
        let keepFile = tempDir.appending(path: "other-app-temp.wav")
        FileManager.default.createFile(atPath: keepFile.path, contents: Data("keep".utf8))

        TempFileSweeper.sweep(directory: tempDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: keepFile.path))
    }

    func testFilesWithPrefixInMiddleAreNotRemoved() {
        // "scrawl-audio-" must match at the START of lastPathComponent, not anywhere
        let midFile = tempDir.appending(path: "notscrawl-audio-foo.wav")
        FileManager.default.createFile(atPath: midFile.path, contents: Data("keep".utf8))

        TempFileSweeper.sweep(directory: tempDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: midFile.path))
    }

    func testMixedBatchOnlyRemovesMatching() {
        let audioFile = tempDir.appending(path: "scrawl-audio-1.wav")
        let transcriptFile = tempDir.appending(path: "scrawl-transcript-1.txt")
        let otherFile = tempDir.appending(path: "unrelated.txt")

        for file in [audioFile, transcriptFile, otherFile] {
            FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        }

        TempFileSweeper.sweep(directory: tempDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transcriptFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherFile.path))
    }

    // MARK: - Edge cases

    func testNonexistentDirectoryIsNoOp() {
        let nonexistentDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        // Must not throw or crash
        TempFileSweeper.sweep(directory: nonexistentDir)
    }

    func testSubdirectoriesAreNotRecursedInto() throws {
        // Matching-named subdir should NOT be treated as a file and removed;
        // and files inside it should not be touched.
        let subdir = tempDir.appending(path: "scrawl-audio-subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let nestedFile = subdir.appending(path: "data.wav")
        FileManager.default.createFile(atPath: nestedFile.path, contents: Data("x".utf8))

        TempFileSweeper.sweep(directory: tempDir)

        // The subdir itself must still exist (we only delete regular files)
        XCTAssertTrue(FileManager.default.fileExists(atPath: subdir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedFile.path))
    }

    func testCustomPrefixesAreRespected() {
        let customFile = tempDir.appending(path: "my-custom-prefix-data.tmp")
        let defaultFile = tempDir.appending(path: "scrawl-audio-data.wav")
        FileManager.default.createFile(atPath: customFile.path, contents: Data("x".utf8))
        FileManager.default.createFile(atPath: defaultFile.path, contents: Data("x".utf8))

        TempFileSweeper.sweep(directory: tempDir, prefixes: ["my-custom-prefix-"])

        XCTAssertFalse(FileManager.default.fileExists(atPath: customFile.path))
        // default prefixes not applied because we passed custom ones
        XCTAssertTrue(FileManager.default.fileExists(atPath: defaultFile.path))
    }
}
