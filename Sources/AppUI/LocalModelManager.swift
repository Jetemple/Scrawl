import Foundation

struct DownloadableModel: Equatable, Sendable {
    let id: String
    let fileName: String
    let displayName: String
    let url: URL
}

private enum ModelDownloadError: LocalizedError {
    case invalidHTTPResponse(URL)
    case badStatusCode(statusCode: Int, url: URL)
    case likelyErrorDocument(URL)
    case allSourcesFailed(modelID: String, failures: [String])

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
        }
    }
}

final class LocalModelManager: @unchecked Sendable {
    typealias ProgressHandler = @Sendable (_ receivedBytes: Int64, _ totalBytes: Int64?) -> Void

    private let lock = NSLock()
    private let modelsDirectoryURL: URL

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

    func download(model: DownloadableModel, onProgress: ProgressHandler? = nil) async throws -> URL {
        try ensureDirectory()
        var failures: [String] = []

        for sourceURL in model.candidateDownloadURLs {
            do {
                let temporaryURL = try await downloadFromURL(sourceURL, onProgress: onProgress)
                return try installDownloadedModel(from: temporaryURL, fileName: model.fileName)
            } catch {
                failures.append("\(sourceURL.absoluteString): \(describe(error))")
            }
        }

        throw ModelDownloadError.allSourcesFailed(modelID: model.id, failures: failures)
    }

    private func canonicalFamily(from raw: String) -> String {
        var value = raw.lowercased()
        if value.hasSuffix(".bin") {
            value = String(value.dropLast(4))
        }
        if value.hasPrefix("ggml-") {
            value = String(value.dropFirst(5))
        }
        if value.hasSuffix(".en") {
            value = String(value.dropLast(3))
        }
        return value
    }

    private func downloadFromURL(_ sourceURL: URL, onProgress: ProgressHandler?) async throws -> URL {
        var lastError: Error?
        for attempt in 1 ... 2 {
            do {
                let (temporaryURL, response) = try await performDownload(from: sourceURL, onProgress: onProgress)
                guard let http = response as? HTTPURLResponse else {
                    throw ModelDownloadError.invalidHTTPResponse(sourceURL)
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    throw ModelDownloadError.badStatusCode(statusCode: http.statusCode, url: sourceURL)
                }
                try validateDownloadedContent(at: temporaryURL, response: response, sourceURL: sourceURL)
                return temporaryURL
            } catch {
                lastError = error
                guard attempt < 2, isTransientNetworkError(error) else {
                    throw error
                }
                try await Task.sleep(nanoseconds: 600_000_000)
            }
        }

        throw lastError ?? ModelDownloadError.invalidHTTPResponse(sourceURL)
    }

    private func performDownload(from sourceURL: URL, onProgress: ProgressHandler?) async throws -> (URL, URLResponse) {
        let session = makeDownloadSession()

        return try await withCheckedThrowingContinuation { continuation in
            var observation: NSKeyValueObservation?
            var downloadTask: URLSessionDownloadTask?

            let task = session.downloadTask(with: sourceURL) { temporaryURL, response, error in
                observation?.invalidate()
                session.finishTasksAndInvalidate()

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let temporaryURL, let response else {
                    continuation.resume(throwing: ModelDownloadError.invalidHTTPResponse(sourceURL))
                    return
                }

                let expected = downloadTask?.countOfBytesExpectedToReceive ?? -1
                let totalBytes = expected > 0 ? expected : nil
                let receivedBytes = downloadTask?.countOfBytesReceived ?? 0
                onProgress?(receivedBytes, totalBytes)
                continuation.resume(returning: (temporaryURL, response))
            }
            downloadTask = task

            if let onProgress {
                observation = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { _, _ in
                    let expected = downloadTask?.countOfBytesExpectedToReceive ?? -1
                    let totalBytes = expected > 0 ? expected : nil
                    let receivedBytes = downloadTask?.countOfBytesReceived ?? 0
                    onProgress(receivedBytes, totalBytes)
                }
            }

            task.resume()
        }
    }

    private func installDownloadedModel(from temporaryURL: URL, fileName: String) throws -> URL {
        let destination = modelsDirectoryURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
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

    private func describe(_ error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

extension LocalModelManager {
    static let downloadableModels: [DownloadableModel] = [
        DownloadableModel(
            id: "ggml-tiny.en",
            fileName: "ggml-tiny.en.bin",
            displayName: "tiny.en — fast, 75 MB",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin")!
        ),
        DownloadableModel(
            id: "ggml-small.en",
            fileName: "ggml-small.en.bin",
            displayName: "small.en — recommended, 466 MB",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!
        ),
        DownloadableModel(
            id: "ggml-medium",
            fileName: "ggml-medium.bin",
            displayName: "medium — multilingual, 1.5 GB",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!
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
