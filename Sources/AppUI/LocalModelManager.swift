import Foundation

struct DownloadableModel: Equatable, Sendable {
    let id: String
    let fileName: String
    let displayName: String
    let url: URL
}

final class LocalModelManager: @unchecked Sendable {
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
            .sorted()
    }

    func modelExists(id: String) -> Bool {
        let path = modelsDirectoryURL.appendingPathComponent("\(id).bin")
        return FileManager.default.fileExists(atPath: path.path)
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

    func download(model: DownloadableModel) async throws -> URL {
        try ensureDirectory()

        let (temporaryURL, response) = try await URLSession.shared.download(from: model.url)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw NSError(domain: "LocalModelManager", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Download failed with HTTP \(http.statusCode)"
            ])
        }

        let destination = modelsDirectoryURL.appendingPathComponent(model.fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
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
