import Foundation
import TranscriptionCore

public struct WhisperCppConfig: Sendable {
    public var executableURL: URL
    public var serverExecutableURL: URL
    public var modelsDirectoryURL: URL
    public var transcriptionTimeoutSeconds: Int
    public var disableGPU: Bool
    public var threads: Int?
    public var idleOffloadSeconds: TimeInterval?

    public init(
        executableURL: URL,
        serverExecutableURL: URL? = nil,
        modelsDirectoryURL: URL,
        transcriptionTimeoutSeconds: Int = 120,
        disableGPU: Bool = false,
        threads: Int? = nil,
        idleOffloadSeconds: TimeInterval? = 300
    ) {
        self.executableURL = executableURL
        self.serverExecutableURL = serverExecutableURL ?? WhisperCppProvider.serverExecutableURL(forCLI: executableURL)
        self.modelsDirectoryURL = modelsDirectoryURL
        self.transcriptionTimeoutSeconds = transcriptionTimeoutSeconds
        self.disableGPU = disableGPU
        self.threads = threads
        self.idleOffloadSeconds = idleOffloadSeconds
    }
}

public final class WhisperCppProvider: ModelRetainingTranscriptionProvider, @unchecked Sendable {
    public let config: WhisperCppConfig
    private let fallbackLock = NSLock()
    private var shouldForceCPUFallback = false
    private let warmServer: WarmWhisperServer

    public init(config: WhisperCppConfig) {
        self.config = config
        self.warmServer = WarmWhisperServer(config: config)
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
        let forceNoGPU = config.disableGPU || isCPUFallbackForced()

        if await warmServer.isEnabled {
            do {
                request.progressHandler?(
                    TranscriptionProgressEvent(phase: .loadingModel, modelID: request.modelID, elapsedMS: 0)
                )
                return try await warmServer.transcribe(
                    request,
                    modelPath: modelPath,
                    forceNoGPU: forceNoGPU,
                    startedAt: startedAt
                )
            } catch {
                await warmServer.shutdown()
            }
        }

        do {
            return try await transcribeOnce(
                request: request,
                modelPath: modelPath,
                startedAt: startedAt,
                forceNoGPU: forceNoGPU
            )
        } catch let transcriptionError as TranscriptionError {
            guard shouldRetryWithCPU(after: transcriptionError, forceNoGPU: forceNoGPU) else {
                throw transcriptionError
            }

            // Some systems advertise Metal support but still fail during GPU execution.
            // Persisting a process-local CPU fallback avoids repeated failed launches.
            setCPUFallbackForced(true)
            request.progressHandler?(
                TranscriptionProgressEvent(
                    phase: .retryingOnCPU,
                    modelID: request.modelID,
                    elapsedMS: Self.elapsedMS(since: startedAt)
                )
            )
            return try await transcribeOnce(
                request: request,
                modelPath: modelPath,
                startedAt: startedAt,
                forceNoGPU: true
            )
        }
    }

    public func warmUp(modelID: String, language: String) async {
        guard let modelPath = resolveModelPath(modelID: modelID) else { return }
        await warmServer.warmUp(
            modelID: modelID,
            modelPath: modelPath,
            language: language,
            forceNoGPU: config.disableGPU || isCPUFallbackForced()
        )
    }

    public func setIdleOffloadSeconds(_ seconds: TimeInterval?) async {
        await warmServer.setIdleOffloadSeconds(seconds)
    }

    public func shutdown() async {
        await warmServer.shutdown()
    }

    private func transcribeOnce(
        request: TranscriptionRequest,
        modelPath: URL,
        startedAt: Date,
        forceNoGPU: Bool
    ) async throws -> TranscriptionResult {
        let outputPrefix = FileManager.default.temporaryDirectory.appendingPathComponent("scrawl-transcript-\(UUID().uuidString)")
        let transcriptFile = outputPrefix.appendingPathExtension("txt")
        let progressReporter = TranscriptionProgressReporter(
            modelID: request.modelID,
            startedAt: startedAt,
            handler: request.progressHandler
        )
        progressReporter.emit(.loadingModel)

        let arguments = makeCLIArguments(
            request: request,
            modelPath: modelPath,
            outputPrefix: outputPrefix,
            forceNoGPU: forceNoGPU
        )

        let process = Process()
        process.executableURL = config.executableURL
        process.arguments = arguments

        let outputID = UUID().uuidString
        let stdoutURL = FileManager.default.temporaryDirectory.appendingPathComponent("scrawl-whisper-\(outputID).stdout.log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrPipe = Pipe()
        let stderrCapture = ProcessOutputCapture()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            stderrCapture.append(data)
            progressReporter.observeCLIOutput(stderrCapture.string())
        }

        process.standardOutput = stdoutHandle
        process.standardError = stderrPipe

        defer {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            try? stdoutHandle.close()
            try? stderrPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForWriting.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            // Clean up the transcript file on every exit path — including the no-speech / empty /
            // non-zero-exit throws below — so blank-audio recordings don't leak temp files.
            try? FileManager.default.removeItem(at: transcriptFile)
        }

        let exitCode = try await runAndWait(
            process: process,
            timeoutSeconds: config.transcriptionTimeoutSeconds
        )

        let stdout = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let stderr = stderrCapture.string()

        guard exitCode == 0 else {
            throw TranscriptionError.executionFailed(
                "whisper.cpp exited with status \(exitCode): \(stderr.isEmpty ? stdout : stderr)"
            )
        }

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

        let latencyMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
        return TranscriptionResult(text: cleaned, latencyMS: latencyMS)
    }

