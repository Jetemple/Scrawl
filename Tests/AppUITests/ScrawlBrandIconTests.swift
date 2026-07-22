import AppKit
@testable import AppUI
import XCTest

final class ScrawlBrandIconTests: XCTestCase {
    /// Regression: image() once read `Bundle.module`, whose generated accessor
    /// traps with a fatalError when the resource bundle is missing. A
    /// `make install` .app ships no resource bundle, so opening Preferences
    /// (About page → image()) crashed the app. It must resolve to a usable image
    /// without trapping, whether or not the bundle is present.
    @MainActor
    func testImageReturnsUsableImageWithoutTrapping() {
        let image = ScrawlBrandIcon.image()
        XCTAssertTrue(image.isValid)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }
}
