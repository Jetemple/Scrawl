import AppKit

/// Builds the app's main menu. Scrawl is an accessory app, so the menu bar is never
/// visible — but AppKit routes key equivalents (⌘V, ⌘C, ⌘A, ⌘W…) through
/// `NSApp.mainMenu`, so without one no text field in the preferences window can
/// paste, copy, or select-all. Every item dispatches through the responder chain
/// (nil target) so the focused field editor or window handles it.
enum MainMenuBuilder {
    static func make() -> NSMenu {
        let main = NSMenu()
        // Slot 0 is the application menu by AppKit convention. It stays empty —
        // the menu bar never renders for an accessory app — but reserving it
        // keeps File/Edit in the right slots if the activation policy changes.
        main.addItem(makeSubmenuItem(NSMenu()))
        main.addItem(makeSubmenuItem(makeFileMenu()))
        main.addItem(makeSubmenuItem(makeEditMenu()))
        return main
    }

    private static func makeSubmenuItem(_ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = submenu
        return item
    }

    private static func makeFileMenu() -> NSMenu {
        let file = NSMenu(title: "File")
        // No Quit (⌘Q) on purpose: a background dictation app shouldn't die to a
        // reflexive keystroke while the preferences window happens to be focused.
        // Quit lives in the status-bar menu.
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return file
    }

    private static func makeEditMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        // undo:/redo: have no exported Swift symbol; the field editor's undo manager
        // still resolves them through the responder chain.
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return edit
    }
}
