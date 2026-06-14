import CryptoKit
import Foundation

enum ModelDownloadValidator {
    struct HashMismatchError: LocalizedError {
        let expected: String
        let actual: String

        var errorDescription: String? {
            "Downloaded file hash mismatch. Expected \(expected), got \(actual)."
        }
    }

    /// Streams `fileURL` in ~1 MB chunks through SHA-256 and compares
    /// the hex digest against `expected` (case-insensitive).
    /// Throws `HashMismatchError` on mismatch; propagates any `FileHandle` errors.
    static func verifySHA256(of fileURL: URL, expected: String) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024 // 1 MB

        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }

        let digest = hasher.finalize()
        let actual = digest.map { String(format: "%02x", $0) }.joined()

        guard actual.lowercased() == expected.lowercased() else {
            throw HashMismatchError(expected: expected.lowercased(), actual: actual)
        }
    }
}
