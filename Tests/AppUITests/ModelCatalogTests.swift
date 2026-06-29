@testable import AppUI
import Foundation
import TranscriptionCore
import XCTest

final class ModelCatalogTests: XCTestCase {
    func testDefaultResolutionPrefersParakeetOnFreshArm64ButSkipsDeletedParakeet() {
        let parakeet = StubManagedModel(
            id: TranscriptionModelID.parakeetV3,
            displayName: "Parakeet v3",
            state: .notInstalled
        )
        let whisper = StubManagedModel(
            id: "ggml-small.en",
            displayName: "small.en",
            state: .installed(sizeBytes: 466 * 1024 * 1024)
        )
        let catalog = ModelCatalog(models: [parakeet, whisper])

        XCTAssertEqual(
            catalog.resolveRecommendedDefaultModelID(preferredModelID: TranscriptionModelID.parakeetV3),
            TranscriptionModelID.parakeetV3
        )
        XCTAssertEqual(
            catalog.resolveRecommendedDefaultModelID(
                preferredModelID: TranscriptionModelID.parakeetV3,
                deletedModelIDs: [TranscriptionModelID.parakeetV3]
            ),
            "ggml-small.en"
        )
    }

    func testDeletingParakeetClearsInstallStateInvokesShutdownAndFallsBackToWhisper() async throws {
        let parakeet = StubManagedModel(
            id: TranscriptionModelID.parakeetV3,
            displayName: "Parakeet v3",
            state: .installed(sizeBytes: 461 * 1024 * 1024)
        )
        let whisper = StubManagedModel(
            id: "ggml-small.en",
            displayName: "small.en",
            state: .installed(sizeBytes: 466 * 1024 * 1024)
        )
        let catalog = ModelCatalog(models: [parakeet, whisper])

        let target = try XCTUnwrap(catalog.deletionTarget(selectedModelID: TranscriptionModelID.parakeetV3))
        XCTAssertEqual(target.sizeNote, " (461 MB)")

        let result = try await catalog.delete(target)

        XCTAssertEqual(result.deletedModelID, TranscriptionModelID.parakeetV3)
        XCTAssertEqual(result.fallbackModelID, "ggml-small.en")
        XCTAssertEqual(parakeet.deleteCallCount, 1)
        XCTAssertEqual(parakeet.installState, .notInstalled)
        XCTAssertEqual(
            catalog.resolveRecommendedDefaultModelID(
                preferredModelID: TranscriptionModelID.parakeetV3,
                deletedModelIDs: Set([result.deletedModelID].compactMap { $0 })
            ),
            "ggml-small.en"
        )
    }

    func testDeletingNotInstalledModelIsCleanNoOp() async throws {
        let parakeet = StubManagedModel(
            id: TranscriptionModelID.parakeetV3,
            displayName: "Parakeet v3",
            state: .notInstalled
        )
        let catalog = ModelCatalog(models: [parakeet])

        XCTAssertNil(catalog.deletionTarget(selectedModelID: TranscriptionModelID.parakeetV3))
        let result = try await catalog.deleteModel(id: TranscriptionModelID.parakeetV3)

        XCTAssertNil(result.deletedModelID)
        XCTAssertNil(result.fallbackModelID)
        XCTAssertEqual(parakeet.deleteCallCount, 0)
    }

    func testPreferenceRowsUseManagedInstallStateForParakeet() {
        let parakeet = StubManagedModel(
            id: TranscriptionModelID.parakeetV3,
            displayName: "Parakeet v3",
            state: .notInstalled
        )
        let whisper = StubManagedModel(
            id: "ggml-small.en",
            displayName: "small.en",
            state: .installed(sizeBytes: 466 * 1024 * 1024)
        )
        let catalog = ModelCatalog(models: [parakeet, whisper])

        let rows = PreferencesModelState.rows(
            models: catalog.availableModels,
            selectedModelID: "ggml-small.en",
            downloadingModelID: nil
        )

        XCTAssertEqual(rows.map(\.id), [TranscriptionModelID.parakeetV3, "ggml-small.en"])
        XCTAssertFalse(rows[0].isInstalled)
        XCTAssertTrue(rows[0].canDownload)
        XCTAssertEqual(rows[0].statusText, "Available")
        XCTAssertTrue(rows[1].isInstalled)
        XCTAssertTrue(rows[1].isSelected)
    }

    #if arch(arm64)
    func testParakeetManagedModelDeleteClearsCacheAndShutdownsProvider() async throws {
        let cache = SpyParakeetCacheStore(exists: true, sizeBytes: 461 * 1024 * 1024)
        let provider = SpyRetainingProvider()
        let model = ParakeetManagedModel(cacheStore: cache, provider: provider)

        XCTAssertEqual(model.installState, .installed(sizeBytes: 461 * 1024 * 1024))

        try await model.delete()

        XCTAssertEqual(cache.deleteCallCount, 1)
        XCTAssertFalse(cache.exists)
        XCTAssertEqual(provider.shutdownModelIDs, [TranscriptionModelID.parakeetV3])
        XCTAssertEqual(model.installState, .notInstalled)
    }
    #endif
}

private final class StubManagedModel: ManagedModel, @unchecked Sendable {
    let id: String
    let displayName: String
    let isAvailable: Bool
    var installState: ManagedModelInstallState
    private(set) var deleteCallCount = 0

    init(
        id: String,
        displayName: String,
        isAvailable: Bool = true,
        state: ManagedModelInstallState
    ) {
        self.id = id
        self.displayName = displayName
        self.isAvailable = isAvailable
        installState = state
    }

    func prepare(progressHandler _: ModelPreparationProgressHandler?) async throws {
        installState = .installed(sizeBytes: nil)
    }

    func delete() async throws {
        deleteCallCount += 1
        installState = .notInstalled
    }
}

#if arch(arm64)
private final class SpyParakeetCacheStore: ParakeetModelCacheStore, @unchecked Sendable {
    var exists: Bool
    var sizeBytes: Int64?
    private(set) var deleteCallCount = 0

    init(exists: Bool, sizeBytes: Int64?) {
        self.exists = exists
        self.sizeBytes = sizeBytes
    }

    func parakeetCacheExists() -> Bool {
        exists
    }

    func parakeetCacheSizeBytes() -> Int64? {
        sizeBytes
    }

    func deleteParakeetCache() throws {
        deleteCallCount += 1
        exists = false
        sizeBytes = nil
    }
}

private final class SpyRetainingProvider: ModelRetainingTranscriptionProvider, @unchecked Sendable {
    private(set) var shutdownModelIDs: [String] = []

    func transcribe(_: TranscriptionRequest) async throws -> TranscriptionResult {
        TranscriptionResult(text: "", latencyMS: 0)
    }

    func warmUp(modelID _: String, language _: String) async {}

    func prepareModel(
        modelID _: String,
        language _: String,
        progressHandler _: ModelPreparationProgressHandler?
    ) async throws {}

    func setIdleOffloadSeconds(_: TimeInterval?) async {}

    func shutdown(modelID: String) async {
        shutdownModelIDs.append(modelID)
    }

    func shutdown() async {}
}
#endif
