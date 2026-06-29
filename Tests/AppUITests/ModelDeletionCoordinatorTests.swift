@testable import AppUI
import TranscriptionCore
import XCTest

final class ModelDeletionCoordinatorTests: XCTestCase {
    func testDeletingParakeetUsesCacheClearResetsPreparationAndFallsBackToWhisper() throws {
        let whisperStore = SpyWhisperModelStore(installedIDs: ["ggml-small.en"])
        let parakeetCache = SpyParakeetCache(exists: true, sizeBytes: 461 * 1024 * 1024)

        let target = try XCTUnwrap(
            ModelDeletionCoordinator.target(
                selectedModelID: TranscriptionModelID.parakeetV3,
                whisperStore: whisperStore,
                parakeetCache: parakeetCache
            )
        )

        XCTAssertEqual(target.storage, .parakeetCache)
        XCTAssertEqual(target.displayName, "Parakeet v3")
        XCTAssertEqual(target.sizeNote, " (461 MB)")

        let result = try ModelDeletionCoordinator.deleteTarget(
            target,
            whisperStore: whisperStore,
            parakeetCache: parakeetCache
        )

        XCTAssertEqual(parakeetCache.deletedCount, 1)
        XCTAssertEqual(whisperStore.deletedIDs, [])
        XCTAssertTrue(result.resetParakeetPreparation)
        XCTAssertEqual(result.fallbackModelID, "ggml-small.en")
    }
}

private final class SpyWhisperModelStore: WhisperModelDeletionStore {
    var installedIDs: [String]
    var deletedIDs: [String] = []

    init(installedIDs: [String]) {
        self.installedIDs = installedIDs
    }

    func whisperModelExists(id: String) -> Bool {
        installedIDs.contains(id)
    }

    func whisperModelSizeBytes(id _: String) -> Int64? {
        nil
    }

    func installedWhisperModelIDs() -> [String] {
        installedIDs
    }

    func deleteWhisperModel(id: String) throws {
        deletedIDs.append(id)
        installedIDs.removeAll { $0 == id }
    }
}

private final class SpyParakeetCache: ParakeetModelCacheStore {
    var exists: Bool
    var sizeBytes: Int64?
    var deletedCount = 0

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
        deletedCount += 1
        exists = false
        sizeBytes = nil
    }
}
