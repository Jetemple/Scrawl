import Foundation

public enum TranscriptionProgressPhase: Sendable, Equatable {
    case loadingModel
    case transcribing
    case retryingOnCPU
}

public struct TranscriptionProgressEvent: Sendable, Equatable {
    public var phase: TranscriptionProgressPhase
    public var modelID: String
    public var elapsedMS: Int

    public init(phase: TranscriptionProgressPhase, modelID: String, elapsedMS: Int) {
        self.phase = phase
        self.modelID = modelID
        self.elapsedMS = elapsedMS
    }
}

public struct TranscriptionRequest: Sendable {
    public var audioFileURL: URL
    public var modelID: String
    public var language: String
    public var progressHandler: (@Sendable (TranscriptionProgressEvent) -> Void)?

    public init(
        audioFileURL: URL,
        modelID: String,
        language: String = "en",
        progressHandler: (@Sendable (TranscriptionProgressEvent) -> Void)? = nil
    ) {
        self.audioFileURL = audioFileURL
        self.modelID = modelID
        self.language = language
        self.progressHandler = progressHandler
    }
}

public struct TranscriptionResult: Sendable {
    public var text: String
    public var latencyMS: Int

    public init(text: String, latencyMS: Int) {
        self.text = text
        self.latencyMS = latencyMS
    }
}

public enum TranscriptionError: Error {
    case providerUnavailable
    case modelMissing(String)
    case noSpeechDetected
    case executionFailed(String)
    case timedOut(seconds: Int)
}

extension TranscriptionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "whisper-cli is not available."
        case let .modelMissing(modelID):
            return "Whisper model '\(modelID)' is not installed."
        case .noSpeechDetected:
            return "No speech was detected. Try again and speak a little longer."
        case let .executionFailed(message):
            return message
        case let .timedOut(seconds):
            return "Transcription timed out after \(seconds)s. Try a shorter clip or a smaller model."
        }
    }
}

public protocol TranscriptionProvider: Sendable {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult
}
