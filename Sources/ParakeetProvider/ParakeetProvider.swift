import Foundation
import TranscriptionCore

#if arch(arm64)
import FluidAudio
#endif

public final class ParakeetTranscriptionProvider: ModelRetainingTranscriptionProvider, @unchecked Sendable {
    #if arch(arm64)
    private let session = ParakeetModelSession()
    #endif

    public init() {}

    public func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        #if arch(arm64)
        let startedAt = Date()
        request.progressHandler?(
            TranscriptionProgressEvent(phase: .loadingModel, modelID: request.modelID, elapsedMS: 0)
        )

        // Parakeet v3 does not consume Scrawl's promptContext vocabulary biasing. Whisper keeps
        // that behavior when a whisper.cpp model is selected.
        let samples = try AudioConverter().resampleAudioFile(request.audioFileURL)
        let text = try await session.transcribe(samples: samples) {
            request.progressHandler?(
                TranscriptionProgressEvent(
                    phase: .transcribing,
                    modelID: request.modelID,
                    elapsedMS: Int(Date().timeIntervalSince(startedAt) * 1000)
                )
            )
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw TranscriptionError.noSpeechDetected
        }
        return TranscriptionResult(
            text: cleaned,
            latencyMS: Int(Date().timeIntervalSince(startedAt) * 1000)
        )
        #else
        throw TranscriptionError.providerUnavailable
        #endif
    }

    public func warmUp(modelID: String, language _: String) async {
        #if arch(arm64)
        guard modelID == TranscriptionModelID.parakeetV3 else { return }
        try? await session.warmUp(progressHandler: nil)
        #endif
    }

    public func prepareModel(
        modelID: String,
        language _: String,
        progressHandler: ModelPreparationProgressHandler?
    ) async throws {
        #if arch(arm64)
        guard modelID == TranscriptionModelID.parakeetV3 else { return }
        try await session.warmUp(progressHandler: progressHandler)
        #else
        throw TranscriptionError.providerUnavailable
        #endif
    }

    public func setIdleOffloadSeconds(_ seconds: TimeInterval?) async {
        #if arch(arm64)
        await session.setIdleOffloadSeconds(seconds)
        #endif
    }

    public func shutdown(modelID: String) async {
        guard modelID == TranscriptionModelID.parakeetV3 else { return }
        await shutdown()
    }

    public func shutdown() async {
        #if arch(arm64)
        await session.shutdown()
        #endif
    }

    public func deleteCachedParakeetV3Model() async throws -> ParakeetModelCacheDeletionResult {
        #if arch(arm64)
        return try await session.deleteModelCache()
        #else
        return ParakeetModelCacheDeletionResult(sizeBytes: nil)
        #endif
    }

    public static func parakeetV3CacheExists() -> Bool {
        #if arch(arm64)
        return ParakeetModelSession.parakeetV3CacheExists()
        #else
        return false
        #endif
    }

    public static func parakeetV3CacheSizeBytes() -> Int64? {
        #if arch(arm64)
        return ParakeetModelSession.parakeetV3CacheSizeBytes()
        #else
        return nil
        #endif
    }

    public static func deleteParakeetV3Cache() throws -> ParakeetModelCacheDeletionResult {
        #if arch(arm64)
        return try ParakeetModelSession.deleteParakeetV3Cache()
        #else
        return ParakeetModelCacheDeletionResult(sizeBytes: nil)
        #endif
    }
}

public struct ParakeetModelCacheDeletionResult: Equatable, Sendable {
    public let sizeBytes: Int64?

    public init(sizeBytes: Int64?) {
        self.sizeBytes = sizeBytes
    }
}

