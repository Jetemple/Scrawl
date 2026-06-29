import Foundation
import TranscriptionCore

enum ParakeetPreparationPhase: Equatable, Sendable {
    case checkingCache
    case downloading
    case optimizing
}

struct ParakeetPreparationProgress: Equatable, Sendable {
    var fractionCompleted: Double?
    var phase: ParakeetPreparationPhase

    init(fractionCompleted: Double?, phase: ParakeetPreparationPhase) {
        self.fractionCompleted = fractionCompleted.map { max(0, min(1, $0)) }
        self.phase = phase
    }

    init(_ progress: ModelPreparationProgress) {
        phase = switch progress.phase {
        case .checkingCache:
            .checkingCache
        case .downloading:
            .downloading
        case .optimizing:
            .optimizing
        }
        fractionCompleted = phase == .downloading
            ? progress.fractionCompleted.map { max(0, min(1, $0)) }
            : nil
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
    private var maxDownloadFraction: Double?
    private var hasMovedPastDownload = false

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
            "Setting up Parakeet (one-time)…"
        case let .preparing(.some(progress)):
            Self.label(for: progress, includePercent: true)
        case let .failed(message):
            "Parakeet setup failed: \(message)"
        }
    }

    var modelRowProgressText: String? {
        switch storage {
        case .idle, .ready:
            nil
        case .preparing(nil):
            "Preparing"
        case let .preparing(.some(progress)):
            switch progress.phase {
            case .downloading:
                Self.label(for: progress, includePercent: true)
            case .checkingCache, .optimizing:
                "Preparing"
            }
        case let .failed(message):
            "Setup failed: \(message)"
        }
    }

    mutating func apply(_ event: ParakeetPreparationEvent) {
        switch event {
        case .started:
            maxDownloadFraction = nil
            hasMovedPastDownload = false
            storage = .preparing(nil)
        case let .progress(progress):
            apply(progress)
        case .ready:
            maxDownloadFraction = 1
            hasMovedPastDownload = true
            storage = .ready
        case let .failed(message):
            storage = .failed(message)
        }
    }

    private mutating func apply(_ progress: ParakeetPreparationProgress) {
        switch progress.phase {
        case .checkingCache:
            storage = .preparing(progress)
        case .downloading:
            guard let fraction = progress.fractionCompleted else {
                storage = .preparing(nil)
                return
            }
            guard !hasMovedPastDownload else {
                return
            }
            let monotonicFraction = max(maxDownloadFraction ?? 0, fraction)
            maxDownloadFraction = monotonicFraction
            storage = .preparing(
                ParakeetPreparationProgress(
                    fractionCompleted: monotonicFraction,
                    phase: .downloading
                )
            )
        case .optimizing:
            if maxDownloadFraction != nil {
                hasMovedPastDownload = true
            }
            storage = .preparing(
                ParakeetPreparationProgress(
                    fractionCompleted: nil,
                    phase: .optimizing
                )
            )
        }
    }

    private static func label(for progress: ParakeetPreparationProgress, includePercent: Bool) -> String {
        switch progress.phase {
        case .checkingCache:
            return "Loading Parakeet…"
        case .downloading:
            guard includePercent, let fraction = progress.fractionCompleted else {
                return "Downloading Parakeet model"
            }
            let percent = Int((max(0, min(1, fraction)) * 100).rounded())
            return "Downloading Parakeet model — \(percent)%"
        case .optimizing:
            return "Optimizing Parakeet for your Mac…"
        }
    }
}

enum ParakeetDictationReadiness: Equatable {
    case ready
    case notReady(message: String)

    static func evaluate(
        preparationState: ParakeetPreparationState
    ) -> ParakeetDictationReadiness {
        if preparationState.isReady {
            return .ready
        }
        return .notReady(message: "Parakeet is still setting up. Pick another model to use now, or wait a moment.")
    }
}
