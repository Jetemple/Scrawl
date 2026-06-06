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
    func testSidebarSelectionSwitchesPagesAndPersists() {
        let controller = PreferencesWindowController(actions: makeActions())

        XCTAssertFalse(controller.hasDraggableSidebarDivider)
        controller.selectSection(.models)
        XCTAssertEqual(controller.visibleSection, .models)

        controller.window?.orderOut(nil)
        controller.showWindow(nil)
        XCTAssertEqual(controller.visibleSection, .models)
    }

    @MainActor
    func testModelsPageHasUnambiguousLayoutAtMinimumWindowSize() throws {
        let controller = PreferencesWindowController(actions: makeActions())
        let window = try XCTUnwrap(controller.window)
        window.setFrame(NSRect(origin: .zero, size: window.minSize), display: false)
        controller.selectSection(.models)
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertFalse(controller.visibleSectionHasAmbiguousLayout)
        XCTAssertTrue(controller.isVisibleSectionWithinContentBounds)
        XCTAssertTrue(controller.isVisibleSectionCriticalContentWithinBounds)
    }

    @MainActor
    func testPreferencesBackgroundsUpdateForAppearanceChanges() {
        for view in [
            PreferencesPageSupport.makeRoundedBackground(),
            PreferencesPageSupport.makeContentBackground()
        ] {
            let background = view as? PreferencesBackgroundView
            XCTAssertNotNil(background)

            background?.appearance = NSAppearance(named: .aqua)
            background?.updateLayer()
            let lightComponents = background?.layer?.backgroundColor?.components

            background?.appearance = NSAppearance(named: .darkAqua)
            background?.updateLayer()
            let darkComponents = background?.layer?.backgroundColor?.components

            XCTAssertNotEqual(lightComponents, darkComponents)
        }
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
