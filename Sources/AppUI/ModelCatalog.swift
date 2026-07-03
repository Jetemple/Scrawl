import Foundation
import TranscriptionCore

struct ModelDeletionTarget: Equatable {
    let modelID: String
    let displayName: String
    let isBuiltIn: Bool
    let sizeNote: String
}

struct ModelDeletionResult: Equatable {
    let deletedModelID: String?
    let fallbackModelID: String?
}

final class ModelCatalog: @unchecked Sendable {
    static let parakeetModelID = TranscriptionModelID.parakeetV3

    private let modelsProvider: @Sendable () -> [any ManagedModel]

    init(models: [any ManagedModel]) {
        modelsProvider = { models }
    }

    init(
        manager: LocalModelManager,
        retainingProvider: (any ModelRetainingTranscriptionProvider)?,
        languageProvider: @escaping @Sendable () -> String,
        preparationProgressProvider: @escaping @Sendable () -> ManagedModelPreparationProgress?
    ) {
        modelsProvider = {
            var models: [any ManagedModel] = []
            #if arch(arm64)
            models.append(
                ParakeetManagedModel(
                    cacheStore: LiveParakeetModelCacheStore(),
                    provider: retainingProvider,
                    languageProvider: languageProvider,
                    preparationProgressProvider: preparationProgressProvider
                )
            )
            #endif

            let downloadableModels = LocalModelManager.downloadableModels.map {
                WhisperGgmlModel(downloadableModel: $0, manager: manager)
            }
            models.append(contentsOf: downloadableModels)

            let knownFamilies = Set(LocalModelManager.downloadableModels.map {
                PreferencesModelState.canonicalFamily($0.id)
            })
            let knownIDs = Set(LocalModelManager.downloadableModels.map(\.id))
            let customModels = manager.installedModelIDs()
                .filter { !knownIDs.contains($0) && !knownFamilies.contains(PreferencesModelState.canonicalFamily($0)) }
                .sorted()
                .map { WhisperGgmlModel(installedModelID: $0, manager: manager) }
            models.append(contentsOf: customModels)
            return models
        }
    }

    var availableModels: [any ManagedModel] {
        modelsProvider().filter(\.isAvailable)
    }

    func model(id modelID: String) -> (any ManagedModel)? {
        availableModels.first { $0.id == modelID }
    }

    func installedModelIDs() -> [String] {
        availableModels
            .filter { $0.installState.isInstalled }
            .map(\.id)
    }

    func isInstalled(modelID: String) -> Bool {
        model(id: modelID)?.installState.isInstalled == true
    }

    func preparesOnSelection(modelID: String) -> Bool {
        model(id: modelID)?.preparesOnSelection == true
    }

    func deletionTarget(selectedModelID: String) -> ModelDeletionTarget? {
        guard let model = model(id: selectedModelID),
              model.installState.isInstalled
        else {
            return nil
        }

        return ModelDeletionTarget(
            modelID: model.id,
            displayName: model.displayName,
            isBuiltIn: isBuiltIn(modelID: model.id),
            sizeNote: Self.sizeNote(for: model.installedSizeBytes)
        )
    }

    func delete(_ target: ModelDeletionTarget) async throws -> ModelDeletionResult {
        try await deleteModel(id: target.modelID)
    }

    func deleteModel(id modelID: String) async throws -> ModelDeletionResult {
        guard let model = model(id: modelID), model.installState.isInstalled else {
            return ModelDeletionResult(deletedModelID: nil, fallbackModelID: nil)
        }

        try await model.delete()
        let fallback = installedModelIDs().first { $0 != modelID }
        return ModelDeletionResult(deletedModelID: modelID, fallbackModelID: fallback)
    }

    func resolveRecommendedDefaultModelID(
        preferredModelID: String,
        deletedModelIDs: Set<String> = []
    ) -> String {
        let available = availableModels
        if !deletedModelIDs.contains(preferredModelID),
           available.contains(where: { $0.id == preferredModelID && $0.isAvailable })
        {
            return preferredModelID
        }

        if let installed = available.first(where: { $0.installState.isInstalled && !deletedModelIDs.contains($0.id) }) {
            return installed.id
        }

        return available.first(where: { !deletedModelIDs.contains($0.id) })?.id ?? ""
    }

    private func isBuiltIn(modelID: String) -> Bool {
        modelID == Self.parakeetModelID || LocalModelManager.downloadableModels.contains { model in
            model.id == modelID || PreferencesModelState.canonicalFamily(model.id) == PreferencesModelState.canonicalFamily(modelID)
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
