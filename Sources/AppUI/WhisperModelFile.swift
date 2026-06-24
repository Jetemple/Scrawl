import Foundation

/// Lightweight sniff test for whisper.cpp model files. Every model whisper.cpp
/// loads — and every model Scrawl downloads — is a ggml container whose first four
/// bytes are the ASCII magic "ggml". Checking it lets us reject an obviously-wrong
/// pick (a text file, an archive, the wrong kind of model) at import time, instead
/// of failing later with a cryptic whisper-cli error during transcription.
enum WhisperModelFile {
    static let ggmlMagic: [UInt8] = [0x67, 0x67, 0x6D, 0x6C] // "ggml"

    static func hasGGMLMagic(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }

        let data: Data?
        do {
            data = try handle.read(upToCount: ggmlMagic.count)
        } catch {
            return false
        }

        guard let bytes = data, bytes.count == ggmlMagic.count else {
            return false
        }
        return Array(bytes) == ggmlMagic
    }
}
