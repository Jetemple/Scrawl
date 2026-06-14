import Foundation

struct DownloadableModel: Equatable, Sendable {
    let id: String
    let fileName: String
    let displayName: String
    let url: URL
    let sha256: String
}

private enum ModelDownloadError: LocalizedError {
    case invalidHTTPResponse(URL)
    case badStatusCode(statusCode: Int, url: URL)
    case likelyErrorDocument(URL)
    case allSourcesFailed(modelID: String, failures: [String])
    case downloadAlreadyInProgress

    var errorDescription: String? {
        switch self {
        case let .invalidHTTPResponse(url):
            return "Download failed: invalid server response from \(url.host ?? url.absoluteString)."
        case let .badStatusCode(statusCode, url):
            return "Download failed with HTTP \(statusCode) from \(url.host ?? url.absoluteString)."
        case let .likelyErrorDocument(url):
            return "Download failed: server returned non-model data from \(url.host ?? url.absoluteString)."
        case let .allSourcesFailed(modelID, failures):
            let details = failures.joined(separator: " | ")
            return "Could not download \(modelID). \(details)"
        case .downloadAlreadyInProgress:
            return "Another model download is already in progress."
        }
    }
}

struct ModelDownloadOperationState {
    private(set) var activeOperationID: UUID?
    private(set) var activeModelID: String?

    mutating func begin(modelID: String) throws -> UUID {
        guard activeOperationID == nil else {
            throw ModelDownloadError.downloadAlreadyInProgress
        }
        let operationID = UUID()
        activeOperationID = operationID
        activeModelID = modelID
        return operationID
    }

    @discardableResult
    mutating func cancel() -> Bool {
        guard activeOperationID != nil else { return false }
        activeOperationID = nil
        activeModelID = nil
        return true
    }

    mutating func finish(_ operationID: UUID) {
        guard owns(operationID) else { return }
        cancel()
    }

    func owns(_ operationID: UUID) -> Bool {
        activeOperationID == operationID
    }
}

private final class DownloadCallbackState: @unchecked Sendable {
    private let lock = NSLock()
    private weak var task: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    private var didComplete = false

    func setTask(_ task: URLSessionDownloadTask) {
        lock.withLock {
            self.task = task
        }
    }

    func setObservation(_ observation: NSKeyValueObservation) {
        lock.withLock {
            if didComplete {
                observation.invalidate()
            } else {
                self.observation = observation
            }
        }
    }

    func beginCompletion() -> Bool {
        lock.withLock {
            guard !didComplete else { return false }
            didComplete = true
            observation?.invalidate()
            observation = nil
            return true
        }
    }

    func byteCounts() -> (received: Int64, expected: Int64?) {
        lock.withLock {
            let expected = task?.countOfBytesExpectedToReceive ?? -1
            return (
                task?.countOfBytesReceived ?? 0,
                expected > 0 ? expected : nil
            )
        }
    }
}

final class LocalModelManager: @unchecked Sendable {
    typealias ProgressHandler = @Sendable (_ receivedBytes: Int64, _ totalBytes: Int64?) -> Void

    private let lock = NSLock()
    private let modelsDirectoryURL: URL
    private(set) var isDownloadInProgress: Bool = false
    /// Resume data keyed by source URL string — resume data is URL-specific and
    /// cannot be replayed against a different mirror URL.
    private(set) var pendingResumeDataBySourceURL: [String: Data] = [:]
    private var operationState = ModelDownloadOperationState()
    private var activeDownloadTask: URLSessionDownloadTask? = nil
    private var activeDownloadSession: URLSession? = nil
    private var activeDownloadOperationID: UUID? = nil
    private var latestDownloadOperationID: UUID? = nil

