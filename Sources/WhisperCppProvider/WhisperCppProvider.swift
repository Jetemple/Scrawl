import Foundation
import TranscriptionCore

public struct WhisperCppConfig: Sendable {
    public var executableURL: URL
    public var modelsDirectoryURL: URL
    public var transcriptionTimeoutSeconds: Int
    public var disableGPU: Bool

    public init(
        executableURL: URL,
        modelsDirectoryURL: URL,
        transcriptionTimeoutSeconds: Int = 120,
        disableGPU: Bool = true
    ) {
        self.executableURL = executableURL
        self.modelsDirectoryURL = modelsDirectoryURL
        self.transcriptionTimeoutSeconds = transcriptionTimeoutSeconds
        self.disableGPU = disableGPU
    }
}

public final class WhisperCppProvider: TranscriptionProvider, @unchecked Sendable {
    public let config: WhisperCppConfig

    public init(config: WhisperCppConfig) {
        self.config = config
    }

    public func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        guard let modelPath = resolveModelPath(modelID: request.modelID) else {
            throw TranscriptionError.modelMissing(request.modelID)
        }

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw TranscriptionError.modelMissing(request.modelID)
        }

        guard FileManager.default.isExecutableFile(atPath: config.executableURL.path) else {
            throw TranscriptionError.providerUnavailable
        }

        let startedAt = Date()
        let outputPrefix = FileManager.default.temporaryDirectory.appendingPathComponent("scrawl-transcript-\(UUID().uuidString)")

        let process = Process()
        process.executableURL = config.executableURL
        var arguments = [
            "-m", modelPath.path,
            "-f", request.audioFileURL.path,
            "-l", request.language,
            "-nt",
            "-np",
            "-otxt",
            "-of", outputPrefix.path
        ]
        if config.disableGPU {
            arguments.append("--no-gpu")
        }
        process.arguments = arguments

        let outputID = UUID().uuidString
        let stdoutURL = FileManager.default.temporaryDirectory.appendingPathComponent("scrawl-whisper-\(outputID).stdout.log")
        let stderrURL = FileManager.default.temporaryDirectory.appendingPathComponent("scrawl-whisper-\(outputID).stderr.log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)

        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        let exitCode = try await runAndWait(
            process: process,
            timeoutSeconds: config.transcriptionTimeoutSeconds
        )

        let stdout = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

        guard exitCode == 0 else {
            throw TranscriptionError.executionFailed(
                "whisper.cpp exited with status \(exitCode): \(stderr.isEmpty ? stdout : stderr)"
            )
        }

        let transcriptFile = outputPrefix.appendingPathExtension("txt")
        let transcriptText: String
        if let text = try? String(contentsOf: transcriptFile, encoding: .utf8) {
            transcriptText = text
        } else {
            transcriptText = stdout
        }

        let cleaned = transcriptText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            throw TranscriptionError.noSpeechDetected
        }

        if Self.isNoSpeechTranscript(cleaned) {
            throw TranscriptionError.noSpeechDetected
        }

        try? FileManager.default.removeItem(at: transcriptFile)

        let latencyMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
        return TranscriptionResult(text: cleaned, latencyMS: latencyMS)
    }

    static func isNoSpeechTranscript(_ transcript: String) -> Bool {
        let lines = transcript
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return true
        }

        return lines.allSatisfy { line in
            let condensed = line
                .uppercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "_", with: "")

            switch condensed {
            case "[BLANKAUDIO]", "(BLANKAUDIO)", "BLANKAUDIO":
                return true
            case "[NOSPEECH]", "(NOSPEECH)", "NOSPEECH":
                return true
            case "[SILENCE]", "(SILENCE)", "SILENCE":
                return true
            case "[NOISE]", "(NOISE)", "NOISE":
                return true
            case "[MUSIC]", "(MUSIC)", "MUSIC":
                return true
            default:
                return false
            }
        }
    }

    private func resolveModelPath(modelID: String) -> URL? {
        let fileManager = FileManager.default

        let directName: String
        if modelID.hasSuffix(".bin") {
            directName = modelID
        } else {
            directName = "\(modelID).bin"
        }

        var candidates: [String] = [directName]
        if !directName.hasPrefix("ggml-") {
            candidates.append("ggml-\(directName)")
        }
        if modelID.hasSuffix(".en") {
            let base = String(modelID.dropLast(3))
            candidates.append("\(base).bin")
            candidates.append("ggml-\(base).bin")
        }

        for name in candidates {
            let path = config.modelsDirectoryURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: path.path) {
                return path
            }
        }
        return nil
    }

    private func runAndWait(
        process: Process,
        timeoutSeconds: Int
    ) async throws -> Int32 {
        try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { process in
                        continuation.resume(returning: process.terminationStatus)
                    }

                    do {
                        try process.run()
                    } catch {
                        continuation.resume(
                            throwing: TranscriptionError.executionFailed(
                                "Failed to launch whisper.cpp: \(error.localizedDescription)"
                            )
                        )
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(timeoutSeconds, 1)) * 1_000_000_000)
                if process.isRunning {
                    process.terminate()
                }
                throw TranscriptionError.executionFailed("whisper.cpp timed out after \(timeoutSeconds)s")
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw TranscriptionError.executionFailed("whisper.cpp failed without output")
            }
            return result
        }
    }
}
