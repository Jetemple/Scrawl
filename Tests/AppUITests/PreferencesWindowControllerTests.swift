import AppKit
@testable import AppUI
import XCTest

final class PreferencesWindowControllerTests: XCTestCase {
    @MainActor
    func testSidebarContainsExpectedSections() {
        XCTAssertEqual(
            PreferencesWindowController.Section.allCases.map(\.title),
            ["General", "Models", "Keyboard", "History", "Dictionary", "About"]
        )
    }

    @MainActor
    func testWindowUsesCompactResizableConfiguration() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertEqual(window.title, "Scrawl")
        XCTAssertEqual(contentView.frame.size, NSSize(width: 680, height: 460))
        XCTAssertEqual(window.minSize, NSSize(width: 620, height: 400))
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.resizable))
    }

    @MainActor
    private func makeActions() -> PreferencesWindowController.Actions {
        PreferencesWindowController.Actions(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            setHotkey: {},
            requestMicrophone: {},
            requestAccessibility: {}
        )
    }
}
