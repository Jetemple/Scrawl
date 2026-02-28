import AppKit
import ApplicationServices
import Foundation

public enum TextOutputError: Error {
    case accessibilityPermissionRequired
    case failedToWritePasteboard
    case failedToCreateEventSource
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

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw TextOutputError.failedToWritePasteboard
        }

        try sendCommandV()

        // Wait briefly to let the focused app consume Cmd+V before restoring clipboard.
        try await Task.sleep(nanoseconds: 140_000_000)
        snapshot.restore(into: pasteboard)
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

private struct PasteboardSnapshot {
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

    func restore(into pasteboard: NSPasteboard) {
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
