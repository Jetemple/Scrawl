import Foundation
import TranscriptionCore

actor WarmWhisperServer {
    struct SupervisedLaunch {
        let executableURL: URL
        let arguments: [String]
    }

    struct ServerKey: Equatable {
        let modelID: String
        let language: String
        let forceNoGPU: Bool
    }

    private let config: WhisperCppConfig
    private var process: Process?
    private var serverKey: ServerKey?
    private var baseURL: URL?
    private var startupTask: Task<URL, Error>?
    private var startupKey: ServerKey?
    private var idleOffloadSeconds: TimeInterval?
    private var idleTask: Task<Void, Never>?
    private var activityGeneration: UInt64 = 0
    private var inFlightRequests = 0

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

        inFlightRequests += 1
        defer {
            inFlightRequests -= 1
            scheduleOffload()
        }
        let (data, response) = try await URLSession.shared.data(for: httpRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TranscriptionError.executionFailed("whisper-server returned an invalid response")
        }
        let text = try WhisperCppProvider.decodeServerTranscript(data)
        return TranscriptionResult(
            text: text,
            latencyMS: Int(Date().timeIntervalSince(startedAt) * 1_000)
        )
    }

    func shutdown() {
        idleTask?.cancel()
        idleTask = nil
        startupTask?.cancel()
        startupTask = nil
        startupKey = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        serverKey = nil
        baseURL = nil
    }

    internal func ensureRunning(key: ServerKey, modelPath: URL) async throws -> URL {
        // In-flight startup for same key — join the existing task
        if startupKey == key, let task = startupTask {
            let url = try await task.value
            // Startup succeeded; re-validate the process is still alive
            guard let p = self.process, p.isRunning else {
                shutdown()
                return try await ensureRunning(key: key, modelPath: modelPath)
            }
            return url
        }

        // Server already running and ready
        if serverKey == key, let process, process.isRunning, let baseURL {
            return baseURL
        }

        // Tear down any existing state and start fresh
        shutdown()
        startupKey = key

        let task = Task {
            // First launch attempt
            let port1 = try Self.allocatePort()
            let url1 = URL(string: "http://127.0.0.1:\(port1)")!
            let process1 = Process()
            do {
                let serverArguments = self.makeServerArguments(
                    modelPath: modelPath, language: key.language,
                    port: port1, forceNoGPU: key.forceNoGPU
                )
                let launch = Self.supervisedLaunch(
                    serverExecutableURL: self.config.serverExecutableURL,
                    serverArguments: serverArguments,
                    ownerPID: ProcessInfo.processInfo.processIdentifier
                )
                process1.executableURL = launch.executableURL
                process1.arguments = launch.arguments
                process1.standardOutput = FileHandle.nullDevice
                process1.standardError = FileHandle.nullDevice
                try process1.run()
            } catch {
                if self.startupKey == key { self.startupTask = nil; self.startupKey = nil }
                throw error
            }

            // Wait for readiness; on "exited during startup" retry once with a fresh port.
            let process: Process
            let url: URL
            do {
                try await self.waitUntilReady(process: process1, baseURL: url1)
                (process, url) = (process1, url1)
            } catch TranscriptionError.executionFailed(let msg)
                where msg == "whisper-server exited during startup" {
                // The server exited before it could bind — likely a port race between
                // allocatePort() closing the probe socket and whisper-server calling
                // bind(). Terminate the (already-dead) supervisor wrapper defensively,
                // then retry with a freshly allocated port. Concurrent callers
                // awaiting this Task transparently get the retry result.
                process1.terminate()
                let port2 = try Self.allocatePort()
                let url2 = URL(string: "http://127.0.0.1:\(port2)")!
                let process2 = Process()
                do {
                    let serverArguments = self.makeServerArguments(
                        modelPath: modelPath, language: key.language,
                        port: port2, forceNoGPU: key.forceNoGPU
                    )
                    let launch = Self.supervisedLaunch(
                        serverExecutableURL: self.config.serverExecutableURL,
                        serverArguments: serverArguments,
                        ownerPID: ProcessInfo.processInfo.processIdentifier
                    )
                    process2.executableURL = launch.executableURL
                    process2.arguments = launch.arguments
                    process2.standardOutput = FileHandle.nullDevice
                    process2.standardError = FileHandle.nullDevice
                    try process2.run()
                    try await self.waitUntilReady(process: process2, baseURL: url2)
                } catch {
                    process2.terminate()
                    if self.startupKey == key { self.startupTask = nil; self.startupKey = nil }
                    throw error
                }
                (process, url) = (process2, url2)
            } catch {
                process1.terminate()
                if self.startupKey == key { self.startupTask = nil; self.startupKey = nil }
                throw error
            }

            // Only publish after readiness is confirmed
            self.process = process
            self.serverKey = key
            self.baseURL = url
            // Schedule an idle-offload timer so a warmed-but-never-used server
            // doesn't hold a loaded model forever. offloadIfIdle checks
            // inFlightRequests before actually shutting down, and transcribe's
            // defer reschedules after each request completes.
            self.scheduleOffload()
            return url
        }
        startupTask = task

        do {
            let url = try await task.value
            startupTask = nil
            return url
        } catch {
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

    internal func waitUntilReady(process: Process, baseURL: URL) async throws {
        // 60 iterations × (1s sleep + 0.5s probe timeout) ≈ 90s max budget
        for _ in 0..<60 {
            guard process.isRunning else {
                throw TranscriptionError.executionFailed("whisper-server exited during startup")
            }
            var request = URLRequest(url: baseURL)
            request.timeoutInterval = 0.5
            if let (data, _) = try? await URLSession.shared.data(for: request),
               Self.isWhisperServerResponse(data) {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw TranscriptionError.executionFailed("whisper-server did not become ready in 90 seconds")
    }

    /// Returns true when the HTTP response body looks like it came from whisper-server.
    /// Empirically verified against whisper-server 1.x (Homebrew): GET / returns an HTML page
    /// with the title "Whisper.cpp Server". A foreign service on the same port (e.g. a dev server
    /// returning 404 or a non-whisper process) will not contain these strings.
    internal static func isWhisperServerResponse(_ data: Data) -> Bool {
        guard let body = String(data: data, encoding: .utf8) else { return false }
        let lower = body.lowercased()
        return lower.contains("whisper.cpp") || lower.contains("whisper-server")
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
        if inFlightRequests > 0 {
            scheduleOffload()
            return
        }
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

    /// Asks the kernel for a free TCP port by binding to :0 and reading the assigned address.
    /// This eliminates the random-range collision risk and TOCTOU window is minimal because the
    /// port is passed directly to whisper-server before other callers can claim it.
    internal static func allocatePort() throws -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw TranscriptionError.executionFailed("socket() failed: could not allocate port")
        }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = INADDR_ANY
        let bindResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw TranscriptionError.executionFailed("bind() failed: could not allocate port")
        }
        var boundAddr = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &boundLen)
            }
        }
        guard nameResult == 0 else {
            throw TranscriptionError.executionFailed("getsockname() failed: could not read port")
        }
        return Int(UInt16(bigEndian: boundAddr.sin_port))
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
