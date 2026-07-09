import Foundation
import ParakeetProvider

struct LiveParakeetModelCacheStore: ParakeetModelCacheStore {
    func parakeetCacheExists() -> Bool {
        #if arch(arm64)
            return ParakeetTranscriptionProvider.parakeetV3CacheExists()
        #else
            return false
        #endif
    }

    func parakeetCacheIsComplete() -> Bool {
        #if arch(arm64)
            return ParakeetTranscriptionProvider.parakeetV3CacheIsComplete()
        #else
            return false
        #endif
    }

    func parakeetCacheSizeBytes() -> Int64? {
        #if arch(arm64)
            return ParakeetTranscriptionProvider.parakeetV3CacheSizeBytes()
        #else
            return nil
        #endif
    }

    func deleteParakeetCache() throws {
        #if arch(arm64)
            _ = try ParakeetTranscriptionProvider.deleteParakeetV3Cache()
        #endif
    }
}
