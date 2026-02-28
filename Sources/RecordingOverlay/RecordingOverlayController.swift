import AppKit
import Foundation

public enum RecordingOverlayState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
}

public final class RecordingOverlayController: @unchecked Sendable {
    public private(set) var state: RecordingOverlayState = .idle
    private var panel: NSPanel?
    private var titleLabel: NSTextField?
    private var spinner: NSProgressIndicator?

    public init() {}

    public func setState(_ state: RecordingOverlayState) {
        if Thread.isMainThread {
            apply(state)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.apply(state)
            }
        }
    }

    private func apply(_ state: RecordingOverlayState) {
        self.state = state
        ensurePanel()
        guard let panel, let titleLabel, let spinner else {
            return
        }

        switch state {
        case .idle:
            spinner.stopAnimation(nil)
            panel.orderOut(nil)
        case .recording:
            titleLabel.stringValue = "● Recording"
            titleLabel.textColor = .systemRed
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            positionPanel(panel)
            panel.orderFrontRegardless()
        case .transcribing:
            titleLabel.stringValue = "Transcribing"
            titleLabel.textColor = .labelColor
            spinner.isHidden = false
            spinner.startAnimation(nil)
            positionPanel(panel)
            panel.orderFrontRegardless()
        }
    }

    private func ensurePanel() {
        guard panel == nil else {
            return
        }

        let frame = NSRect(x: 0, y: 0, width: 190, height: 52)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let visual = NSVisualEffectView(frame: frame)
        visual.autoresizingMask = [.width, .height]
        visual.material = .hudWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 12
        visual.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "Recording")
        label.frame = NSRect(x: 16, y: 16, width: 130, height: 20)
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor

        let spinner = NSProgressIndicator(frame: NSRect(x: 154, y: 15, width: 20, height: 20))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true

        visual.addSubview(label)
        visual.addSubview(spinner)
        panel.contentView = visual

        self.panel = panel
        self.titleLabel = label
        self.spinner = spinner
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let visible = screen.visibleFrame
        let x = visible.maxX - panel.frame.width - 18
        let y = visible.maxY - panel.frame.height - 18
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
