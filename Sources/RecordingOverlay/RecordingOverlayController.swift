import AppKit
import Foundation
import QuartzCore

public enum RecordingOverlayState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
}

public final class RecordingOverlayController: @unchecked Sendable {
    public private(set) var state: RecordingOverlayState = .idle
    private var panel: NSPanel?
    private var dotView: NSView?
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
        let previous = self.state
        self.state = state
        ensurePanel()
        guard let panel, let dotView, let titleLabel, let spinner else {
            return
        }

        switch state {
        case .idle:
            dotView.layer?.removeAnimation(forKey: "pulse")
            dotView.isHidden = true
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            fadeOut(panel)

        case .recording:
            titleLabel.stringValue = "Recording"
            titleLabel.textColor = .labelColor
            dotView.isHidden = false
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            startDotPulse()
            layoutSubviews()
            positionPanel(panel)
            fadeIn(panel, wasHidden: previous == .idle)

        case .transcribing:
            titleLabel.stringValue = "Transcribing"
            titleLabel.textColor = .secondaryLabelColor
            dotView.layer?.removeAnimation(forKey: "pulse")
            dotView.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
            layoutSubviews()
            positionPanel(panel)
            fadeIn(panel, wasHidden: previous == .idle)
        }
    }

    // MARK: - Panel setup

    private func ensurePanel() {
        guard panel == nil else {
            return
        }

        let pillWidth: CGFloat = 148
        let pillHeight: CGFloat = 34
        let frame = NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0

        // Shadow host — draws a rounded shadow without clipping
        let shadowMargin: CGFloat = 12
        let shadowFrame = NSRect(
            x: -shadowMargin,
            y: -shadowMargin,
            width: pillWidth + shadowMargin * 2,
            height: pillHeight + shadowMargin * 2
        )
        let shadowHost = NSView(frame: shadowFrame)
        shadowHost.autoresizingMask = [.width, .height]
        shadowHost.wantsLayer = true
        shadowHost.layer?.masksToBounds = false
        shadowHost.layer?.shadowColor = NSColor.black.cgColor
        shadowHost.layer?.shadowOpacity = 0.2
        shadowHost.layer?.shadowRadius = 8
        shadowHost.layer?.shadowOffset = CGSize(width: 0, height: -2)
        shadowHost.layer?.shadowPath = CGPath(
            roundedRect: CGRect(x: shadowMargin, y: shadowMargin, width: pillWidth, height: pillHeight),
            cornerWidth: pillHeight / 2,
            cornerHeight: pillHeight / 2,
            transform: nil
        )

        let visual = NSVisualEffectView(frame: frame)
        visual.autoresizingMask = [.width, .height]
        visual.material = .hudWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = pillHeight / 2
        visual.layer?.masksToBounds = true

        let dot = NSView(frame: .zero)
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 4
        dot.isHidden = true

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true

        visual.addSubview(dot)
        visual.addSubview(label)
        visual.addSubview(spinner)

        let container = NSView(frame: frame)
        container.autoresizingMask = [.width, .height]
        container.addSubview(shadowHost)
        container.addSubview(visual)
        panel.contentView = container

        self.panel = panel
        self.dotView = dot
        self.titleLabel = label
        self.spinner = spinner
    }

    // MARK: - Layout

    private func layoutSubviews() {
        guard let panel, let dotView, let titleLabel, let spinner else {
            return
        }

        let h = panel.frame.height
        let padding: CGFloat = 14

        if !dotView.isHidden {
            let dotSize: CGFloat = 8
            dotView.frame = NSRect(
                x: padding,
                y: (h - dotSize) / 2,
                width: dotSize,
                height: dotSize
            )
            dotView.layer?.cornerRadius = dotSize / 2

            let labelX = padding + dotSize + 8
            titleLabel.frame = NSRect(
                x: labelX,
                y: (h - 16) / 2,
                width: panel.frame.width - labelX - padding,
                height: 16
            )
        } else if !spinner.isHidden {
            let spinnerSize: CGFloat = 16
            spinner.frame = NSRect(
                x: padding,
                y: (h - spinnerSize) / 2,
                width: spinnerSize,
                height: spinnerSize
            )

            let labelX = padding + spinnerSize + 8
            titleLabel.frame = NSRect(
                x: labelX,
                y: (h - 16) / 2,
                width: panel.frame.width - labelX - padding,
                height: 16
            )
        } else {
            titleLabel.frame = NSRect(
                x: padding,
                y: (h - 16) / 2,
                width: panel.frame.width - padding * 2,
                height: 16
            )
        }
    }

    // MARK: - Animation

    private func startDotPulse() {
        guard let dotView, let layer = dotView.layer else {
            return
        }
        layer.removeAnimation(forKey: "pulse")

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.3
        pulse.toValue = 1.0
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: "pulse")
    }

    private func fadeIn(_ panel: NSPanel, wasHidden: Bool) {
        if wasHidden {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1.0
            }
        } else {
            panel.alphaValue = 1.0
            panel.orderFrontRegardless()
        }
    }

    private func fadeOut(_ panel: NSPanel) {
        guard panel.alphaValue > 0 else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0.0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    // MARK: - Position

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let visible = screen.visibleFrame
        let x = visible.maxX - panel.frame.width - 16
        let y = visible.maxY - panel.frame.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
