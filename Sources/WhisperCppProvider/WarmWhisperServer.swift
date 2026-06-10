import Foundation
import TranscriptionCore

actor WarmWhisperServer {
    struct SupervisedLaunch {
        let executableURL: URL
        let arguments: [String]
    }

    private struct ServerKey: Equatable {
        let modelID: String
        let language: String
        let forceNoGPU: Bool
    }

    private let config: WhisperCppConfig
    private var process: Process?
    private var serverKey: ServerKey?
    private var baseURL: URL?
    private var idleOffloadSeconds: TimeInterval?
    private var idleTask: Task<Void, Never>?
    private var activityGeneration: UInt64 = 0

    init(config: WhisperCppConfig) {
        self.config = config
        self.idleOffloadSeconds = config.idleOffloadSeconds
    }

    var isEnabled: Bool {
        idleOffloadSeconds != 0
            && FileManager.default.isExecutableFile(atPath: config.serverExecutableURL.path)
    }

    func setIdleOffloadSeconds(_ seconds: TimeInterval?) {
        idleOffloadSeconds = seconds
        if seconds == 0 {
            shutdown()
        } else if process != nil {
            scheduleOffload()
        }
    }

    func warmUp(modelID: String, modelPath: URL, language: String, forceNoGPU: Bool) async {
        guard isEnabled else { return }
        _ = try? await ensureRunning(
            key: ServerKey(modelID: modelID, language: language, forceNoGPU: forceNoGPU),
            modelPath: modelPath
        )
    }

    func transcribe(
        _ request: TranscriptionRequest,
        modelPath: URL,
        forceNoGPU: Bool,
        startedAt: Date
    ) async throws -> TranscriptionResult {
        let key = ServerKey(modelID: request.modelID, language: request.language, forceNoGPU: forceNoGPU)
        let url = try await ensureRunning(key: key, modelPath: modelPath)
        request.progressHandler?(
            TranscriptionProgressEvent(
                phase: .transcribing,
                modelID: request.modelID,
                elapsedMS: Int(Date().timeIntervalSince(startedAt) * 1_000)
            )
        )

        var httpRequest = URLRequest(url: url.appendingPathComponent("inference"))
        httpRequest.httpMethod = "POST"
        let boundary = "Scrawl-\(UUID().uuidString)"
        httpRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try Self.multipartBody(
            audioURL: request.audioFileURL,
            prompt: request.promptContext,
            boundary: boundary
        )
        httpRequest.timeoutInterval = TimeInterval(config.transcriptionTimeoutSeconds)

        let (data, response) = try await URLSession.shared.data(for: httpRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TranscriptionError.executionFailed("whisper-server returned an invalid response")
        }
        let text = try WhisperCppProvider.decodeServerTranscript(data)
        scheduleOffload()
        return TranscriptionResult(
            text: text,
            latencyMS: Int(Date().timeIntervalSince(startedAt) * 1_000)
        )
    }

    func shutdown() {
        idleTask?.cancel()
        idleTask = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        serverKey = nil
        baseURL = nil
    }

    private func ensureRunning(key: ServerKey, modelPath: URL) async throws -> URL {
        if serverKey == key, let process, process.isRunning, let baseURL {
            scheduleOffload()
            return baseURL
        }
        shutdown()

        let port = Int.random(in: 20_000...49_999)
        let baseURL = URL(string: "http://127.0.0.1:\(port)")!
        let process = Process()
        let serverArguments = makeServerArguments(
            modelPath: modelPath,
            language: key.language,
            port: port,
            forceNoGPU: key.forceNoGPU
        )
        let launch = Self.supervisedLaunch(
            serverExecutableURL: config.serverExecutableURL,
            serverArguments: serverArguments,
            ownerPID: ProcessInfo.processInfo.processIdentifier
        )
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        self.process = process
        self.serverKey = key
        self.baseURL = baseURL

        do {
            try await waitUntilReady(process: process, baseURL: baseURL)
            scheduleOffload()
            return baseURL
        } catch {
            shutdown()
            throw error
        }
    }

    private func makeServerArguments(
        modelPath: URL,
        language: String,
        port: Int,
        forceNoGPU: Bool
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

    private func waitUntilReady(process: Process, baseURL: URL) async throws {
        for _ in 0..<100 {
            guard process.isRunning else {
                throw TranscriptionError.executionFailed("whisper-server exited during startup")
            }
            var request = URLRequest(url: baseURL)
            request.timeoutInterval = 0.2
            if (try? await URLSession.shared.data(for: request)) != nil {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw TranscriptionError.executionFailed("whisper-server did not become ready")
    }

    private func scheduleOffload() {
        activityGeneration &+= 1
        let generation = activityGeneration
        idleTask?.cancel()
        guard let seconds = idleOffloadSeconds, seconds > 0 else { return }
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.offloadIfIdle(generation: generation)
        }
    }

    private func offloadIfIdle(generation: UInt64) {
        guard generation == activityGeneration else { return }
        shutdown()
    }

    private static func multipartBody(audioURL: URL, prompt: String?, boundary: String) throws -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(try Data(contentsOf: audioURL))
        append("\r\n--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n")
        if let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n\(prompt)\r\n")
        }
        append("--\(boundary)--\r\n")
        return body
    }

    static func supervisedLaunch(
        serverExecutableURL: URL,
        serverArguments: [String],
        ownerPID: Int32
    ) -> SupervisedLaunch {
        let script = """
        owner=$1
        shift
        "$@" &
        child=$!
        cleanup() {
          kill "$child" 2>/dev/null || true
          wait "$child" 2>/dev/null || true
        }
        trap cleanup EXIT TERM INT
        while kill -0 "$owner" 2>/dev/null && kill -0 "$child" 2>/dev/null; do
          sleep 1
        done
        """
        return SupervisedLaunch(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: [
                "-c", script, "scrawl-whisper-supervisor", String(ownerPID),
                serverExecutableURL.path
            ] + serverArguments
        )
    }
}