#if arch(arm64)
private actor ParakeetModelSession {
    private var asrManager: AsrManager?
    private var idleOffloadSeconds: TimeInterval?
    private var idleTask: Task<Void, Never>?
    private var activityGeneration: UInt64 = 0
    private var inFlightTranscriptions = 0

    func warmUp(progressHandler: ModelPreparationProgressHandler?) async throws {
        _ = try await loadManager(progressHandler: progressHandler)
        scheduleOffload()
    }

    func transcribe(samples: [Float], didLoadModel: @Sendable () -> Void) async throws -> String {
        let manager = try await loadManager(progressHandler: nil)
        didLoadModel()

        inFlightTranscriptions += 1
        defer {
            inFlightTranscriptions -= 1
            scheduleOffload()
        }

        let decoderLayers = await manager.decoderLayerCount
        var decoderState = TdtDecoderState.make(decoderLayers: decoderLayers)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text
    }

    func setIdleOffloadSeconds(_ seconds: TimeInterval?) {
        idleOffloadSeconds = seconds
        if seconds == 0 {
            shutdown()
        } else if asrManager != nil {
            scheduleOffload()
        }
    }

    func shutdown() {
        idleTask?.cancel()
        idleTask = nil
        asrManager = nil
        activityGeneration &+= 1
    }

    func deleteModelCache() throws -> ParakeetModelCacheDeletionResult {
        shutdown()
        return try Self.deleteParakeetV3Cache()
    }

    static func parakeetV3CacheExists() -> Bool {
        FileManager.default.fileExists(atPath: parakeetV3CacheURL.path)
    }

    static func parakeetV3CacheSizeBytes() -> Int64? {
        directorySizeBytes(at: parakeetV3CacheURL)
    }

    static func deleteParakeetV3Cache() throws -> ParakeetModelCacheDeletionResult {
        let sizeBytes = parakeetV3CacheSizeBytes()
        DownloadUtils.clearModelCache(forRepo: .parakeetV3, directory: fluidAudioModelsDirectory)
        if FileManager.default.fileExists(atPath: parakeetV3CacheURL.path) {
            try FileManager.default.removeItem(at: parakeetV3CacheURL)
        }
        return ParakeetModelCacheDeletionResult(sizeBytes: sizeBytes)
    }

    private static var fluidAudioModelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private static var parakeetV3CacheURL: URL {
        fluidAudioModelsDirectory.appendingPathComponent(Repo.parakeetV3.folderName, isDirectory: true)
    }

    private static func directorySizeBytes(at url: URL) -> Int64? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true,
                let fileSize = values.fileSize
            else {
                continue
            }
            total += Int64(fileSize)
        }
        return total
    }

    private func loadManager(progressHandler: ModelPreparationProgressHandler?) async throws -> AsrManager {
        if let asrManager {
            return asrManager
        }

        let fluidProgressHandler: DownloadUtils.ProgressHandler?
        if let progressHandler {
            fluidProgressHandler = { @Sendable progress in
                progressHandler(ParakeetDownloadProgressMapper.map(progress))
            }
        } else {
            fluidProgressHandler = nil
        }

        let models = try await AsrModels.downloadAndLoad(
            version: .v3,
            progressHandler: fluidProgressHandler
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        asrManager = manager
        return manager
    }

    private func scheduleOffload() {
        idleTask?.cancel()
        guard let seconds = idleOffloadSeconds, seconds > 0, asrManager != nil else {
            return
        }

        activityGeneration &+= 1
        let generation = activityGeneration
        idleTask = Task { [weak self] in
            let nanoseconds = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            await self?.offloadIfIdle(generation: generation)
        }
    }

    private func offloadIfIdle(generation: UInt64) {
        guard generation == activityGeneration, inFlightTranscriptions == 0 else {
            return
        }
        shutdown()
    }
}

enum ParakeetDownloadProgressMapper {
    static func map(_ progress: DownloadUtils.DownloadProgress) -> ModelPreparationProgress {
        switch progress.phase {
        case .listing:
            return ModelPreparationProgress(fractionCompleted: nil, phase: .checkingCache)
        case let .downloading(completedFiles, totalFiles):
            guard totalFiles > 0 else {
                return ModelPreparationProgress(fractionCompleted: nil, phase: .checkingCache)
            }
            let fileFraction = Double(completedFiles) / Double(totalFiles)
            return ModelPreparationProgress(
                fractionCompleted: fileFraction.clampedToUnitInterval,
                phase: .downloading
            )
        case .compiling:
            return ModelPreparationProgress(fractionCompleted: nil, phase: .optimizing)
        }
    }
}

private extension Double {
    var clampedToUnitInterval: Double {
        max(0, min(1, self))
    }
}
#endif
