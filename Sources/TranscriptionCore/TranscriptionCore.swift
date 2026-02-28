import Foundation

public struct TranscriptionRequest: Sendable {
    public var audioFileURL: URL
    public var modelID: String
    public var language: String

    public init(audioFileURL: URL, modelID: String, language: String = "en") {
        self.audioFileURL = audioFileURL
        self.modelID = modelID
        self.language = language
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
    case executionFailed(String)
}

public protocol TranscriptionProvider: Sendable {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult
}
