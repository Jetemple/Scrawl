import Foundation

/// Lightweight sniff test for whisper.cpp model files. Every model whisper.cpp
/// loads — and every model Scrawl downloads — is a ggml container whose first four
/// bytes are the ASCII magic "ggml". Checking it lets us reject an obviously-wrong
/// pick (a text file, an archive, the wrong kind of model) at import time, instead
/// of failing later with a cryptic whisper-cli error during transcription.
enum WhisperModelFile {
    /// ggml's `GGML_FILE_MAGIC` is the 32-bit constant 0x67676D6C, written to disk
    /// little-endian — so the first four bytes of a real whisper.cpp model file are
    /// 0x6C 0x6D 0x67 0x67. (The hex constant reads "ggml" left-to-right; on disk the
    /// little-endian byte order reads "lmgg".) Checking the constant's byte order
    /// instead of the on-disk order rejects every real model — verified against the
    /// ggml-tiny.en.bin header.
    static let ggmlMagic: [UInt8] = [0x6C, 0x6D, 0x67, 0x67]

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
