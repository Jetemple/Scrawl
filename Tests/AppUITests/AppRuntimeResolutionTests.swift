@testable import AppUI
import XCTest

final class AppRuntimeResolutionTests: XCTestCase {
    func testRecommendedDefaultModelIsLightweightEnglishForFastOnboarding() {
        // First-run onboarding should recommend the small English model regardless of GPU:
        // it is far smaller than `medium` and the app's language is English-only today, so the
        // multilingual `medium` model would be strictly heavier/slower with no benefit.
        XCTAssertEqual(AppRuntime.resolveRecommendedDefaultModelID(), "ggml-small.en")
    }
}
