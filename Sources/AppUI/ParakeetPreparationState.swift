import Foundation
import TranscriptionCore

enum ParakeetPreloadPolicy {
    static func shouldPreload(selectedModelID: String, isParakeetAvailable: Bool) -> Bool {
        isParakeetAvailable && selectedModelID == TranscriptionModelID.parakeetV3
    }
}

enum ParakeetPreparationPhase: Equatable, Sendable {
    case downloading
    case optimizing
}

struct ParakeetPreparationProgress: Equatable, Sendable {
    var fractionCompleted: Double?
    var phase: ParakeetPreparationPhase

    init(fractionCompleted: Double?, phase: ParakeetPreparationPhase) {
        self.fractionCompleted = fractionCompleted
        self.phase = phase
    }

    init(_ progress: ModelPreparationProgress) {
        fractionCompleted = progress.fractionCompleted
        phase = switch progress.phase {
        case .checkingCache, .downloading:
            .downloading
        case .optimizing:
            .optimizing
        }
    }
}

enum ParakeetPreparationEvent: Equatable, Sendable {
    case started
    case progress(ParakeetPreparationProgress)
    case ready
    case failed(String)
}

struct ParakeetPreparationState: Equatable, Sendable {
    private enum Storage: Equatable, Sendable {
        case idle
        case preparing(ParakeetPreparationProgress?)
        case ready
        case failed(String)
    }

    private var storage: Storage = .idle

    var isPreparing: Bool {
        if case .preparing = storage { return true }
        return false
    }

    var isReady: Bool {
        if case .ready = storage { return true }
        return false
    }

    var failureMessage: String? {
        if case let .failed(message) = storage { return message }
        return nil
    }

    var statusText: String? {
        switch storage {
        case .idle, .ready:
            nil
        case .preparing(nil):
            "Preparing Parakeet..."
        case let .preparing(.some(progress)):
            "Preparing Parakeet: \(Self.label(for: progress, includePercent: true))"
        case let .failed(message):
            "Parakeet setup failed: \(message)"
        }
    }

    var modelRowProgressText: String? {
        switch storage {
        case .idle, .ready:
            nil
        case .preparing(nil):
            "Setting up"
        case let .preparing(.some(progress)):
            Self.label(for: progress, includePercent: true)
        case let .failed(message):
            "Setup failed: \(message)"
        }
    }

    mutating func apply(_ event: ParakeetPreparationEvent) {
        switch event {
        case .started:
            storage = .preparing(nil)
        case let .progress(progress):
            storage = .preparing(progress)
        case .ready:
            storage = .ready
        case let .failed(message):
            storage = .failed(message)
        }
    }

    private static func label(for progress: ParakeetPreparationProgress, includePercent: Bool) -> String {
        switch progress.phase {
        case .downloading:
            guard includePercent, let fraction = progress.fractionCompleted else {
                return "Downloading model"
            }
            let percent = Int((max(0, min(1, fraction)) * 100).rounded())
            return "Downloading model \(percent)%"
        case .optimizing:
            return "Optimizing for your Mac"
        }
    }
}

enum ParakeetDictationReadiness: Equatable {
    case ready
    case notReady(message: String)

    static func evaluate(
        selectedModelID: String,
        isParakeetAvailable: Bool,
        preparationState: ParakeetPreparationState
    ) -> ParakeetDictationReadiness {
        guard ParakeetPreloadPolicy.shouldPreload(
            selectedModelID: selectedModelID,
            isParakeetAvailable: isParakeetAvailable
        ) else {
            return .ready
        }
        if preparationState.isReady {
            return .ready
        }
        return .notReady(message: "Parakeet is still setting up — ready shortly")
    }
}
