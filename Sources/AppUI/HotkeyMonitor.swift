import AppKit
import Foundation
import SettingsStore

final class HotkeyMonitor {
    private let onKeyDown: @MainActor () -> Void
    private let onKeyUp: @MainActor () -> Void
    private let hotkey: HotkeySetting

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isDown = false

    init(
        hotkey: HotkeySetting,
        onKeyDown: @escaping @MainActor () -> Void,
        onKeyUp: @escaping @MainActor () -> Void
    ) {
        self.hotkey = hotkey
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else {
            return
        }

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.process(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.process(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isDown = false
    }

    private func process(_ event: NSEvent) {
        if hotkey.isModifierKey {
            processModifierEvent(event)
        } else {
            processNormalKeyEvent(event)
        }
    }

    private func processModifierEvent(_ event: NSEvent) {
        guard event.type == .flagsChanged, event.keyCode == hotkey.keyCode else {
            return
        }

        let expectedFlag = SupportedHotkeyModifiers.modifierFlag(for: hotkey.keyCode)
        let downFromEvent = expectedFlag.map { event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains($0) } ?? false
        let downFromSource = CGEventSource.keyState(.hidSystemState, key: hotkey.keyCode)
        let downNow = downFromEvent || downFromSource

        if downNow, !isDown {
            isDown = true
            Task { @MainActor in
                onKeyDown()
            }
            return
        }

        if !downNow, isDown {
            isDown = false
            Task { @MainActor in
                onKeyUp()
            }
        }
    }

    private func processNormalKeyEvent(_ event: NSEvent) {
        guard event.keyCode == hotkey.keyCode else {
            return
        }

        if event.type == .keyDown, !event.isARepeat, !isDown {
            isDown = true
            Task { @MainActor in
                onKeyDown()
            }
            return
        }

        if event.type == .keyUp, isDown {
            isDown = false
            Task { @MainActor in
                onKeyUp()
            }
        }
    }

    deinit {
        stop()
    }
}