    init(modelsDirectoryURL: URL) {
        self.modelsDirectoryURL = modelsDirectoryURL
    }

    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
    }

    func installedModelIDs() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        guard let files = try? FileManager.default.contentsOfDirectory(at: modelsDirectoryURL, includingPropertiesForKeys: nil) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "bin" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { !$0.hasPrefix("for-tests-") }
            .sorted()
    }

    func modelExists(id: String) -> Bool {
        let path = modelsDirectoryURL.appendingPathComponent("\(id).bin")
        return FileManager.default.fileExists(atPath: path.path)
    }

    func modelExists(downloadableModel: DownloadableModel) -> Bool {
        let explicitFilePath = modelsDirectoryURL.appendingPathComponent(downloadableModel.fileName)
        if FileManager.default.fileExists(atPath: explicitFilePath.path) {
            return true
        }
        if modelExists(id: downloadableModel.id) {
            return true
        }

        let targetFamilies: Set<String> = [
            canonicalFamily(from: downloadableModel.id),
            canonicalFamily(from: downloadableModel.fileName)
        ]

        let installedFamilies = Set(installedModelIDs().map(canonicalFamily(from:)))
        return !targetFamilies.isDisjoint(with: installedFamilies)
    }

    func modelURL(id: String) -> URL {
        modelsDirectoryURL.appendingPathComponent("\(id).bin")
    }

    func deleteModel(id: String) throws {
        let url = modelURL(id: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func cancelDownload() -> Bool {
        let cancellation: (didCancel: Bool, task: URLSessionDownloadTask?, taskURL: URL?, operationID: UUID?) = lock.withLock {
            guard let cancelledOperationID = operationState.activeOperationID else {
                return (false, nil, nil, nil)
            }
            let task = activeDownloadTask
            // Capture the URL before cancelling so resume data can be stored under
            // the exact URL the task was running against (resume data is URL-specific).
            let taskURL = task?.currentRequest?.url ?? task?.originalRequest?.url
            operationState.cancel()
            activeDownloadTask = nil
            activeDownloadSession = nil
            activeDownloadOperationID = nil
            isDownloadInProgress = false
            return (true, task, taskURL, cancelledOperationID)
        }
        let (didCancel, task, taskURL, cancelledOperationID) = cancellation

        guard let task else { return didCancel }
        task.cancel(byProducingResumeData: { [weak self] (data: Data?) in
            guard let self, let data, let urlKey = taskURL?.absoluteString, let cancelledOperationID else { return }
            self.lock.withLock {
                // A restarted operation owns its own URLSession/resume state. A delayed
                // callback from the cancelled task must not overwrite it.
                guard self.latestDownloadOperationID == cancelledOperationID else { return }
                self.pendingResumeDataBySourceURL[urlKey] = data
            }
        })
        return didCancel
    }

    func download(model: DownloadableModel, onProgress: ProgressHandler? = nil) async throws -> URL {
        let operationID = try beginDownloadOperation(modelID: model.id)
        defer { finishDownloadOperation(operationID) }

        try ensureDirectory()
        var failures: [String] = []

        for sourceURL in model.candidateDownloadURLs {
            try requireActiveDownloadOperation(operationID)
            var temporaryURL: URL?
            do {
                let downloadedURL = try await downloadFromURL(
                    sourceURL,
                    operationID: operationID,
                    onProgress: onProgress
                )
                temporaryURL = downloadedURL
                try requireActiveDownloadOperation(operationID)
                try ModelDownloadValidator.verifySHA256(of: downloadedURL, expected: model.sha256)
                try requireActiveDownloadOperation(operationID)
                return try installDownloadedModel(
                    from: downloadedURL,
                    fileName: model.fileName,
                    operationID: operationID
                )
            } catch {
                if let temp = temporaryURL {
                    try? FileManager.default.removeItem(at: temp)
                }
                // User-initiated cancel: stop the entire mirror/retry/install operation.
                if isCancellation(error) || !ownsDownloadOperation(operationID) {
                    throw URLError(.cancelled)
                }
                if error is ModelDownloadValidator.HashMismatchError {
                    failures.append("\(sourceURL.absoluteString): SHA-256 mismatch")
                } else {
                    failures.append("\(sourceURL.absoluteString): \(describe(error))")
                }
            }
        }

        throw ModelDownloadError.allSourcesFailed(modelID: model.id, failures: failures)
    }

    private func canonicalFamily(from raw: String) -> String {
        PreferencesModelState.canonicalFamily(raw)
    }

    private func downloadFromURL(
        _ sourceURL: URL,
        operationID: UUID,
        onProgress: ProgressHandler?
    ) async throws -> URL {
        var lastError: Error?
        for attempt in 1 ... 2 {
            try requireActiveDownloadOperation(operationID)
            var downloadedURL: URL?
            do {
                let (temporaryURL, response) = try await performDownload(
                    from: sourceURL,
                    operationID: operationID,
                    onProgress: onProgress
                )
                downloadedURL = temporaryURL
                try requireActiveDownloadOperation(operationID)
                guard let http = response as? HTTPURLResponse else {
                    throw ModelDownloadError.invalidHTTPResponse(sourceURL)
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    throw ModelDownloadError.badStatusCode(statusCode: http.statusCode, url: sourceURL)
                }
                try validateDownloadedContent(at: temporaryURL, response: response, sourceURL: sourceURL)
                return temporaryURL
            } catch {
                if let downloadedURL {
                    try? FileManager.default.removeItem(at: downloadedURL)
                }
                lastError = error
                if isCancellation(error) || !ownsDownloadOperation(operationID) {
                    throw URLError(.cancelled)
                }
                guard attempt < 2, isTransientNetworkError(error) else {
                    throw error
                }
                // Stash any resume data from the system for the next attempt of this same URL.
                if let resumeDataFromError = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                    lock.withLock {
                        guard operationState.owns(operationID) else { return }
                        pendingResumeDataBySourceURL[sourceURL.absoluteString] = resumeDataFromError
                    }
                }
                try await Task.sleep(nanoseconds: 600_000_000)
                try requireActiveDownloadOperation(operationID)
            }
        }

        throw lastError ?? ModelDownloadError.invalidHTTPResponse(sourceURL)
    }

    private func performDownload(
        from sourceURL: URL,
        operationID: UUID,
        onProgress: ProgressHandler?
    ) async throws -> (URL, URLResponse) {
        let session = makeDownloadSession()

        let resumeData = try lock.withLock {
            guard operationState.owns(operationID) else {
                throw URLError(.cancelled)
            }
            activeDownloadSession = session
            activeDownloadOperationID = operationID
            return pendingResumeDataBySourceURL.removeValue(forKey: sourceURL.absoluteString)
        }

        defer {
            lock.withLock {
                if activeDownloadSession === session, activeDownloadOperationID == operationID {
                    activeDownloadTask = nil
                    activeDownloadSession = nil
                    activeDownloadOperationID = nil
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            let callbackState = DownloadCallbackState()

            let completionHandler: @Sendable (URL?, URLResponse?, Error?) -> Void = { temporaryURL, response, error in
                guard callbackState.beginCompletion() else { return }
                session.finishTasksAndInvalidate()

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let temporaryURL, let response else {
                    continuation.resume(throwing: ModelDownloadError.invalidHTTPResponse(sourceURL))
                    return
                }

                let safeCopy = FileManager.default.temporaryDirectory
                    .appendingPathComponent("scrawl-download-\(UUID().uuidString).bin")
                do {
                    try FileManager.default.moveItem(at: temporaryURL, to: safeCopy)
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Final progress callback so callers see 100 % on success.
                let counts = callbackState.byteCounts()
                onProgress?(counts.received, counts.expected)

                continuation.resume(returning: (safeCopy, response))
            }

            let task: URLSessionDownloadTask
            if let resumeData {
                task = session.downloadTask(withResumeData: resumeData, completionHandler: completionHandler)
            } else {
                task = session.downloadTask(with: sourceURL, completionHandler: completionHandler)
            }
            callbackState.setTask(task)

            // Register task under lock BEFORE resume() to eliminate the window
            // where cancelDownload() could see activeDownloadTask == nil.
            do {
                try lock.withLock {
                    guard operationState.owns(operationID) else {
                        throw URLError(.cancelled)
                    }
                    activeDownloadTask = task
                }
            } catch {
                session.invalidateAndCancel()
                if callbackState.beginCompletion() {
                    continuation.resume(throwing: error)
                }
                return
            }

            if let onProgress {
                let observation = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak task] _, _ in
                    let expected = task?.countOfBytesExpectedToReceive ?? -1
                    let totalBytes = expected > 0 ? expected : nil
                    let receivedBytes = task?.countOfBytesReceived ?? 0
                    onProgress(receivedBytes, totalBytes)
                }
                callbackState.setObservation(observation)
            }

            task.resume()
        }
    }

    private func installDownloadedModel(from temporaryURL: URL, fileName: String, operationID: UUID) throws -> URL {
        try lock.withLock {
            guard operationState.owns(operationID) else {
                throw URLError(.cancelled)
            }
            let destination = modelsDirectoryURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            operationState.finish(operationID)
            isDownloadInProgress = false
            return destination
        }
    }

    private func makeDownloadSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 6 * 60 * 60
        return URLSession(configuration: configuration)
    }

    private func validateDownloadedContent(at fileURL: URL, response: URLResponse, sourceURL: URL) throws {
        let mimeType = response.mimeType?.lowercased() ?? ""
        if mimeType.hasPrefix("text/") || mimeType.contains("json") || mimeType.contains("html") {
            throw ModelDownloadError.likelyErrorDocument(sourceURL)
        }

        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize, fileSize < 1_000_000 {
            throw ModelDownloadError.likelyErrorDocument(sourceURL)
        }
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private func beginDownloadOperation(modelID: String) throws -> UUID {
        try lock.withLock {
            let operationID = try operationState.begin(modelID: modelID)
            latestDownloadOperationID = operationID
            isDownloadInProgress = true
            return operationID
        }
    }

    private func finishDownloadOperation(_ operationID: UUID) {
        lock.withLock {
            guard operationState.owns(operationID) else { return }
            operationState.finish(operationID)
            isDownloadInProgress = false
        }
    }

    private func ownsDownloadOperation(_ operationID: UUID) -> Bool {
        lock.withLock {
            operationState.owns(operationID)
        }
    }

    private func requireActiveDownloadOperation(_ operationID: UUID) throws {
        do {
            try Task.checkCancellation()
        } catch {
            throw URLError(.cancelled)
        }
        guard ownsDownloadOperation(operationID) else {
            throw URLError(.cancelled)
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func describe(_ error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}

extension LocalModelManager {
    static let downloadableModels: [DownloadableModel] = [
        DownloadableModel(
            id: "ggml-tiny.en",
            fileName: "ggml-tiny.en.bin",
            displayName: "tiny.en — fast, 75 MB",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin")!,
            sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f"
        ),
        DownloadableModel(
            id: "ggml-small.en",
            fileName: "ggml-small.en.bin",
            displayName: "small.en — recommended, 466 MB",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!,
            sha256: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"
        ),
        DownloadableModel(
            id: "ggml-medium",
            fileName: "ggml-medium.bin",
            displayName: "medium — multilingual, 1.5 GB",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
            sha256: "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208"
        ),
        DownloadableModel(
            id: "ggml-large-v3-turbo",
            fileName: "ggml-large-v3-turbo.bin",
            displayName: "large-v3-turbo — highest accuracy, 1.6 GB",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
            sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
        )
    ]
}

private extension DownloadableModel {
    var candidateDownloadURLs: [URL] {
        var urls: [URL] = [url]
        if let withDownloadParam = withDownloadQuery(from: url) {
            urls.append(withDownloadParam)
        }

        if let datasetMirror = huggingFaceDatasetMirror(from: url) {
            urls.append(datasetMirror)
            if let datasetWithDownloadParam = withDownloadQuery(from: datasetMirror) {
                urls.append(datasetWithDownloadParam)
            }
        }

        var unique: [URL] = []
        var seen = Set<String>()
        for item in urls {
            if seen.insert(item.absoluteString).inserted {
                unique.append(item)
            }
        }
        return unique
    }

    private func withDownloadQuery(from baseURL: URL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var queryItems = components.queryItems ?? []
        if queryItems.contains(where: { $0.name == "download" }) {
            return nil
        }
        queryItems.append(URLQueryItem(name: "download", value: "true"))
        components.queryItems = queryItems
        return components.url
    }

    private func huggingFaceDatasetMirror(from baseURL: URL) -> URL? {
        guard
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
            components.host == "huggingface.co",
            !components.path.hasPrefix("/datasets/")
        else {
            return nil
        }

        components.path = "/datasets" + components.path
        return components.url
    }
}
