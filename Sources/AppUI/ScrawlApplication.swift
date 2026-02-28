import AppKit
import AudioCapture
import HotkeyEngine
import Permissions
import SettingsStore
import TranscriptionCore

public final class ScrawlApplication {
    public init() {}

    public func run() {
        let app = NSApplication.shared
        let delegate = StatusBarAppDelegate(runtime: .live())

        DelegateRetainer.shared.delegate = delegate

        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

private final class DelegateRetainer {
    static let shared = DelegateRetainer()
    var delegate: NSApplicationDelegate?
}

private struct TranscriptRecord: Sendable {
    let id: UUID
    let createdAt: Date
    let text: String
}

private final class StatusBarAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum RecordingOrigin {
        case manual
        case hotkeyHold
        case hotkeyToggle
    }

    private let runtime: AppRuntime
    private let modelManager: LocalModelManager

    private var statusItem: NSStatusItem?
    private var rootMenu: NSMenu?

    private var infoLineItem: NSMenuItem?
    private var microphoneItem: NSMenuItem?
    private var accessibilityItem: NSMenuItem?
    private var startManualItem: NSMenuItem?
    private var stopManualItem: NSMenuItem?

    private var modelsSubmenu: NSMenu?
    private var historySubmenu: NSMenu?

    private var recordingOrigin: RecordingOrigin?
    private var recordingSafetyTimer: Timer?
    private var insertionTargetApp: NSRunningApplication?
    private var lastExternalActiveApp: NSRunningApplication?
    private var transcriptHistory: [TranscriptRecord] = []

    private var workspaceActivationObserver: NSObjectProtocol?
    private var hotkeyMonitor: HotkeyMonitor?
    private var hotkeyTickTimer: Timer?

    private var hotkeyCaptureGlobalMonitor: Any?
    private var hotkeyCaptureLocalMonitor: Any?
    private var hotkeyCaptureTimeoutTimer: Timer?
    private var isCapturingHotkey = false

    private var isModelDownloadInProgress = false

    init(runtime: AppRuntime) {
        self.runtime = runtime
        self.modelManager = LocalModelManager(modelsDirectoryURL: runtime.modelsDirectoryURL)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        observeWorkspaceActivations()
        setupHotkeyHandling()

        do {
            try modelManager.ensureDirectory()
        } catch {
            setStatus("Model dir error: \(describe(error))")
        }

        refreshSettingsRows()
        refreshModelMenu()
        refreshHistoryMenu()
        updatePermissionRows()
        updateRecordingActionRows()
        setStatus("Idle")
        updateStatusIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardownHotkeyHandling()
        stopHotkeyCapture()
        stopObservingWorkspaceActivations()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshSettingsRows()
        refreshModelMenu()
        refreshHistoryMenu()
        updatePermissionRows()
        updateRecordingActionRows()
    }

    @objc private func requestMicrophonePermission(_ sender: Any?) {
        runtime.permissionManager.requestMicrophoneAccess { [weak self] _ in
            DispatchQueue.main.async {
                self?.updatePermissionRows()
            }
        }
    }

    @objc private func requestAccessibilityPermission(_ sender: Any?) {
        _ = runtime.permissionManager.requestAccessibilityAccess(prompt: true)
        updatePermissionRows()
        teardownHotkeyHandling()
        setupHotkeyHandling()
        if runtime.permissionManager.accessibilityStatus() == .authorized {
            setStatus("Hotkey ready")
        }
    }

    @objc private func beginHotkeyCapture(_ sender: Any?) {
        guard !isCapturingHotkey else {
            return
        }

        teardownHotkeyHandling()
        isCapturingHotkey = true
        setStatus("Press desired hotkey now...")

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

        hotkeyCaptureGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.handleHotkeyCaptureEvent(event)
            }
        }

        hotkeyCaptureLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.handleHotkeyCaptureEvent(event)
            }
            return event
        }

        hotkeyCaptureTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.setStatus("Hotkey capture timed out")
            self.stopHotkeyCapture()
            self.setupHotkeyHandling()
        }
        if let hotkeyCaptureTimeoutTimer {
            RunLoop.main.add(hotkeyCaptureTimeoutTimer, forMode: .common)
        }
    }

    @objc private func showIdleState(_ sender: Any?) {
        runtime.overlayController.setState(.idle)
        updateStatusIcon()
    }

    @objc private func showRecordingState(_ sender: Any?) {
        runtime.overlayController.setState(.recording)
        updateStatusIcon()
    }

    @objc private func showTranscribingState(_ sender: Any?) {
        runtime.overlayController.setState(.transcribing)
        updateStatusIcon()
    }

    @objc private func startManualRecording(_ sender: Any?) {
        beginRecording(origin: .manual)
    }

    @objc private func stopManualRecordingAndTranscribe(_ sender: Any?) {
        stopRecordingAndTranscribe(reason: "Manual stop")
    }

    @objc private func repasteTranscript(_ sender: NSMenuItem) {
        guard
            let idString = sender.representedObject as? String,
            let id = UUID(uuidString: idString),
            let record = transcriptHistory.first(where: { $0.id == id })
        else {
            setStatus("Transcript not found")
            return
        }

        Task { [weak self] in
            await self?.pasteToPreviousApp(record.text)
            await self?.setStatusOnMain("Repasted transcript")
        }
    }

    @objc private func selectInstalledModel(_ sender: NSMenuItem) {
        guard let modelID = sender.representedObject as? String else {
            return
        }
        var settings = runtime.settingsStore.load()
        settings.selectedModelID = modelID
        if settings.defaultModelID.isEmpty {
            settings.defaultModelID = modelID
        }
        saveSettings(settings)
        setStatus("Selected model: \(modelID)")
    }

    @objc private func downloadModel(_ sender: NSMenuItem) {
        guard
            let modelID = sender.representedObject as? String,
            let model = LocalModelManager.downloadableModels.first(where: { $0.id == modelID })
        else {
            return
        }
        startModelDownload(model)
    }

    @objc private func deleteSelectedModel(_ sender: Any?) {
        let settings = runtime.settingsStore.load()
        let selected = settings.selectedModelID

        do {
            try modelManager.deleteModel(id: selected)
            var updated = settings
            let installed = modelManager.installedModelIDs()
            if let fallback = installed.first {
                updated.selectedModelID = fallback
            }
            saveSettings(updated)
            setStatus("Deleted model: \(selected)")
        } catch {
            setStatus("Delete failed: \(describe(error))")
        }
    }

    private func startModelDownload(_ model: DownloadableModel) {
        guard !isModelDownloadInProgress else {
            return
        }
        guard !modelManager.modelExists(downloadableModel: model) else {
            setStatus("Model already installed: \(model.id)")
            return
        }

        isModelDownloadInProgress = true
        refreshModelMenu()
        setStatus("Downloading \(model.displayName)...")

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.modelManager.download(model: model)
                var workingSettings = self.runtime.settingsStore.load()
                workingSettings.selectedModelID = model.id
                if workingSettings.defaultModelID.isEmpty {
                    workingSettings.defaultModelID = model.id
                }
                let updatedSettings = workingSettings
                await MainActor.run {
                    self.saveSettings(updatedSettings)
                    self.setStatus("Downloaded \(model.id)")
                }
            } catch {
                await self.setStatusOnMain("Download failed: \(self.describe(error))")
            }
            await MainActor.run {
                self.isModelDownloadInProgress = false
                self.refreshModelMenu()
            }
        }
    }

    private func validateTranscriptionPrerequisites(origin: RecordingOrigin) -> Bool {
        if !FileManager.default.isExecutableFile(atPath: runtime.whisperExecutableURL.path) {
            setStatus("whisper-cli missing")
            presentWhisperMissingAlert()
            return false
        }

        let settings = runtime.settingsStore.load()
        if modelManager.modelExists(id: settings.modelID) {
            return true
        }

        let installed = modelManager.installedModelIDs()
        if let fallback = installed.first {
            var updated = settings
            updated.selectedModelID = fallback
            saveSettings(updated)
            return true
        }

        setStatus("No model installed")
        presentMissingModelAlert(triggeredByHotkey: origin != .manual)
        return false
    }

    @discardableResult
    private func presentAlert(
        title: String,
        message: String,
        primaryButton: String = "OK",
        secondaryButton: String? = nil
    ) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: primaryButton)
        if let secondaryButton {
            alert.addButton(withTitle: secondaryButton)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private func presentWhisperMissingAlert() {
        let executablePath = runtime.whisperExecutableURL.path
        let message = """
        Scrawl could not find whisper-cli at:
        \(executablePath)

        Install whisper.cpp:
        brew install whisper-cpp

        Or set:
        SCRAWL_WHISPER_EXECUTABLE=/absolute/path/to/whisper-cli
        """

        _ = presentAlert(
            title: "whisper-cli not found",
            message: message
        )
    }

    private func presentMissingModelAlert(triggeredByHotkey: Bool) {
        guard let tinyModel = LocalModelManager.downloadableModels.first(where: { $0.id == "ggml-tiny.en" }) else {
            _ = presentAlert(
                title: "No model installed",
                message: "Scrawl needs a Whisper model in Models before transcription can run."
            )
            return
        }

        let alert = NSAlert()
        alert.messageText = "Set Up Speech Recognition"
        alert.informativeText = """
            Scrawl transcribes audio locally on your Mac using OpenAI's \
            Whisper model. No data leaves your device.

            To get started, download the tiny.en model (75 MB). \
            You can switch to a larger model later for improved accuracy.
            """
        alert.alertStyle = .informational
        if let icon = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil) {
            alert.icon = icon.withSymbolConfiguration(.init(pointSize: 48, weight: .medium))
        }
        alert.addButton(withTitle: "Download Model")
        alert.addButton(withTitle: "Not Now")
        NSApplication.shared.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            startModelDownload(tinyModel)
        }
    }

    private func presentNoSpeechDetectedAlert() {
        runtime.overlayController.showTransientMessage("No speech detected. Try again.")
        setStatus("No speech detected")
    }

    private func presentTranscriptionGuidanceIfNeeded(for error: Error) {
        guard let transcriptionError = error as? TranscriptionError else {
            return
        }

        switch transcriptionError {
        case .providerUnavailable:
            presentWhisperMissingAlert()
        case .modelMissing:
            presentMissingModelAlert(triggeredByHotkey: true)
        case .noSpeechDetected:
            presentNoSpeechDetectedAlert()
        case let .executionFailed(message):
            let normalized = message.uppercased()
            if normalized.contains("BLANK_AUDIO")
                || normalized.contains("EMPTY TRANSCRIPT")
                || normalized.contains("NO SPEECH")
            {
                presentNoSpeechDetectedAlert()
            }
        }
    }

    @objc private func hotkeyTick(_ timer: Timer) {
        dispatchHotkeyActions(runtime.hotkeyStateMachine.tick(at: Date()))
    }

    @objc private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Scrawl"
        statusItem.isVisible = true
        self.statusItem = statusItem

        let menu = NSMenu()
        menu.delegate = self
        rootMenu = menu

        let infoLineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        infoLineItem.isEnabled = false
        menu.addItem(infoLineItem)
        self.infoLineItem = infoLineItem

        menu.addItem(.separator())

        let historyItem = NSMenuItem(title: "Recent Transcripts", action: nil, keyEquivalent: "")
        let historySubmenu = NSMenu()
        historyItem.submenu = historySubmenu
        self.historySubmenu = historySubmenu
        menu.addItem(historyItem)

        let modelsItem = NSMenuItem(title: "Models", action: nil, keyEquivalent: "")
        let modelsSubmenu = NSMenu()
        modelsItem.submenu = modelsSubmenu
        self.modelsSubmenu = modelsSubmenu
        menu.addItem(modelsItem)

        // Permissions — hidden once both are granted
        let micItem = NSMenuItem(title: "", action: #selector(requestMicrophonePermission(_:)), keyEquivalent: "")
        micItem.target = self
        menu.addItem(micItem)
        self.microphoneItem = micItem

        let axItem = NSMenuItem(title: "", action: #selector(requestAccessibilityPermission(_:)), keyEquivalent: "")
        axItem.target = self
        menu.addItem(axItem)
        self.accessibilityItem = axItem

        // Debug tools — only visible with SCRAWL_DEBUG=1
        if ProcessInfo.processInfo.environment["SCRAWL_DEBUG"] != nil {
            menu.addItem(.separator())

            let startManualItem = NSMenuItem(title: "Start Recording", action: #selector(startManualRecording(_:)), keyEquivalent: "r")
            startManualItem.target = self
            menu.addItem(startManualItem)
            self.startManualItem = startManualItem

            let stopManualItem = NSMenuItem(title: "Stop + Transcribe", action: #selector(stopManualRecordingAndTranscribe(_:)), keyEquivalent: "s")
            stopManualItem.target = self
            menu.addItem(stopManualItem)
            self.stopManualItem = stopManualItem

            let idleState = NSMenuItem(title: "Preview Idle", action: #selector(showIdleState(_:)), keyEquivalent: "")
            idleState.target = self
            menu.addItem(idleState)

            let recordingState = NSMenuItem(title: "Preview Recording", action: #selector(showRecordingState(_:)), keyEquivalent: "")
            recordingState.target = self
            menu.addItem(recordingState)

            let transcribingState = NSMenuItem(title: "Preview Transcribing", action: #selector(showTranscribingState(_:)), keyEquivalent: "")
            transcribingState.target = self
            menu.addItem(transcribingState)
        }

        menu.addItem(.separator())

        let setHotkeyItem = NSMenuItem(title: "Set Hotkey...", action: #selector(beginHotkeyCapture(_:)), keyEquivalent: "")
        setHotkeyItem.target = self
        menu.addItem(setHotkeyItem)

        let quitItem = NSMenuItem(title: "Quit Scrawl", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setupHotkeyHandling() {
        guard hotkeyMonitor == nil else {
            return
        }

        let hotkey = runtime.settingsStore.load().hotkey
        let monitor = HotkeyMonitor(
            hotkey: hotkey,
            onKeyDown: { [weak self] in
                self?.dispatchHotkeyActions(self?.runtime.hotkeyStateMachine.keyDown(at: Date()) ?? [])
            },
            onKeyUp: { [weak self] in
                self?.dispatchHotkeyActions(self?.runtime.hotkeyStateMachine.keyUp(at: Date()) ?? [])
            }
        )
        monitor.start()
        hotkeyMonitor = monitor

        let tickTimer = Timer.scheduledTimer(timeInterval: 0.02, target: self, selector: #selector(hotkeyTick(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(tickTimer, forMode: .common)
        hotkeyTickTimer = tickTimer

        if runtime.permissionManager.accessibilityStatus() != .authorized {
            setStatus("Hotkey limited until Accessibility is enabled")
        }
    }

    private func teardownHotkeyHandling() {
        hotkeyTickTimer?.invalidate()
        hotkeyTickTimer = nil
        hotkeyMonitor?.stop()
        hotkeyMonitor = nil
        runtime.hotkeyStateMachine.reset()
    }

    private func dispatchHotkeyActions(_ actions: [HotkeyGestureAction]) {
        for action in actions {
            switch action {
            case .startHoldRecording:
                beginRecording(origin: .hotkeyHold)
            case .stopHoldRecording:
                if recordingOrigin == .hotkeyHold {
                    stopRecordingAndTranscribe(reason: "Hold release")
                }
            case .startToggleRecording:
                beginRecording(origin: .hotkeyToggle)
            case .stopToggleRecording:
                if recordingOrigin == .hotkeyToggle {
                    stopRecordingAndTranscribe(reason: "Toggle stop")
                }
            }
        }
    }

    private func beginRecording(origin: RecordingOrigin) {
        guard recordingOrigin == nil else {
            return
        }

        if runtime.permissionManager.microphoneStatus() != .authorized {
            if runtime.permissionManager.microphoneStatus() == .notDetermined {
                requestMicrophonePermission(nil)
            }
            setStatus("Microphone permission required")
            return
        }

        guard validateTranscriptionPrerequisites(origin: origin) else {
            return
        }

        captureInsertionTargetApp()

        do {
            try runtime.audioCaptureService.startCapture()
            recordingOrigin = origin
            updateRecordingActionRows()
            scheduleSafetyStopTimer()
            runtime.overlayController.setState(.recording)
            updateStatusIcon()
            setStatus("Recording...")
        } catch {
            setStatus("Record error: \(describe(error))")
        }
    }

    private func stopRecordingAndTranscribe(reason: String) {
        guard let activeOrigin = recordingOrigin else {
            return
        }

        recordingSafetyTimer?.invalidate()
        recordingSafetyTimer = nil

        let audioURL: URL
        do {
            audioURL = try runtime.audioCaptureService.stopCapture()
        } catch {
            recordingOrigin = nil
            updateRecordingActionRows()
            runtime.overlayController.setState(.idle)
            updateStatusIcon()
            setStatus("Stop error: \(describe(error))")
            if case AudioCaptureError.captureTooShort = error, activeOrigin != .manual {
                presentNoSpeechDetectedAlert()
            }
            return
        }

        recordingOrigin = nil
        updateRecordingActionRows()
        runtime.overlayController.setState(.transcribing)
        updateStatusIcon()
        setStatus("Transcribing...")

        let settings = runtime.settingsStore.load()
        let runtime = self.runtime
        let insertionTargetApp = self.insertionTargetApp

        Task { [weak self] in
            do {
                let request = TranscriptionRequest(
                    audioFileURL: audioURL,
                    modelID: settings.modelID,
                    language: settings.language
                )
                let result = try await runtime.whisperProvider.transcribe(request)
                let correctedText = runtime.dictionaryStore.apply(to: result.text)
                await self?.pasteToTargetApp(correctedText, target: insertionTargetApp)
                await self?.handleTranscriptionSuccess(latencyMS: result.latencyMS, transcript: correctedText)
            } catch {
                await self?.handleTranscriptionFailure(error, reason: reason)
            }
        }
    }

    private func observeWorkspaceActivations() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != selfPID {
            lastExternalActiveApp = app
        }

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else {
                return
            }
            if app.processIdentifier != selfPID {
                self.lastExternalActiveApp = app
            }
        }
    }

    private func stopObservingWorkspaceActivations() {
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
            self.workspaceActivationObserver = nil
        }
    }

    private func captureInsertionTargetApp() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != selfPID {
            insertionTargetApp = app
            return
        }
        insertionTargetApp = lastExternalActiveApp
    }

    @MainActor
    private func handleHotkeyCaptureEvent(_ event: NSEvent) {
        guard isCapturingHotkey else {
            return
        }

        if let captured = capturedHotkey(from: event) {
            applyHotkey(captured)
            stopHotkeyCapture()
            setupHotkeyHandling()
        }
    }

    private func capturedHotkey(from event: NSEvent) -> HotkeySetting? {
        if event.type == .flagsChanged {
            switch event.keyCode {
            case 56: return HotkeySetting(keyCode: 56, isModifierKey: true, displayName: "Left \u{21E7} Shift")
            case 60: return HotkeySetting(keyCode: 60, isModifierKey: true, displayName: "Right \u{21E7} Shift")
            case 58: return HotkeySetting(keyCode: 58, isModifierKey: true, displayName: "Left \u{2325} Option")
            case 61: return HotkeySetting(keyCode: 61, isModifierKey: true, displayName: "Right \u{2325} Option")
            case 59: return HotkeySetting(keyCode: 59, isModifierKey: true, displayName: "Left \u{2303} Control")
            case 62: return HotkeySetting(keyCode: 62, isModifierKey: true, displayName: "Right \u{2303} Control")
            case 55: return HotkeySetting(keyCode: 55, isModifierKey: true, displayName: "Left \u{2318} Command")
            case 54: return HotkeySetting(keyCode: 54, isModifierKey: true, displayName: "Right \u{2318} Command")
            default: return nil
            }
        }

        if event.type == .keyDown, !event.isARepeat {
            if event.keyCode == 53 { // Escape
                setStatus("Hotkey capture cancelled")
                stopHotkeyCapture()
                setupHotkeyHandling()
                return nil
            }
            let label = (event.charactersIgnoringModifiers ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let display = label.isEmpty ? "KeyCode \(event.keyCode)" : label.uppercased()
            return HotkeySetting(
                keyCode: event.keyCode,
                isModifierKey: false,
                displayName: display
            )
        }

        return nil
    }

    private func applyHotkey(_ hotkey: HotkeySetting) {
        var settings = runtime.settingsStore.load()
        settings.hotkey = hotkey
        saveSettings(settings)
        setStatus("Hotkey set: \(hotkey.displayName)")
    }

    private func stopHotkeyCapture() {
        if let hotkeyCaptureGlobalMonitor {
            NSEvent.removeMonitor(hotkeyCaptureGlobalMonitor)
            self.hotkeyCaptureGlobalMonitor = nil
        }
        if let hotkeyCaptureLocalMonitor {
            NSEvent.removeMonitor(hotkeyCaptureLocalMonitor)
            self.hotkeyCaptureLocalMonitor = nil
        }
        hotkeyCaptureTimeoutTimer?.invalidate()
        hotkeyCaptureTimeoutTimer = nil
        isCapturingHotkey = false
    }

    private func refreshSettingsRows() {
        let settings = runtime.settingsStore.load()
        let modelName = settings.modelID
            .replacingOccurrences(of: "ggml-", with: "")
        infoLineItem?.title = "\(modelName) · \(settings.hotkey.displayName)"
    }

    private func refreshModelMenu() {
        guard let modelsSubmenu else {
            return
        }

        modelsSubmenu.removeAllItems()
        let settings = runtime.settingsStore.load()

        let installed = modelManager.installedModelIDs()
        if installed.isEmpty {
            let empty = NSMenuItem(title: "No installed models", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            modelsSubmenu.addItem(empty)
        } else {
            for modelID in installed {
                let displayName = modelID.replacingOccurrences(of: "ggml-", with: "")
                let item = NSMenuItem(title: displayName, action: #selector(selectInstalledModel(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = modelID
                item.state = (modelID == settings.modelID) ? .on : .off
                modelsSubmenu.addItem(item)
            }
        }

        modelsSubmenu.addItem(.separator())

        let downloadable = LocalModelManager.downloadableModels.filter { !modelManager.modelExists(downloadableModel: $0) }

        let downloadableHeader = NSMenuItem(title: "Download", action: nil, keyEquivalent: "")
        downloadableHeader.isEnabled = false
        modelsSubmenu.addItem(downloadableHeader)

        if downloadable.isEmpty {
            let allInstalled = NSMenuItem(title: "All available models are installed", action: nil, keyEquivalent: "")
            allInstalled.isEnabled = false
            modelsSubmenu.addItem(allInstalled)
        } else {
            for model in downloadable {
                let item = NSMenuItem(title: model.displayName, action: #selector(downloadModel(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = model.id
                item.isEnabled = !isModelDownloadInProgress
                modelsSubmenu.addItem(item)
            }
        }

        modelsSubmenu.addItem(.separator())

        let deleteItem = NSMenuItem(title: "Delete Selected Model", action: #selector(deleteSelectedModel(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.isEnabled = modelManager.modelExists(id: settings.modelID)
        modelsSubmenu.addItem(deleteItem)
    }

    private func refreshHistoryMenu() {
        guard let historySubmenu else {
            return
        }

        historySubmenu.removeAllItems()

        guard !transcriptHistory.isEmpty else {
            let empty = NSMenuItem(title: "No transcripts yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historySubmenu.addItem(empty)
            return
        }

        for record in transcriptHistory {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let prefix = formatter.string(from: record.createdAt)
            let shortened = record.text.count > 70 ? String(record.text.prefix(67)) + "..." : record.text
            let title = "[\(prefix)] \(shortened)"
            let item = NSMenuItem(title: title, action: #selector(repasteTranscript(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = record.id.uuidString
            historySubmenu.addItem(item)
        }
    }

    private func updatePermissionRows() {
        let micStatus = runtime.permissionManager.microphoneStatus()
        let axStatus = runtime.permissionManager.accessibilityStatus()

        microphoneItem?.title = permissionMenuTitle(for: "Microphone", status: micStatus)
        accessibilityItem?.title = permissionMenuTitle(for: "Accessibility", status: axStatus)

        // Hide permission rows once both are granted
        let bothGranted = micStatus == .authorized && axStatus == .authorized
        microphoneItem?.isHidden = bothGranted
        accessibilityItem?.isHidden = bothGranted
    }

    private func updateRecordingActionRows() {
        let isRecording = recordingOrigin != nil
        startManualItem?.isEnabled = !isRecording
        stopManualItem?.isEnabled = isRecording
    }

    private func setStatus(_ text: String) {
        // Status is now communicated via the overlay + menubar icon.
        // This method is kept as a hook for debug logging.
        #if DEBUG
        print("[Scrawl] \(text)")
        #endif
    }

    @MainActor
    private func setStatusOnMain(_ text: String) {
        setStatus(text)
    }

    private func permissionMenuTitle(for name: String, status: PermissionStatus) -> String {
        switch status {
        case .authorized:
            return "\(name): Authorized"
        case .denied:
            return "\(name): Denied (click to retry)"
        case .notDetermined:
            return "\(name): Not Requested (click to request)"
        }
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else {
            return
        }

        let symbolName: String
        switch runtime.overlayController.state {
        case .idle:
            symbolName = "quote.bubble.fill"
        case .recording:
            symbolName = "waveform.circle.fill"
        case .transcribing:
            symbolName = "ellipsis.circle.fill"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Scrawl") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            switch runtime.overlayController.state {
            case .idle:
                button.title = "Sc"
            case .recording:
                button.title = "R"
            case .transcribing:
                button.title = "…"
            }
        }
    }

    private func scheduleSafetyStopTimer() {
        recordingSafetyTimer?.invalidate()
        recordingSafetyTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { [weak self] _ in
            guard let self, self.recordingOrigin != nil else {
                return
            }
            self.setStatus("Auto-stopping...")
            self.stopRecordingAndTranscribe(reason: "Safety timeout")
        }
        if let recordingSafetyTimer {
            RunLoop.main.add(recordingSafetyTimer, forMode: .common)
        }
    }

    @MainActor
    private func pasteToTargetApp(_ text: String, target: NSRunningApplication?) async {
        Self.restoreFocus(to: target)
        try? await Task.sleep(nanoseconds: 180_000_000)
        do {
            try await runtime.textOutputTarget.output(text)
        } catch {
            setStatus("Paste error: \(describe(error))")
        }
    }

    @MainActor
    private func pasteToPreviousApp(_ text: String) async {
        await pasteToTargetApp(text, target: lastExternalActiveApp)
    }

    private func addTranscriptToHistory(_ text: String) {
        let record = TranscriptRecord(id: UUID(), createdAt: Date(), text: text)
        transcriptHistory.insert(record, at: 0)
        if transcriptHistory.count > 12 {
            transcriptHistory = Array(transcriptHistory.prefix(12))
        }
        refreshHistoryMenu()
    }

    private func saveSettings(_ settings: AppSettings) {
        do {
            try runtime.settingsStore.save(settings)
            refreshSettingsRows()
            refreshModelMenu()
            teardownHotkeyHandling()
            setupHotkeyHandling()
        } catch {
            setStatus("Settings error: \(describe(error))")
        }
    }

    private func describe(_ error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        return String(describing: error)
    }

    @MainActor
    private static func restoreFocus(to app: NSRunningApplication?) {
        guard let app, !app.isTerminated else {
            return
        }
        _ = app.activate(options: [.activateAllWindows])
    }

    @MainActor
    private func handleTranscriptionSuccess(latencyMS: Int, transcript: String) {
        runtime.overlayController.setState(.idle)
        addTranscriptToHistory(transcript)
        updateStatusIcon()
        setStatus("Done")
    }

    @MainActor
    private func handleTranscriptionFailure(_ error: Error, reason: String) {
        runtime.overlayController.setState(.idle)
        updateStatusIcon()
        setStatus("\(reason): \(describe(error))")
        presentTranscriptionGuidanceIfNeeded(for: error)
    }
}
