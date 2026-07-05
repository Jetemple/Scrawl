import AppKit
import Foundation
import QuartzCore

public enum RecordingOverlayState: Equatable, Sendable {
    case idle
    case hotkeyCapture
    case recording
    case transcribing
}

public final class RecordingOverlayController: @unchecked Sendable {
    public private(set) var state: RecordingOverlayState = .idle
    private var panel: NSPanel?
    private var dotView: NSView?
    private var symbolView: NSImageView?
    private var titleLabel: NSTextField?
    private var spinner: NSProgressIndicator?
    private var transientDismissWorkItem: DispatchWorkItem?
    /// Incremented every time the panel is shown or faded in.
    /// Fade-out completion handlers capture the value at the time they are
    /// scheduled and skip `orderOut` / teardown if the generation has advanced
    /// (meaning a new show/fade-in arrived before the animation finished).
    private var fadeGeneration = 0

    private var waveformView: NSView?
    private var barLayers: [CALayer] = []
    private(set) var barHeights: [CGFloat] = []
    private var levelTimer: Timer?
    /// Supplies the current input level in decibels; nil means not capturing.
    /// Assigned once at app startup (AppUI wires it to the audio capture service).
    public var levelProvider: (() -> Float?)?
    /// Test seam: overrides the system Reduce Motion setting when non-nil.
    var reduceMotionOverride: Bool?
    var isPollingLevels: Bool {
        levelTimer != nil
    }

    var isShowingWaveform: Bool {
        waveformView?.isHidden == false
    }

    var isShowingDot: Bool {
        dotView?.isHidden == false
    }

    private var isReduceMotionEnabled: Bool {
        reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Brand coral. Source of truth is `PreferencesPageSupport.accentColor` in AppUI
    /// (sRGB 0.95, 0.36, 0.30); RecordingOverlay cannot import AppUI, keep in sync.
    static let coralAccent = NSColor(srgbRed: 0.95, green: 0.36, blue: 0.30, alpha: 1)
    /// 5 bars of 2.5pt with 2pt gaps = 20.5, rounded up.
    static let waveformLeadingAccessoryWidth: CGFloat = 21
    private static let barWidth: CGFloat = 2.5
    private static let barGap: CGFloat = 2

    public init() {}

    deinit {
        levelTimer?.invalidate()
    }

    public func setState(_ state: RecordingOverlayState) {
        if Thread.isMainThread {
            apply(state)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.apply(state)
            }
        }
    }

