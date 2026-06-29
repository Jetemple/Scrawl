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
        try? await session.warmUp()
        #endif
    }

    public func setIdleOffloadSeconds(_ seconds: TimeInterval?) async {
        #if arch(arm64)
        await session.setIdleOffloadSeconds(seconds)
        #endif
    }

    public func shutdown() async {
        #if arch(arm64)
        await session.shutdown()
        #endif
    }
}

#if arch(arm64)
private actor ParakeetModelSession {
    private var asrManager: AsrManager?
    private var idleOffloadSeconds: TimeInterval? = 300
    private var idleTask: Task<Void, Never>?
    private var activityGeneration: UInt64 = 0
    private var inFlightTranscriptions = 0

    func warmUp() async throws {
        _ = try await loadManager()
        scheduleOffload()
    }

    func transcribe(samples: [Float], didLoadModel: @Sendable () -> Void) async throws -> String {
        let manager = try await loadManager()
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

    private func loadManager() async throws -> AsrManager {
        if let asrManager {
            return asrManager
        }

        let models = try await AsrModels.downloadAndLoad(version: .v3)
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
#endif
