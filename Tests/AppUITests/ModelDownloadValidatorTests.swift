@testable import AppUI
import CryptoKit
import XCTest

final class ModelDownloadValidatorTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("validator-test-\(UUID().uuidString).bin")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    private func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func testVerifyAcceptsMatchingHash() throws {
        let content = Data("hello world".utf8)
        let expected = sha256Hex(of: content)
        try content.write(to: tempURL)
        XCTAssertNoThrow(try ModelDownloadValidator.verifySHA256(of: tempURL, expected: expected))
    }

    func testVerifyThrowsOnMismatch() throws {
        let content = Data("hello world".utf8)
        try content.write(to: tempURL)
        XCTAssertThrowsError(
            try ModelDownloadValidator.verifySHA256(of: tempURL, expected: "deadbeef")
        ) { error in
            XCTAssertTrue(error is ModelDownloadValidator.HashMismatchError)
        }
    }

    func testVerifyHandlesLargeFileInChunks() throws {
        // 3 MB — forces multiple 1 MB chunk reads
        let content = Data(repeating: 0xAB, count: 3 * 1024 * 1024)
        let expected = sha256Hex(of: content)
        try content.write(to: tempURL)
        XCTAssertNoThrow(try ModelDownloadValidator.verifySHA256(of: tempURL, expected: expected))
    }

    func testVerifyIsCaseInsensitive() throws {
        let content = Data("abc".utf8)
        let lowerHex = sha256Hex(of: content)
        let upperHex = lowerHex.uppercased()
        try content.write(to: tempURL)
        XCTAssertNoThrow(try ModelDownloadValidator.verifySHA256(of: tempURL, expected: upperHex))
    }
}
