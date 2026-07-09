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
        XCTAssertEqual(rows[0].statusText, "Removed")
        XCTAssertTrue(rows[1].isInstalled)
        XCTAssertTrue(rows[1].isSelected)
    }

    func testCatalogBuildResolvesWhisperIdentityFromSingleDirectorySnapshot() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrawl-catalog-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let downloadable = try XCTUnwrap(LocalModelManager.downloadableModels.first)
        FileManager.default.createFile(
            atPath: tempDir.appendingPathComponent("\(downloadable.id).bin").path,
            contents: Data("stub".utf8)
        )

        let manager = LocalModelManager(modelsDirectoryURL: tempDir)
        let catalog = ModelCatalog(
            manager: manager,
            retainingProvider: nil,
            languageProvider: { "en" },
            preparationProgressProvider: { nil }
        )

        let models = catalog.availableModels // one build = one directory listing
        try FileManager.default.removeItem(at: tempDir) // a re-scan would now find nothing

        let whisper = try XCTUnwrap(models.first { $0.id == downloadable.id })
        XCTAssertTrue(
            whisper.installState.isInstalled,
            "identity/install resolution must use the build-time snapshot, not re-scan the directory"
        )
    }

    #if arch(arm64)
        func testParakeetManagedModelDeleteClearsCacheAndShutdownsProvider() async throws {
            let cache = SpyParakeetCacheStore(exists: true, isComplete: true, sizeBytes: 461 * 1024 * 1024)
            let provider = SpyRetainingProvider()
            let model = ParakeetManagedModel(cacheStore: cache, provider: provider)
            let catalog = ModelCatalog(models: [model])

            XCTAssertEqual(model.installState, .installed(sizeBytes: nil))
            XCTAssertEqual(cache.sizeCallCount, 0)
            XCTAssertEqual(
                catalog.deletionTarget(selectedModelID: TranscriptionModelID.parakeetV3)?.sizeNote,
                " (461 MB)"
            )
            XCTAssertEqual(cache.sizeCallCount, 1)

            try await model.delete()

            XCTAssertEqual(cache.deleteCallCount, 1)
            XCTAssertFalse(cache.exists)
            XCTAssertEqual(provider.shutdownModelIDs, [TranscriptionModelID.parakeetV3])
            XCTAssertEqual(model.installState, .notInstalled)
        }

        func testCachedParakeetStaysInstalledInPreferenceRowsWhilePreparationIsInProgress() throws {
            let cache = SpyParakeetCacheStore(exists: true, isComplete: true, sizeBytes: 461 * 1024 * 1024)
            let model = ParakeetManagedModel(
                cacheStore: cache,
                provider: nil,
                preparationProgressProvider: {
                    ManagedModelPreparationProgress(displayText: "Preparing")
                }
            )

            let rows = PreferencesModelState.rows(
                models: [model],
                selectedModelID: TranscriptionModelID.parakeetV3,
                downloadingModelID: nil
            )

            let row = try XCTUnwrap(rows.first)
            XCTAssertTrue(row.isInstalled, "Cached Parakeet must stay in Installed Models while it loads")
            XCTAssertFalse(row.isPreparing)
            XCTAssertEqual(row.statusText, "Recommended")
        }

        func testCachedParakeetPreferenceRefreshDoesNotMeasureCacheSize() throws {
            let cache = SpyParakeetCacheStore(exists: true, isComplete: true, sizeBytes: 461 * 1024 * 1024)
            let model = ParakeetManagedModel(cacheStore: cache, provider: nil)
            let catalog = ModelCatalog(models: [model])

            XCTAssertTrue(catalog.isInstalled(modelID: TranscriptionModelID.parakeetV3))
            let rows = PreferencesModelState.rows(
                models: catalog.availableModels,
                selectedModelID: TranscriptionModelID.parakeetV3,
                downloadingModelID: nil
            )

            XCTAssertTrue(try XCTUnwrap(rows.first).isInstalled)
            XCTAssertEqual(cache.sizeCallCount, 0)
        }

        func testCanDeleteModelDoesNotMeasureParakeetCacheSize() {
            let cache = SpyParakeetCacheStore(exists: true, isComplete: true, sizeBytes: 461 * 1024 * 1024)
            let model = ParakeetManagedModel(cacheStore: cache, provider: nil)
            let notInstalled = StubManagedModel(
                id: "ggml-small.en",
                displayName: "small.en",
                state: .notInstalled
            )
            let catalog = ModelCatalog(models: [model, notInstalled])

            XCTAssertTrue(catalog.canDeleteModel(selectedModelID: TranscriptionModelID.parakeetV3))
            XCTAssertFalse(catalog.canDeleteModel(selectedModelID: "ggml-small.en"))
            XCTAssertFalse(catalog.canDeleteModel(selectedModelID: "ggml-nonexistent"))
            XCTAssertEqual(cache.sizeCallCount, 0, "menu enablement must never walk the cache directory")
        }

        func testIncompleteParakeetCacheDoesNotRenderInstalled() throws {
            let cache = SpyParakeetCacheStore(exists: true, isComplete: false, sizeBytes: 32 * 1024 * 1024)
            let model = ParakeetManagedModel(cacheStore: cache, provider: nil)
            let catalog = ModelCatalog(models: [model])

            XCTAssertFalse(catalog.isInstalled(modelID: TranscriptionModelID.parakeetV3))
            XCTAssertNil(model.installedSizeBytes)

            let rows = PreferencesModelState.rows(
                models: catalog.availableModels,
                selectedModelID: "ggml-small.en",
                downloadingModelID: nil
            )
            let row = try XCTUnwrap(rows.first)
            XCTAssertFalse(row.isInstalled)
            XCTAssertTrue(row.canDownload)
        }

        func testCompleteParakeetCacheRendersInstalled() throws {
            let cache = SpyParakeetCacheStore(exists: true, isComplete: true, sizeBytes: 461 * 1024 * 1024)
            let model = ParakeetManagedModel(cacheStore: cache, provider: nil)
            let catalog = ModelCatalog(models: [model])

            XCTAssertTrue(catalog.isInstalled(modelID: TranscriptionModelID.parakeetV3))
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
        var isComplete: Bool
        var sizeBytes: Int64?
        private(set) var deleteCallCount = 0
        private(set) var sizeCallCount = 0

        init(exists: Bool, isComplete: Bool, sizeBytes: Int64?) {
            self.exists = exists
            self.isComplete = isComplete
            self.sizeBytes = sizeBytes
        }

        func parakeetCacheExists() -> Bool {
            exists
        }

        func parakeetCacheIsComplete() -> Bool {
            isComplete
        }

        func parakeetCacheSizeBytes() -> Int64? {
            sizeCallCount += 1
            return sizeBytes
        }

        func deleteParakeetCache() throws {
            deleteCallCount += 1
            exists = false
            isComplete = false
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
