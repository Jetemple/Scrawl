import Foundation
import TranscriptionCore

protocol WhisperModelDeletionStore {
    func whisperModelExists(id: String) -> Bool
    func whisperModelSizeBytes(id: String) -> Int64?
    func installedWhisperModelIDs() -> [String]
    func deleteWhisperModel(id: String) throws
}

protocol ParakeetModelCacheStore {
    func parakeetCacheExists() -> Bool
    func parakeetCacheSizeBytes() -> Int64?
    func deleteParakeetCache() throws
}

struct ModelDeletionTarget: Equatable {
    enum Storage: Equatable {
        case whisperModel(id: String)
        case parakeetCache
    }

    let modelID: String
    let storage: Storage
    let displayName: String
    let isBuiltIn: Bool
    let sizeNote: String
}

struct ModelDeletionResult: Equatable {
    let fallbackModelID: String?
    let resetParakeetPreparation: Bool
}

enum ModelDeletionCoordinator {
    static func target(
        selectedModelID: String,
        whisperStore: WhisperModelDeletionStore,
        parakeetCache: ParakeetModelCacheStore
    ) -> ModelDeletionTarget? {
        if selectedModelID == LocalModelManager.parakeetModelID {
            guard parakeetCache.parakeetCacheExists() else {
                return nil
            }
            return ModelDeletionTarget(
                modelID: selectedModelID,
                storage: .parakeetCache,
                displayName: PreferencesModelState.displayName(forInstalledModelID: selectedModelID),
                isBuiltIn: true,
                sizeNote: sizeNote(for: parakeetCache.parakeetCacheSizeBytes())
            )
        }

        guard whisperStore.whisperModelExists(id: selectedModelID) else {
            return nil
        }

        let catalogModel = LocalModelManager.downloadableModels.first { $0.id == selectedModelID }
        let displayName = catalogModel?.displayName
            ?? PreferencesModelState.displayName(forInstalledModelID: selectedModelID)

        return ModelDeletionTarget(
            modelID: selectedModelID,
            storage: .whisperModel(id: selectedModelID),
            displayName: displayName,
            isBuiltIn: catalogModel != nil,
            sizeNote: sizeNote(for: whisperStore.whisperModelSizeBytes(id: selectedModelID))
        )
    }

    static func deleteTarget(
        _ target: ModelDeletionTarget,
        whisperStore: WhisperModelDeletionStore,
        parakeetCache: ParakeetModelCacheStore
    ) throws -> ModelDeletionResult {
        switch target.storage {
        case let .whisperModel(id):
            try whisperStore.deleteWhisperModel(id: id)
            return ModelDeletionResult(
                fallbackModelID: whisperStore.installedWhisperModelIDs().first,
                resetParakeetPreparation: false
            )
        case .parakeetCache:
            try parakeetCache.deleteParakeetCache()
            return ModelDeletionResult(
                fallbackModelID: whisperStore.installedWhisperModelIDs().first,
                resetParakeetPreparation: true
            )
        }
    }

    private static func sizeNote(for bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else {
            return ""
        }
        let mb = Double(bytes) / (1024 * 1024)
        return " (\(String(format: "%.0f", mb)) MB)"
    }
}
