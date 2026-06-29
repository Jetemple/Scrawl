import Foundation
import ParakeetProvider
import TranscriptionCore

struct ManagedModelPreparationProgress: Equatable, Sendable {
    var progress: ModelPreparationProgress?
    var displayText: String?

    init(progress: ModelPreparationProgress? = nil, displayText: String? = nil) {
        self.progress = progress
        self.displayText = displayText
    }
}

enum ManagedModelInstallState: Equatable, Sendable {
    case notInstalled
    case preparing(ManagedModelPreparationProgress?)
    case installed(sizeBytes: Int64?)

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }

    var installedSizeBytes: Int64? {
        if case let .installed(sizeBytes) = self { return sizeBytes }
        return nil
    }
}

protocol ManagedModel: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isAvailable: Bool { get }
    var installState: ManagedModelInstallState { get }
    var preparesOnSelection: Bool { get }

    func prepare(progressHandler: ModelPreparationProgressHandler?) async throws
    func delete() async throws
}

extension ManagedModel {
    var preparesOnSelection: Bool { false }
}

protocol ParakeetModelCacheStore: Sendable {
    func parakeetCacheExists() -> Bool
    func parakeetCacheSizeBytes() -> Int64?
    func deleteParakeetCache() throws
}

final class WhisperGgmlModel: ManagedModel, @unchecked Sendable {
    private let manager: LocalModelManager
    private let downloadableModel: DownloadableModel?
    private let customModelID: String?

    init(downloadableModel: DownloadableModel, manager: LocalModelManager) {
        self.downloadableModel = downloadableModel
        customModelID = nil
        self.manager = manager
    }

    init(installedModelID: String, manager: LocalModelManager) {
        downloadableModel = nil
        customModelID = installedModelID
        self.manager = manager
    }

    var id: String {
        if let downloadableModel {
            return manager.resolvedInstalledModelID(for: downloadableModel) ?? downloadableModel.id
        }
        return customModelID ?? ""
    }

    var displayName: String {
        if let downloadableModel {
            return downloadableModel.displayName
        }
        return PreferencesModelState.displayName(forInstalledModelID: id)
    }

    var isAvailable: Bool { true }

    var installState: ManagedModelInstallState {
        if let downloadableModel {
            guard let installedID = manager.resolvedInstalledModelID(for: downloadableModel) else {
                return .notInstalled
            }
            return .installed(sizeBytes: manager.modelSizeBytes(id: installedID))
        }

        guard manager.modelExists(id: id) else {
            return .notInstalled
        }
        return .installed(sizeBytes: manager.modelSizeBytes(id: id))
    }

    func prepare(progressHandler: ModelPreparationProgressHandler?) async throws {
        guard let downloadableModel else { return }
        _ = try await manager.download(model: downloadableModel) { receivedBytes, totalBytes in
            let fraction: Double?
            if let totalBytes, totalBytes > 0 {
                fraction = max(0, min(1, Double(receivedBytes) / Double(totalBytes)))
            } else {
                fraction = nil
            }
            progressHandler?(ModelPreparationProgress(fractionCompleted: fraction, phase: .downloading))
        }
    }

    func delete() async throws {
        try manager.deleteModel(id: id)
    }
}

#if arch(arm64)
final class ParakeetManagedModel: ManagedModel, @unchecked Sendable {
    private let cacheStore: ParakeetModelCacheStore
    private let provider: (any ModelRetainingTranscriptionProvider)?
    private let languageProvider: @Sendable () -> String
    private let preparationProgressProvider: @Sendable () -> ManagedModelPreparationProgress?

    init(
        cacheStore: ParakeetModelCacheStore,
        provider: (any ModelRetainingTranscriptionProvider)?,
        languageProvider: @escaping @Sendable () -> String = { "en" },
        preparationProgressProvider: @escaping @Sendable () -> ManagedModelPreparationProgress? = { nil }
    ) {
        self.cacheStore = cacheStore
        self.provider = provider
        self.languageProvider = languageProvider
        self.preparationProgressProvider = preparationProgressProvider
    }

    var id: String { TranscriptionModelID.parakeetV3 }
    var displayName: String { "Parakeet v3 — recommended" }
    var isAvailable: Bool { true }
    var preparesOnSelection: Bool { true }

    var installState: ManagedModelInstallState {
        if let progress = preparationProgressProvider() {
            return .preparing(progress)
        }
        guard cacheStore.parakeetCacheExists() else {
            return .notInstalled
        }
        return .installed(sizeBytes: cacheStore.parakeetCacheSizeBytes())
    }

    func prepare(progressHandler: ModelPreparationProgressHandler?) async throws {
        guard let provider else {
            throw TranscriptionError.providerUnavailable
        }
        try await provider.prepareModel(
            modelID: id,
            language: languageProvider(),
            progressHandler: progressHandler
        )
    }

    func delete() async throws {
        await provider?.shutdown(modelID: id)
        try cacheStore.deleteParakeetCache()
    }
}
#endif
