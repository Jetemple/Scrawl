import AppKit
import ApplicationServices
import Carbon
import Foundation

public enum TextOutputError: Error {
    case accessibilityPermissionRequired
    case failedToWritePasteboard
    case failedToCreateEventSource
    /// A secure input field (e.g. a password field) is focused. The transcript was left on the
    /// clipboard for the user to paste deliberately rather than auto-pasted into a sensitive field.
    case secureInputActive
}

public protocol TextOutputTarget: Sendable {
    func output(_ text: String) async throws
}

public final class PasteboardTextOutput: TextOutputTarget, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func output(_ text: String) async throws {
        guard AXIsProcessTrusted() else {
            throw TextOutputError.accessibilityPermissionRequired
        }

        if IsSecureEventInputEnabled() {
            // A secure input field (password) is focused. Synthesized Cmd+V is unreliable while secure
            // input is active, and pasting spoken text into a password field would silently leak it.
            // Instead, leave the transcript on the clipboard (do NOT restore the previous contents) so
            // the user can paste it deliberately, and signal the caller to surface a message.
            PasteboardTextOutput.writeTranscript(text, to: pasteboard)
            throw TextOutputError.secureInputActive
        }

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        PasteboardTextOutput.writeTranscript(text, to: pasteboard)
        guard pasteboard.pasteboardItems?.first?.string(forType: .string) == text else {
            throw TextOutputError.failedToWritePasteboard
        }

        let changeCountAfterWrite = pasteboard.changeCount

        do {
            try sendCommandV()
        } catch {
            snapshot.restoreIfUnchanged(into: pasteboard, expectedChangeCount: changeCountAfterWrite)
            throw error
        }

        // Wait briefly to let the focused app consume Cmd+V before restoring clipboard.
        try await Task.sleep(nanoseconds: 140_000_000)
        snapshot.restoreIfUnchanged(into: pasteboard, expectedChangeCount: changeCountAfterWrite)
    }

    static func writeTranscript(_ text: String, to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // De-facto standard markers so clipboard managers skip/conceal dictated text.
        item.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
        item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    private func sendCommandV() throws {
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