    static func progressPhase(forCLIOutput output: String) -> TranscriptionProgressPhase? {
        let lowercased = output.lowercased()
        guard lowercased.contains(": processing '") || lowercased.contains(": processing \"") else {
            return nil
        }
        return .transcribing
    }

    private static func elapsedMS(since startedAt: Date) -> Int {
        Int(Date().timeIntervalSince(startedAt) * 1_000)
    }

    private func shouldRetryWithCPU(after error: TranscriptionError, forceNoGPU: Bool) -> Bool {
        Self.isRetryableWithCPU(error: error, forceNoGPU: forceNoGPU)
    }

    /// A GPU run should only fall back to CPU when the GPU genuinely failed to execute. A timeout
    /// means the run was merely too slow — retrying the same long input on CPU is typically slower
    /// and can time out again, doubling the user's stall — so timeouts (and non-execution errors)
    /// are not retryable.
    static func isRetryableWithCPU(error: TranscriptionError, forceNoGPU: Bool) -> Bool {
        guard !forceNoGPU else {
            return false
        }
        switch error {
        case .executionFailed:
            return true
        case .timedOut, .providerUnavailable, .modelMissing, .noSpeechDetected:
            return false
        }
    }

    private func isCPUFallbackForced() -> Bool {
        fallbackLock.lock()
        defer { fallbackLock.unlock() }
        return shouldForceCPUFallback
    }

    private func setCPUFallbackForced(_ enabled: Bool) {
        fallbackLock.lock()
        shouldForceCPUFallback = enabled
        fallbackLock.unlock()
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
            Self.isNoSpeechLine(line)
        }
    }

    private static func isNoSpeechLine(_ line: String) -> Bool {
        let nonDecorativeScalars = line.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
        }

        if nonDecorativeScalars.isEmpty {
            return true
        }

        let wordOnly = nonDecorativeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .uppercased()

        if wordOnly == "YOU" {
            return true
        }

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
        case "[NOISE]", "(NOISE)":
            return true
        case "[MUSIC]", "(MUSIC)":
            return true
        default:
            return false
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

    func makeCLIArguments(
        request: TranscriptionRequest,
        modelPath: URL,
        outputPrefix: URL,
        forceNoGPU: Bool = false
    ) -> [String] {
        var arguments = [
            "-m", modelPath.path,
            "-f", request.audioFileURL.path,
            "-l", request.language,
            "-nt",
            "-np",
            "-otxt",
            "-of", outputPrefix.path
        ]

        if let threads = config.threads, threads > 0 {
            arguments.append(contentsOf: ["-t", String(threads)])
        }

        if config.disableGPU || forceNoGPU {
            arguments.append("--no-gpu")
        }

        if let prompt = request.promptContext?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            arguments.append(contentsOf: ["--prompt", prompt])
        }

        return arguments
    }

    func makeServerArguments(
        modelPath: URL,
        language: String,
        port: Int,
        forceNoGPU: Bool = false
    ) -> [String] {
        var arguments = [
            "-m", modelPath.path,
            "-l", language,
            "-nt",
            "-bo", "5",
            "-bs", "5",
            "--host", "127.0.0.1",
            "--port", String(port)
        ]
        if let threads = config.threads, threads > 0 {
            arguments.append(contentsOf: ["-t", String(threads)])
        }
        if config.disableGPU || forceNoGPU {
            arguments.append("--no-gpu")
        }
        return arguments
    }

    static func serverExecutableURL(forCLI executableURL: URL) -> URL {
        executableURL.deletingLastPathComponent().appendingPathComponent("whisper-server")
    }

    static func decodeServerTranscript(_ data: Data) throws -> String {
        struct Response: Decodable { let text: String }
        let cleaned = try JSONDecoder().decode(Response.self, from: data).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !isNoSpeechTranscript(cleaned) else {
            throw TranscriptionError.noSpeechDetected
        }
        return cleaned
    }

    private func runAndWait(
        process: Process,
        timeoutSeconds: Int
    ) async throws -> Int32 {
        try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    do {
                        process.terminationHandler = { process in
                            continuation.resume(returning: process.terminationStatus)
                        }
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
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
                throw TranscriptionError.timedOut(seconds: timeoutSeconds)
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw TranscriptionError.executionFailed("whisper.cpp failed without output")
            }
            return result
        }
    }
}

private final class ProcessOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private final class TranscriptionProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private let modelID: String
    private let startedAt: Date
    private let handler: (@Sendable (TranscriptionProgressEvent) -> Void)?
    private var didEmitTranscribing = false

    init(
        modelID: String,
        startedAt: Date,
        handler: (@Sendable (TranscriptionProgressEvent) -> Void)?
    ) {
        self.modelID = modelID
        self.startedAt = startedAt
        self.handler = handler
    }

    func emit(_ phase: TranscriptionProgressPhase) {
        handler?(
            TranscriptionProgressEvent(
                phase: phase,
                modelID: modelID,
                elapsedMS: Int(Date().timeIntervalSince(startedAt) * 1_000)
            )
        )
    }

    func observeCLIOutput(_ output: String) {
        guard WhisperCppProvider.progressPhase(forCLIOutput: output) == .transcribing else {
            return
        }

        lock.lock()
        guard !didEmitTranscribing else {
            lock.unlock()
            return
        }
        didEmitTranscribing = true
        lock.unlock()

        emit(.transcribing)
    }
}
