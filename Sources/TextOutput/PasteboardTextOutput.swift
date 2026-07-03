import AppKit
import ApplicationServices
import Carbon
import Foundation

public enum TextOutputError: Error, LocalizedError, Equatable {
    case accessibilityPermissionRequired
    case failedToWritePasteboard
    case failedToCreateEventSource
    /// macOS Secure Keyboard Entry is active session-wide, so synthesized ⌘V is blocked. This is
    /// usually a terminal (e.g. Ghostty/Terminal) or a password manager holding secure input, not
    /// a focused password field. The transcript is left on the clipboard for the user to paste
    /// deliberately rather than auto-pasted into what could be a sensitive field.
    case secureInputActive

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Scrawl needs Accessibility permission to paste for you. Turn it on in "
                + "System Settings → Privacy & Security → Accessibility, then try again."
        case .failedToWritePasteboard:
            "Scrawl couldn't copy the transcript to the clipboard."
        case .failedToCreateEventSource:
            "Scrawl couldn't send the paste keystroke (it failed to create an event source)."
        case .secureInputActive:
            "Auto-paste paused — macOS Secure Keyboard Entry is on (often your terminal or a "
                + "password manager). Your text is on the clipboard; press ⌘V to paste."
        }
    }
}

public protocol TextOutputTarget: Sendable {
    func output(_ text: String, markPrivate: Bool) async throws
}

public final class PasteboardTextOutput: TextOutputTarget, @unchecked Sendable {
    private let pasteboard: NSPasteboard
    private let focusedTextInserter: FocusedTextInserting
    private let isAccessibilityTrusted: @Sendable () -> Bool
    private let isSecureInputActive: @Sendable () -> Bool
    private let sendPasteCommand: @Sendable () throws -> Void
    private let pasteSettleDelayNanoseconds: UInt64

    public init(
        pasteboard: NSPasteboard = .general,
        focusedTextInserter: FocusedTextInserting = AccessibilityFocusedTextInserter(),
        isAccessibilityTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        isSecureInputActive: @escaping @Sendable () -> Bool = { IsSecureEventInputEnabled() },
        sendPasteCommand: (@Sendable () throws -> Void)? = nil,
        pasteSettleDelayNanoseconds: UInt64 = 140_000_000
    ) {
        self.pasteboard = pasteboard
        self.focusedTextInserter = focusedTextInserter
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.isSecureInputActive = isSecureInputActive
        // Wrapped in a literal because a bare method reference is not @Sendable.
        self.sendPasteCommand = sendPasteCommand ?? { try PasteboardTextOutput.sendCommandV() }
        self.pasteSettleDelayNanoseconds = pasteSettleDelayNanoseconds
    }

    public func output(_ text: String, markPrivate: Bool = true) async throws {
        guard isAccessibilityTrusted() else {
            throw TextOutputError.accessibilityPermissionRequired
        }

        if isSecureInputActive() {
            // Secure Keyboard Entry is active session-wide (commonly a terminal or password manager,
            // sometimes a focused password field). Synthesized Cmd+V is blocked while secure input is
            // active. The Accessibility API is NOT blocked, so first try to insert directly into the
            // focused field — but only when it's a verified, non-secure text field, so dictation can
            // never leak into a password box. If there's no safe target, fall back to the clipboard
            // (do NOT restore the previous contents) so the user can paste it deliberately, and signal
            // the caller to surface a message. Always mark private in this path regardless of user
            // preferences — a possible password-field context must never feed clipboard managers.
            if focusedTextInserter.insertReplacingSelection(text) {
                return
            }
            PasteboardTextOutput.writeTranscript(text, to: pasteboard, markPrivate: true)
            throw TextOutputError.secureInputActive
        }

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        PasteboardTextOutput.writeTranscript(text, to: pasteboard, markPrivate: markPrivate)
        guard pasteboard.pasteboardItems?.first?.string(forType: .string) == text else {
            throw TextOutputError.failedToWritePasteboard
        }

        let changeCountAfterWrite = pasteboard.changeCount

        do {
            try sendPasteCommand()
        } catch {
            if markPrivate {
                snapshot.restoreIfUnchanged(into: pasteboard, expectedChangeCount: changeCountAfterWrite)
            }
            throw error
        }

        // Wait briefly to let the focused app consume Cmd+V before restoring clipboard.
        try await Task.sleep(nanoseconds: pasteSettleDelayNanoseconds)
        if markPrivate {
            snapshot.restoreIfUnchanged(into: pasteboard, expectedChangeCount: changeCountAfterWrite)
        }
    }

    static func writeTranscript(_ text: String, to pasteboard: NSPasteboard, markPrivate: Bool = true) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if markPrivate {
            // De-facto standard markers so clipboard managers skip/conceal dictated text.
            item.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
            item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    private static func sendCommandV() throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw TextOutputError.failedToCreateEventSource
        }

        let keyCodeForV: CGKeyCode = 9

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}

struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let snapshotItems = (pasteboard.pasteboardItems ?? []).map { item in
            var itemMap: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemMap[type] = data
                }
            }
            return itemMap
        }
        return PasteboardSnapshot(items: snapshotItems)
    }

    func restoreIfUnchanged(into pasteboard: NSPasteboard, expectedChangeCount: Int) {
        guard pasteboard.changeCount == expectedChangeCount else { return }
        pasteboard.clearContents()
        let restoredItems = items.map { typeMap -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in typeMap {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
