import Foundation
import TranscriptionCore

public final class RoutingTranscriptionProvider: ModelRetainingTranscriptionProvider, @unchecked Sendable {
    private let whisperProvider: any TranscriptionProvider
    private let whisperRetainingProvider: (any ModelRetainingTranscriptionProvider)?
    private let parakeetProvider: (any TranscriptionProvider)?
    private let parakeetRetainingProvider: (any ModelRetainingTranscriptionProvider)?

    public init(
        whisperProvider: any TranscriptionProvider,
        parakeetProvider: (any TranscriptionProvider)?
    ) {
        self.whisperProvider = whisperProvider
        whisperRetainingProvider = whisperProvider as? any ModelRetainingTranscriptionProvider
        self.parakeetProvider = parakeetProvider
        parakeetRetainingProvider = parakeetProvider as? any ModelRetainingTranscriptionProvider
    }

    public func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        try await provider(for: request.modelID).transcribe(request)
    }

    public func warmUp(modelID: String, language: String) async {
        if modelID == TranscriptionModelID.parakeetV3, let parakeetRetainingProvider {
            await parakeetRetainingProvider.warmUp(modelID: modelID, language: language)
            return
        }
        await whisperRetainingProvider?.warmUp(modelID: modelID, language: language)
    }

    public func prepareModel(
        modelID: String,
        language: String,
        progressHandler: ModelPreparationProgressHandler?
    ) async throws {
        if modelID == TranscriptionModelID.parakeetV3, let parakeetRetainingProvider {
            try await parakeetRetainingProvider.prepareModel(
                modelID: modelID,
                language: language,
                progressHandler: progressHandler
            )
            return
        }
        try await whisperRetainingProvider?.prepareModel(
            modelID: modelID,
            language: language,
            progressHandler: progressHandler
        )
    }

    public func setIdleOffloadSeconds(_ seconds: TimeInterval?) async {
        await whisperRetainingProvider?.setIdleOffloadSeconds(seconds)
        await parakeetRetainingProvider?.setIdleOffloadSeconds(nil)
    }

    public func shutdown(modelID: String) async {
        if modelID == TranscriptionModelID.parakeetV3 {
            await parakeetRetainingProvider?.shutdown()
            return
        }
        await whisperRetainingProvider?.shutdown(modelID: modelID)
    }

    public func shutdown() async {
        await whisperRetainingProvider?.shutdown()
        await parakeetRetainingProvider?.shutdown()
    }

    private func provider(for modelID: String) -> any TranscriptionProvider {
        if modelID == TranscriptionModelID.parakeetV3, let parakeetProvider {
            return parakeetProvider
        }
        return whisperProvider
    }
}