    public func showTransientMessage(_ text: String, duration: TimeInterval = 1.6) {
        if Thread.isMainThread {
            applyTransientMessage(text, duration: duration)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.applyTransientMessage(text, duration: duration)
            }
        }
    }

    private func apply(_ state: RecordingOverlayState) {
        transientDismissWorkItem?.cancel()
        transientDismissWorkItem = nil

        let previous = self.state
        self.state = state
        ensurePanel()
        guard let panel, let dotView, let symbolView, let titleLabel, let spinner else {
            return
        }

        switch state {
        case .idle:
            stopIndicatorAnimations()
            dotView.isHidden = true
            waveformView?.isHidden = true
            stopLevelPolling()
            symbolView.isHidden = true
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            fadeGeneration += 1
            fadeOut(panel)

        case .hotkeyCapture:
            titleLabel.stringValue = "Press Hotkey"
            titleLabel.textColor = .labelColor
            dotView.isHidden = true
            waveformView?.isHidden = true
            stopLevelPolling()
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            configureSymbolView(
                symbolView,
                symbolName: "keyboard.fill",
                fallbackSymbolName: "keyboard",
                tintColor: .systemOrange
            )
            symbolView.isHidden = false
            startSymbolPulse()
            layoutSubviews()
            positionPanel(panel)
            fadeGeneration += 1
            fadeIn(panel, wasHidden: previous == .idle)

        case .recording:
            titleLabel.stringValue = "Recording"
            // Semantic color like every other state: the pill material follows the
            // system appearance, so hardcoded white washes out in light mode.
            titleLabel.textColor = .labelColor
            symbolView.isHidden = true
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            stopIndicatorAnimations()
            if isReduceMotionEnabled {
                // Static coral dot: no bars, no pulse, no polling.
                stopLevelPolling()
                waveformView?.isHidden = true
                dotView.isHidden = false
                dotView.layer?.backgroundColor = Self.coralAccent.cgColor
            } else {
                dotView.isHidden = true
                waveformView?.isHidden = false
                startLevelPolling()
            }
            layoutSubviews()
            positionPanel(panel)
            fadeGeneration += 1
            fadeIn(panel, wasHidden: previous == .idle)

        case .transcribing:
            titleLabel.stringValue = "Transcribing"
            titleLabel.textColor = .secondaryLabelColor
            stopIndicatorAnimations()
            dotView.isHidden = true
            waveformView?.isHidden = true
            stopLevelPolling()
            symbolView.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
            layoutSubviews()
            positionPanel(panel)
            fadeGeneration += 1
            fadeIn(panel, wasHidden: previous == .idle)
        }

        // The pill is a borderless, non-key, mouse-transparent panel, so it never enters the
        // accessibility tree. Without an explicit announcement a VoiceOver user gets no
        // feedback that recording started/stopped. Announce each non-idle state transition.
        titleLabel.setAccessibilityLabel(titleLabel.stringValue)
        if state != previous, state != .idle {
            announce(titleLabel.stringValue)
        }
    }

    /// Posts a high-priority VoiceOver announcement. No-op when VoiceOver is off, so there is
    /// no effect for sighted users.
    private func announce(_ message: String) {
        guard !message.isEmpty else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func applyTransientMessage(_ text: String, duration: TimeInterval) {
        transientDismissWorkItem?.cancel()
        transientDismissWorkItem = nil

        ensurePanel()
        guard let panel, let dotView, let symbolView, let titleLabel, let spinner else {
            return
        }

        stopIndicatorAnimations()
        dotView.isHidden = true
        waveformView?.isHidden = true
        stopLevelPolling()
        symbolView.isHidden = true
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        titleLabel.stringValue = text
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.setAccessibilityLabel(text)
        layoutSubviews()
        positionPanel(panel)
        fadeGeneration += 1
        fadeIn(panel, wasHidden: panel.alphaValue == 0)
        announce(text)

        let workItem = DispatchWorkItem { [weak self] in
            self?.fireTransientDismiss()
        }
        transientDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 0.2), execute: workItem)
    }

    /// Runs when a transient message's display time elapses. Idle → fade the pill out;
    /// otherwise re-apply the live state so a transient shown mid-recording restores the
    /// waveform/spinner/symbol instead of leaving stale text with no indicator.
    func fireTransientDismiss() {
        guard let panel else { return }
        if state == .idle {
            fadeOut(panel)
        } else {
            apply(state)
        }
    }

    // MARK: - Pill width computation

    /// Returns the required panel width for the given label text, clamped to [minPillWidth, maxPillWidth].
    ///
    /// - Parameters:
    ///   - text: The string that will be displayed in the title label.
    ///   - font: The label font.
    ///   - leadingAccessoryWidth: The width consumed by any leading accessory (dot, symbol, spinner)
    ///     plus the gap between it and the label. Pass 0 when there is no accessory.
    /// - Returns: A clamped pill width.
    static func pillWidth(forText text: String, font: NSFont, leadingAccessoryWidth: CGFloat) -> CGFloat {
        let padding: CGFloat = 14
        let measuredText = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let required = padding + leadingAccessoryWidth + measuredText + labelTextInset + padding
        return min(max(required, minPillWidth), maxPillWidth)
    }

    static let minPillWidth: CGFloat = 148
    static let maxPillWidth: CGFloat = 420
    /// Height of a single-line pill. A wrapped pill adds `pillLineHeight` per extra line.
    static let basePillHeight: CGFloat = 34
    /// Vertical space one line of label text occupies inside the pill.
    static let pillLineHeight: CGFloat = 16
    /// Long messages wrap up to this many lines before the last line ellipsizes.
    static let maxPillLines = 2
    /// Slack reserved for the NSTextField cell's internal inset, which makes the cell
    /// need slightly more width than `NSString.size` reports. Without it the cell wraps
    /// a "one line" message and clips the hidden second line.
    static let labelTextInset: CGFloat = 8
    static let shadowMargin: CGFloat = 12

    /// Returns the pill height needed to render `text`. Text that fits on one line at the
    /// width `pillWidth(forText:)` chose keeps `basePillHeight`; longer text wraps up to
    /// `maxPillLines`, growing the pill taller. Both functions share the same width and
    /// inset accounting so the height never under-allocates lines the cell will render.
    static func pillHeight(forText text: String, font: NSFont, leadingAccessoryWidth: CGFloat) -> CGFloat {
        let padding: CGFloat = 14
        let measured = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let chosenWidth = pillWidth(forText: text, font: font, leadingAccessoryWidth: leadingAccessoryWidth)
        // Usable text width inside the label, leaving the cell's internal inset as slack.
        let usable = chosenWidth - padding - leadingAccessoryWidth - padding - labelTextInset
        guard measured > usable else {
            return basePillHeight
        }

        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: max(usable, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let neededLines = max(1, Int(ceil(bounding.height / pillLineHeight)))
        let cappedLines = min(neededLines, maxPillLines)
        return basePillHeight + CGFloat(cappedLines - 1) * pillLineHeight
    }

    // MARK: - Panel setup

    private func ensurePanel() {
        guard panel == nil else {
            return
        }

        let pillWidth = Self.minPillWidth
        let pillHeight = Self.basePillHeight
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
        let shadowMargin = Self.shadowMargin
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
        shadowHost.layer?.shadowPath = Self.makeShadowPath(pillWidth: pillWidth, pillHeight: pillHeight, shadowMargin: shadowMargin)

        let visual = NSVisualEffectView(frame: frame)
        visual.autoresizingMask = [.width, .height]
        visual.material = .hudWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = pillHeight / 2
        visual.layer?.masksToBounds = true
        // A hairline edge so the pill stays legible on dark or busy wallpapers, where the
        // drop shadow alone gives little separation. The faint stroke disappears into the
        // light-mode material and separates the dark one, so it works in both appearances.
        visual.layer?.borderWidth = 1
        visual.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        let dot = NSView(frame: .zero)
        dot.wantsLayer = true
        dot.layer?.backgroundColor = Self.coralAccent.cgColor
        dot.layer?.cornerRadius = 4
        dot.isHidden = true

        let waveform = NSView(frame: .zero)
        waveform.wantsLayer = true
        waveform.isHidden = true
        var layers: [CALayer] = []
        for index in 0..<WaveformLevel.barCount {
            let bar = CALayer()
            bar.backgroundColor = Self.coralAccent.cgColor
            bar.cornerRadius = Self.barWidth / 2
            bar.frame = NSRect(
                x: CGFloat(index) * (Self.barWidth + Self.barGap),
                y: 0,
                width: Self.barWidth,
                height: WaveformLevel.minBarHeight
            )
            waveform.layer?.addSublayer(bar)
            layers.append(bar)
        }
        visual.addSubview(waveform)
        waveformView = waveform
        barLayers = layers

        let symbolView = NSImageView(frame: .zero)
        symbolView.imageScaling = .scaleProportionallyUpOrDown
        symbolView.contentTintColor = .systemOrange
        symbolView.wantsLayer = true
        symbolView.isHidden = true

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        // Wrap long messages onto a second line (then ellipsize) instead of clipping words.
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = Self.maxPillLines
        label.cell?.wraps = true
        label.cell?.isScrollable = false

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true

        visual.addSubview(dot)
        visual.addSubview(symbolView)
        visual.addSubview(label)
        visual.addSubview(spinner)

        let container = NSView(frame: frame)
        container.autoresizingMask = [.width, .height]
        container.addSubview(shadowHost)
        container.addSubview(visual)
        panel.contentView = container

        self.panel = panel
        dotView = dot
        self.symbolView = symbolView
        titleLabel = label
        self.spinner = spinner
    }

    /// Generates the CGPath used for the shadow host's shadowPath.
    private static func makeShadowPath(pillWidth: CGFloat, pillHeight: CGFloat, shadowMargin: CGFloat) -> CGPath {
        // Fixed corner radius (single-line capsule radius) so a taller, wrapped pill
        // reads as a rounded rectangle instead of an over-rounded stadium.
        let cornerRadius = basePillHeight / 2
        return CGPath(
            roundedRect: CGRect(x: shadowMargin, y: shadowMargin, width: pillWidth, height: pillHeight),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }

    /// Resizes the panel to fit the current label text, then regenerates the shadow path.
    /// Must be called BEFORE `layoutSubviews()` positions child frames.
    private func resizePanel() {
        guard let panel, let titleLabel, let dotView, let symbolView, let spinner else { return }

        let font = titleLabel.font ?? NSFont.systemFont(ofSize: 12, weight: .medium)
        let text = titleLabel.stringValue

        // Determine leading accessory width + gap (matches layoutSubviews constants).
        let leadingAccessoryWidth: CGFloat = if waveformView?.isHidden == false {
            Self.waveformLeadingAccessoryWidth + 8 // waveform(21) + gap(8)
        } else if !dotView.isHidden {
            8 + 8 // dotSize(8) + gap(8)
        } else if !symbolView.isHidden {
            15 + 8 // symbolSize(15) + gap(8)
        } else if !spinner.isHidden {
            16 + 8 // spinnerSize(16) + gap(8)
        } else {
            0
        }

        let newWidth = Self.pillWidth(forText: text, font: font, leadingAccessoryWidth: leadingAccessoryWidth)
        let newHeight = Self.pillHeight(forText: text, font: font, leadingAccessoryWidth: leadingAccessoryWidth)
        let shadowMargin = Self.shadowMargin

        // Resize panel (autoresizingMask on container/visual/shadowHost propagates the change).
        panel.setFrame(
            NSRect(origin: panel.frame.origin, size: NSSize(width: newWidth, height: newHeight)),
            display: false
        )

        // Regenerate shadow path to match the new width and height.
        if let shadowHost = panel.contentView?.subviews.first {
            shadowHost.layer?.shadowPath = Self.makeShadowPath(
                pillWidth: newWidth,
                pillHeight: newHeight,
                shadowMargin: shadowMargin
            )
        }
    }

    // MARK: - Layout

    private func layoutSubviews() {
        // Resize the panel to fit the current text FIRST, so child frame
        // calculations below use the updated panel width.
        resizePanel()

        guard let panel, let dotView, let symbolView, let titleLabel, let spinner else {
            return
        }

        let h = panel.frame.height
        let padding: CGFloat = 14
        // Vertical inset that lets the label occupy the pill's full (possibly multi-line)
        // height. For a single-line pill (h == basePillHeight) this collapses to the old
        // centered 16pt line; when the pill grows to a second line the label can use it
        // instead of clipping. Shared by every branch so an accessory never caps the label.
        let labelInset = (Self.basePillHeight - Self.pillLineHeight) / 2

        if let waveformView, !waveformView.isHidden {
            waveformView.frame = NSRect(
                x: padding,
                y: (h - WaveformLevel.maxBarHeight) / 2,
                width: Self.waveformLeadingAccessoryWidth,
                height: WaveformLevel.maxBarHeight
            )

            let labelX = padding + Self.waveformLeadingAccessoryWidth + 8
            titleLabel.frame = NSRect(
                x: labelX,
                y: labelInset,
                width: panel.frame.width - labelX - padding,
                height: h - labelInset * 2
            )
        } else if !dotView.isHidden {
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
                y: labelInset,
                width: panel.frame.width - labelX - padding,
                height: h - labelInset * 2
            )
        } else if !symbolView.isHidden {
            let symbolSize: CGFloat = 15
            symbolView.frame = NSRect(
                x: padding,
                y: (h - symbolSize) / 2,
                width: symbolSize,
                height: symbolSize
            )

            let labelX = padding + symbolSize + 8
            titleLabel.frame = NSRect(
                x: labelX,
                y: labelInset,
                width: panel.frame.width - labelX - padding,
                height: h - labelInset * 2
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
                y: labelInset,
                width: panel.frame.width - labelX - padding,
                height: h - labelInset * 2
            )
        } else {
            // No accessory: this is where long transient messages live.
            titleLabel.frame = NSRect(
                x: padding,
                y: labelInset,
                width: panel.frame.width - padding * 2,
                height: h - labelInset * 2
            )
        }
    }

    // MARK: - Animation

    private func startSymbolPulse() {
        guard let symbolView, let layer = symbolView.layer else {
            return
        }
        stopIndicatorAnimations()
        // Respect Reduce Motion: leave a fully-visible static symbol instead of a looping pulse.
        guard !isReduceMotionEnabled else { return }

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.45
        opacity.toValue = 1.0
        opacity.duration = 0.8
        opacity.autoreverses = true
        opacity.repeatCount = .infinity

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.92
        scale.toValue = 1.02
        scale.duration = 0.8
        scale.autoreverses = true
        scale.repeatCount = .infinity

        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = 0.8
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(group, forKey: "waiting")
    }

    private func stopIndicatorAnimations() {
        dotView?.layer?.removeAnimation(forKey: "pulse")
        symbolView?.layer?.removeAnimation(forKey: "waiting")
    }

    // MARK: - Live level waveform

    private func startLevelPolling() {
        guard levelTimer == nil else { return }
        barHeights = Array(repeating: WaveformLevel.minBarHeight, count: WaveformLevel.barCount)
        applyBarHeights()
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.pollLevelOnce()
        }
        // A 25Hz timer doesn't need sub-frame precision; tolerance lets the OS coalesce wakeups.
        timer.tolerance = 0.008
        // .common so the bars keep moving while menus or drags track the run loop.
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    private func stopLevelPolling() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    /// One metering tick. Internal so tests can drive it without waiting on the timer.
    func pollLevelOnce() {
        let level = WaveformLevel.normalizedLevel(fromDecibels: levelProvider?() ?? nil)
        barHeights = WaveformLevel.nextBarHeights(level: level, previous: barHeights)
        applyBarHeights()
    }

    private func applyBarHeights() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, height) in zip(barLayers, barHeights) {
            var frame = layer.frame
            frame.origin.y = (WaveformLevel.maxBarHeight - height) / 2
            frame.size.height = height
            layer.frame = frame
        }
        CATransaction.commit()
    }

    private func configureSymbolView(
        _ symbolView: NSImageView,
        symbolName: String,
        fallbackSymbolName: String,
        tintColor: NSColor
    ) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Waiting for hotkey"
        ) ?? NSImage(
            systemSymbolName: fallbackSymbolName,
            accessibilityDescription: "Waiting for hotkey"
        )
        symbolView.image = image?.withSymbolConfiguration(configuration)
        symbolView.contentTintColor = tintColor
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
        let generation = fadeGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            guard let self, fadeGeneration == generation else { return }
            panel.orderOut(nil)
        }
    }

    // MARK: - Position

    private func positionPanel(_ panel: NSPanel) {
        // This is an LSUIElement accessory app that owns no key window, so `NSScreen.main`
        // can point at a display the user isn't typing on. Prefer the screen under the
        // mouse — where the user is actually working — so the live indicator lands there.
        let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        guard let screen = mouseScreen ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let visible = screen.visibleFrame
        let x = visible.maxX - panel.frame.width - 16
        let y = visible.maxY - panel.frame.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
