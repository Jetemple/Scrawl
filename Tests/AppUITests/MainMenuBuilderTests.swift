import AppKit
@testable import AppUI
import XCTest

final class MainMenuBuilderTests: XCTestCase {
    private func editMenu(in menu: NSMenu) -> NSMenu? {
        menu.items.first { $0.submenu?.title == "Edit" }?.submenu
    }

    func testMenuContainsEditMenuWithStandardKeyEquivalents() throws {
        let edit = try XCTUnwrap(editMenu(in: MainMenuBuilder.make()))
        // key equivalent → expected action, the standard Edit bindings every text
        // field expects to reach through the responder chain.
        let expectations: [(key: String, action: Selector)] = [
            ("x", #selector(NSText.cut(_:))),
            ("c", #selector(NSText.copy(_:))),
            ("v", #selector(NSText.paste(_:))),
            ("a", #selector(NSText.selectAll(_:))),
        ]
        for (key, action) in expectations {
            let item = edit.items.first { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == .command }
            XCTAssertEqual(item?.action, action, "Edit menu is missing ⌘\(key.uppercased())")
            XCTAssertNil(item?.target, "⌘\(key.uppercased()) must dispatch through the responder chain")
        }
    }

    func testMenuContainsUndoAndRedo() throws {
        let edit = try XCTUnwrap(editMenu(in: MainMenuBuilder.make()))
        let undo = edit.items.first { $0.keyEquivalent == "z" && $0.keyEquivalentModifierMask == .command }
        XCTAssertEqual(undo?.action, Selector(("undo:")))
        let redo = edit.items.first { $0.keyEquivalent == "z" && $0.keyEquivalentModifierMask == [.command, .shift] }
        XCTAssertEqual(redo?.action, Selector(("redo:")))
    }

    func testMenuContainsCloseWindow() throws {
        let menu = MainMenuBuilder.make()
        let file = try XCTUnwrap(menu.items.first { $0.submenu?.title == "File" }?.submenu)
        let close = file.items.first { $0.keyEquivalent == "w" && $0.keyEquivalentModifierMask == .command }
        XCTAssertEqual(close?.action, #selector(NSWindow.performClose(_:)))
        XCTAssertNil(close?.target)
    }
}
