import AppKit
import AudioCapture
import HotkeyEngine
import Permissions
import SettingsStore
import TextOutput
import TranscriptHistoryStore
import TranscriptionCore

public final class ScrawlApplication {
    public init() {}

    public func run() {
        do {
            let instanceLock = try SingleInstanceLock()
            if try !instanceLock.tryAcquire() {
                Self.activateExistingInstance()
                return
            }
            DelegateRetainer.shared.instanceLock = instanceLock
        } catch {
            #if DEBUG
            print("[Scrawl] Single-instance lock unavailable: \(error)")
            #endif
        }

        let app = NSApplication.shared
        let delegate = StatusBarAppDelegate(runtime: .live())

        DelegateRetainer.shared.delegate = delegate

        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }

    private static func activateExistingInstance() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.jetemple.scrawl"
        let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != currentPID }

        _ = existing?.activate(options: [.activateAllWindows])
    }
}

private final class DelegateRetainer {
    static let shared = DelegateRetainer()
    var delegate: NSApplicationDelegate?
    var instanceLock: SingleInstanceLock?
}

private final class StatusBarAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum RecordingOrigin {
        case manual
        case hotkeyHold
        case hotkeyToggle
    }

    private static let hotkeyCapturePrompt = "Press a key, Fn, or a modifier. Esc cancels."

    private let runtime: AppRuntime
    private let modelManager: LocalModelManager
    private lazy var transcriptHistoryCoordinator = TranscriptHistoryCoordinator(
        settingsStore: runtime.settingsStore,
        historyStore: runtime.transcriptHistoryStore
    )

    private var statusItem: NSStatusItem?
    private var rootMenu: NSMenu?

    private var infoLineItem: NSMenuItem?
    private var hotkeyLineItem: NSMenuItem?
    private var statusLineItem: NSMenuItem?
    private var microphoneItem: NSMenuItem?
    private var accessibilityItem: NSMenuItem?
    private var startManualItem: NSMenuItem?
    private var stopManualItem: NSMenuItem?
    private var setHotkeyItem: NSMenuItem?
    private var preferencesWindowController: PreferencesWindowController?

    private var modelsSubmenu: NSMenu?
    private var historySubmenu: NSMenu?

    private var recordingOrigin: RecordingOrigin?
    private var recordingSafetyTimer: Timer?
    private var insertionTargetApp: NSRunningApplication?
    private var lastExternalActiveApp: NSRunningApplication?

    private var workspaceActivationObserver: NSObjectProtocol?
    private var hotkeyMonitor: HotkeyMonitor?
    private var hotkeyGestureTimer: Timer?

    private var hotkeyCaptureGlobalMonitor: Any?
    private var hotkeyCaptureLocalMonitor: Any?
    private var hotkeyCaptureTimeoutTimer: Timer?
    private var statusAutoClearTimer: Timer?
    private var isCapturingHotkey = false

    private var isModelDownloadInProgress = false
    private var downloadingModelID: String?
    private var latestStatusText = ""
    private var activeOperationGeneration = ActiveOperationGeneration()
    private var historyActionPresentationPolicy = HistoryActionPresentationPolicy()
    private var pendingHistoryFailures: [(title: String, description: String)] = []
    private let historyActionQueue = DispatchQueue(label: "Scrawl.HistoryActions", qos: .utility)
    private let dictionaryActionQueue = DispatchQueue(label: "Scrawl.DictionaryActions", qos: .utility)
    private var cachedAccessibilityAuthorized = false
    private var hasPromptedAccessibilityForHotkeyAttempt = false

    init(runtime: AppRuntime) {
        self.runtime = runtime
        self.modelManager = LocalModelManager(modelsDirectoryURL: runtime.modelsDirectoryURL)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        observeWorkspaceActivations()
        cachedAccessibilityAuthorized = runtime.permissionManager.accessibilityStatus() == .authorized
        setupHotkeyHandling()

        do {
            try modelManager.ensureDirectory()
        } catch {
            setStatus("Model dir error: \(describe(error))")
        }

        applyRecommendedModelDefaultsIfNeeded()
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
        statusAutoClearTimer?.invalidate()
        statusAutoClearTimer = nil
        DelegateRetainer.shared.instanceLock?.release()
        DelegateRetainer.shared.instanceLock = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        reconcileAccessibilityAuthorization()
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
        promptForAccessibilityPermission(force: true)
    }

    @objc private func toggleHotkeyCapture(_ sender: Any?) {
        if isCapturingHotkey {
            cancelHotkeyCapture(status: "Hotkey capture cancelled")
            return
        }

        beginHotkeyCapture()
    }

    @objc private func openPreferences(_ sender: Any?) {
        if preferencesWindowController == nil {
            preferencesWindowController = makePreferencesWindowController()
        }
        refreshPreferencesWindow()
        preferencesWindowController?.showWindow(sender)
    }

    private func makePreferencesWindowController() -> PreferencesWindowController {
        PreferencesWindowController(
            actions: PreferencesWindowController.Actions(
                selectModel: { [weak self] modelID in
                    self?.selectModel(id: modelID)
                },
                downloadModel: { [weak self] model in
                    self?.startModelDownload(model)
                },
                deleteSelectedModel: { [weak self] in
                    self?.deleteSelectedModel(nil)
                },
                setHotkey: { [weak self] in
                    self?.toggleHotkeyCapture(nil)
                },
                requestMicrophone: { [weak self] in
                    self?.requestMicrophonePermission(nil)
                },
                requestAccessibility: { [weak self] in
                    self?.requestAccessibilityPermission(nil)
                },
                setTranscriptHistoryEnabled: { [weak self] enabled in
                    self?.setTranscriptHistoryEnabled(enabled)
                },
                copyTranscript: { [weak self] id in
                    self?.copyTranscript(id: id)
                },
                repasteTranscript: { [weak self] id in
                    self?.repasteTranscript(id: id)
                },
                deleteTranscripts: { [weak self] ids in
                    self?.deleteTranscripts(ids: ids)
                },
                addDictionaryEntry: { [weak self] wrong, correct, completion in
                    self?.addDictionaryEntry(wrong: wrong, correct: correct, completion: completion)
                }
            )
        )
    }

    private func refreshPreferencesWindow() {
        guard let preferencesWindowController else {
            return
        }

        let settings = runtime.settingsStore.load()
        let installedModelIDs = modelManager.installedModelIDs()
        let downloadableModels = LocalModelManager.downloadableModels
        let modelRows = PreferencesModelState.rows(
            downloadableModels: downloadableModels,
            installedModelIDs: installedModelIDs,
            selectedModelID: settings.modelID,
            downloadingModelID: downloadingModelID
        )

        preferencesWindowController.update(
            snapshot: PreferencesWindowController.Snapshot(
                settings: settings,
                downloadableModels: downloadableModels,
                modelRows: modelRows,
                microphoneStatus: runtime.permissionManager.microphoneStatus(),
                accessibilityStatus: runtime.permissionManager.accessibilityStatus(),
                isCapturingHotkey: isCapturingHotkey,
                isModelDownloadInProgress: isModelDownloadInProgress,
                transcriptHistory: runtime.transcriptHistoryStore.records(),
                transcriptHistoryLoadErrorDescription: runtime.transcriptHistoryStore.loadErrorDescription,
                dictionaryEntries: runtime.dictionaryStore.entries()
            )
        )
    }

    private func setTranscriptHistoryEnabled(_ enabled: Bool) {
        if !enabled {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Turn Off Transcript History?"
            alert.informativeText = "This permanently deletes all saved transcripts on this Mac."
            alert.addButton(withTitle: "Turn Off and Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                refreshPreferencesWindow()
                return
            }
        }

        let action = historyActionPresentationPolicy.beginAction()
        let coordinator = transcriptHistoryCoordinator
        historyActionQueue.async { [weak self] in
            let result = Result { try coordinator.setEnabled(enabled) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshHistoryMenu()
                self.refreshPreferencesWindow()
                self.handleHistoryActionCompletion(
                    action: action,
                    result: result,
                    successStatus: enabled ? "Transcript history enabled" : "Transcript history disabled and deleted",
                    failureTitle: "Could not update transcript history"
                )
            }
        }
    }

    private func copyTranscript(id: UUID) {
        guard let record = runtime.transcriptHistoryStore.records().first(where: { $0.id == id }) else {
            setStatus("Transcript not found")
            refreshPreferencesWindow()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.text, forType: .string)
        setStatus("Copied transcript")
    }

    private func repasteTranscript(id: UUID) {
        guard let record = runtime.transcriptHistoryStore.records().first(where: { $0.id == id }) else {
            setStatus("Transcript not found")
            refreshPreferencesWindow()
            return
        }
        Task { [weak self] in
            guard let outcome = await self?.pasteToPreviousApp(record.text) else { return }
            if let status = outcome.repasteStatus {
                await self?.setStatusOnMain(status)
            }
        }
    }

    private func deleteTranscripts(ids: Set<UUID>) {
        let action = historyActionPresentationPolicy.beginAction()
        let store = runtime.transcriptHistoryStore
        historyActionQueue.async { [weak self] in
            let result = Result { try store.delete(ids: ids) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshHistoryMenu()
                self.refreshPreferencesWindow()
                self.handleHistoryActionCompletion(
                    action: action,
                    result: result,
                    successStatus: "Deleted transcript",
                    failureTitle: "Could not delete transcript"
                )
            }
        }
    }

    private func addDictionaryEntry(
        wrong: String,
        correct: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let store = runtime.dictionaryStore
        dictionaryActionQueue.async { [weak self] in
            let result = Result { try store.addOrReplace(wrong: wrong, correct: correct) }
            DispatchQueue.main.async {
                self?.refreshPreferencesWindow()
                completion(result)
            }
        }
    }

    @MainActor
    private func handleHistoryActionCompletion(
        action: UInt64,
        result: Result<Void, Error>,
        successStatus: String,
        failureTitle: String
    ) {
        let completion: HistoryActionPresentationPolicy.Completion
        switch result {
        case .success:
            completion = .success
        case .failure:
            completion = .failure
        }
        let decision = historyActionPresentationPolicy.decision(
            for: action,
            completion: completion,
            hasActiveOperation: hasActiveOperation
        )
        switch (decision, result) {
        case (.presentSuccess, .success):
            applyStatus(successStatus)
        case let (.presentFailure, .failure(error)):
            presentHistoryFailure(failureTitle, description: describe(error))
        case let (.queueFailure, .failure(error)):
            pendingHistoryFailures.append((failureTitle, describe(error)))
        case (.ignore, _), (.presentSuccess, .failure), (.presentFailure, .success), (.queueFailure, .success):
            break
        }
    }

    @MainActor
    private func flushPendingHistoryFailuresIfPossible() {
        guard !hasActiveOperation, !pendingHistoryFailures.isEmpty else { return }
        let failures = pendingHistoryFailures
        pendingHistoryFailures.removeAll()
        for failure in failures {
            presentHistoryFailure(failure.title, description: failure.description)
        }
    }

    @MainActor
    private func presentHistoryFailure(_ title: String, description: String) {
        applyStatus("History unavailable: \(description)", autoClear: false)
        runtime.overlayController.showTransientMessage(title)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = description
        alert.runModal()
    }

    private func beginHotkeyCapture() {
        guard !isCapturingHotkey else {
            return
        }

        teardownHotkeyHandling()
        isCapturingHotkey = true
        activeOperationGeneration.beginActiveOperation()
        refreshSettingsRows()
        runtime.overlayController.setState(.hotkeyCapture)
        updateStatusIcon()
        setStatus(Self.hotkeyCapturePrompt)

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
            self.cancelHotkeyCapture(status: "Hotkey capture timed out")
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
            let record = runtime.transcriptHistoryStore.records().first(where: { $0.id == id })
        else {
            setStatus("Transcript not found")
            return
        }

        Task { [weak self] in
            guard let outcome = await self?.pasteToPreviousApp(record.text) else { return }
            if let status = outcome.repasteStatus {
                await self?.setStatusOnMain(status)
            }
        }
    }

    @objc private func selectInstalledModel(_ sender: NSMenuItem) {
        guard let modelID = sender.representedObject as? String else {
            return
        }
        selectModel(id: modelID)
    }

    private func selectModel(id modelID: String) {
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
        downloadingModelID = model.id
        refreshModelMenu()
        refreshPreferencesWindow()
        setStatus("Downloading \(model.displayName)...")

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.modelManager.download(model: model) { [weak self] receivedBytes, totalBytes in
                    guard let self else { return }
                    self.setStatus(self.downloadProgressText(for: model, receivedBytes: receivedBytes, totalBytes: totalBytes))
                }
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
                await MainActor.run {
                    let details = self.describe(error)
                    self.setStatus("Download failed")
                    _ = self.presentAlert(
                        title: "Model download failed",
                        message: """
                        Could not download \(model.displayName).

                        \(details)
                        """
                    )
                }
            }
            await MainActor.run {
                self.isModelDownloadInProgress = false
                self.downloadingModelID = nil
                self.refreshModelMenu()
                self.refreshPreferencesWindow()
            }
        }
    }

    private func downloadProgressText(for model: DownloadableModel, receivedBytes: Int64, totalBytes: Int64?) -> String {
        let modelName = model.id.replacingOccurrences(of: "ggml-", with: "")
        let receivedMB = formatMegabytes(receivedBytes)

        guard let totalBytes, totalBytes > 0 else {
            return "Downloading \(modelName): \(receivedMB) MB"
        }

        let totalMB = formatMegabytes(totalBytes)
        let ratio = max(0, min(1, Double(receivedBytes) / Double(totalBytes)))
        let percent = Int((ratio * 100).rounded())
        return "Downloading \(modelName): \(percent)% (\(receivedMB)/\(totalMB) MB)"
    }

    private func formatMegabytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 100 {
            return String(format: "%.0f", mb)
        }
        if mb >= 10 {
            return String(format: "%.1f", mb)
        }
        return String(format: "%.2f", mb)
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

    private func presentMicrophoneDeniedAlert() {
        let response = presentAlert(
            title: "Microphone Access Required",
            message: """
            Scrawl needs microphone access to record your voice for transcription.

            Open System Settings → Privacy & Security → Microphone and enable Scrawl.
            """,
            primaryButton: "Open Settings",
            secondaryButton: "Not Now"
        )

        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func presentWhisperMissingAlert() {
        _ = presentAlert(
            title: "whisper-cli Not Found",
            message: "Scrawl requires whisper.cpp for transcription.\n\nInstall it with Homebrew:\nbrew install whisper-cpp"
        )
    }

    private func promptForAccessibilityPermission(force: Bool) {
        cachedAccessibilityAuthorized = runtime.permissionManager.accessibilityStatus() == .authorized
        if cachedAccessibilityAuthorized {
            hasPromptedAccessibilityForHotkeyAttempt = false
            updatePermissionRows()
            teardownHotkeyHandling()
            setupHotkeyHandling()
            setStatus("Hotkey ready")
            return
        }

        if hasPromptedAccessibilityForHotkeyAttempt && !force {
            openAccessibilitySettings()
            runtime.overlayController.showTransientMessage("Enable Accessibility in System Settings")
            setStatus("Enable Accessibility in System Settings")
            return
        }

        hasPromptedAccessibilityForHotkeyAttempt = true

        _ = runtime.permissionManager.requestAccessibilityAccess(prompt: true)
        cachedAccessibilityAuthorized = runtime.permissionManager.accessibilityStatus() == .authorized
        updatePermissionRows()

        if cachedAccessibilityAuthorized {
            hasPromptedAccessibilityForHotkeyAttempt = false
            teardownHotkeyHandling()
            setupHotkeyHandling()
            setStatus("Hotkey ready")
        } else {
            openAccessibilitySettings()
            runtime.overlayController.showTransientMessage("Enable Accessibility in System Settings")
            setStatus("Enable Accessibility in System Settings")
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func presentMissingModelAlert(triggeredByHotkey: Bool) {
        let recommendedModel = preferredInitialDownloadModel()
        guard let recommendedModel else {
            _ = presentAlert(
                title: "No model installed",
                message: "Scrawl needs a Whisper model in Models before transcription can run."
            )
            return
        }

        let recommendedModelName = recommendedModel.id
            .replacingOccurrences(of: "ggml-", with: "")

        let alert = NSAlert()
        alert.messageText = "Set Up Speech Recognition"
        alert.informativeText = """
            Scrawl transcribes audio locally on your Mac using OpenAI's \
            Whisper model. No data leaves your device.

            To get started, download the \(recommendedModelName) model. \
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
            startModelDownload(recommendedModel)
        }
    }

    private func preferredInitialDownloadModel() -> DownloadableModel? {
        let preferredOrder = [
            runtime.recommendedDefaultModelID,
            "ggml-small.en",
            "ggml-medium",
            "ggml-tiny.en"
        ]

        for modelID in preferredOrder {
            if let model = LocalModelManager.downloadableModels.first(where: { $0.id == modelID }) {
                return model
            }
        }
        return LocalModelManager.downloadableModels.first
    }

    private func applyRecommendedModelDefaultsIfNeeded() {
        let hasStoredSettings = runtime.settingsStore.hasStoredSettings()
        var settings = runtime.settingsStore.load()
        var changed = false

        if !hasStoredSettings {
            settings.defaultModelID = runtime.recommendedDefaultModelID
            settings.selectedModelID = runtime.recommendedDefaultModelID
            changed = true
        }

        if settings.defaultModelID.isEmpty || settings.defaultModelID == "ggml-small" {
            settings.defaultModelID = runtime.recommendedDefaultModelID
            changed = true
        }

        if settings.selectedModelID.isEmpty || settings.selectedModelID == "ggml-small" {
            settings.selectedModelID = settings.defaultModelID
            changed = true
        }

        if changed {
            saveSettings(settings)
        }
    }

    private func presentNoSpeechDetectedAlert() {
        runtime.overlayController.showTransientMessage("No speech detected. Try again.")
        setStatus("No speech detected")
    }

    private func presentNoAudioCapturedMessage() {
        runtime.overlayController.showTransientMessage("No audio captured. Check your mic.")
        setStatus("No audio captured")
    }

    /// Surfaces user-facing guidance for a transcription failure. Returns `true` if it already showed
    /// something the user can see (alert or overlay message); `false` means the caller should show a
    /// generic visible fallback so the failure is never silent.
    @discardableResult
    private func presentTranscriptionGuidanceIfNeeded(for error: Error) -> Bool {
        guard let transcriptionError = error as? TranscriptionError else {
            return false
        }

        switch transcriptionError {
        case .providerUnavailable:
            presentWhisperMissingAlert()
            return true
        case .modelMissing:
            presentMissingModelAlert(triggeredByHotkey: true)
            return true
        case .noSpeechDetected:
            presentNoSpeechDetectedAlert()
            return true
        case .timedOut:
            runtime.overlayController.showTransientMessage("Transcription timed out. Try a shorter clip or a smaller model.")
            return true
        case let .executionFailed(message):
            let normalized = message.uppercased()
            if normalized.contains("BLANK_AUDIO")
                || normalized.contains("EMPTY TRANSCRIPT")
                || normalized.contains("NO SPEECH")
            {
                presentNoSpeechDetectedAlert()
                return true
            }
            return false
        }
    }

    private func reconcileAccessibilityAuthorization() {
        let isAuthorized = runtime.permissionManager.accessibilityStatus() == .authorized
        guard isAuthorized != cachedAccessibilityAuthorized else {
            return
        }

        cachedAccessibilityAuthorized = isAuthorized
        if isAuthorized {
            hasPromptedAccessibilityForHotkeyAttempt = false
        }
        updatePermissionRows()

        guard !isCapturingHotkey else {
            return
        }

        teardownHotkeyHandling()
        setupHotkeyHandling()
        if isAuthorized {
            setStatus("Hotkey ready")
        }
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

        let hotkeyLineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        hotkeyLineItem.isEnabled = false
        menu.addItem(hotkeyLineItem)
        self.hotkeyLineItem = hotkeyLineItem

        let statusLineItem = NSMenuItem(title: "Status: Launching...", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        statusLineItem.isHidden = true
        menu.addItem(statusLineItem)
        self.statusLineItem = statusLineItem

        menu.addItem(.separator())

        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

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

        let setHotkeyItem = NSMenuItem(title: "Set Hotkey...", action: #selector(toggleHotkeyCapture(_:)), keyEquivalent: "")
        setHotkeyItem.target = self
        menu.addItem(setHotkeyItem)
        self.setHotkeyItem = setHotkeyItem

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
                guard let self else { return }
                self.dispatchHotkeyActionsAndScheduleNext(self.runtime.hotkeyStateMachine.keyDown(at: Date()))
            },
            onKeyUp: { [weak self] in
                guard let self else { return }
                self.dispatchHotkeyActionsAndScheduleNext(self.runtime.hotkeyStateMachine.keyUp(at: Date()))
            }
        )
        monitor.start()
        hotkeyMonitor = monitor

        if runtime.permissionManager.accessibilityStatus() != .authorized {
            setStatus("Hotkey limited until Accessibility is enabled")
        }
    }

    private func teardownHotkeyHandling() {
        hotkeyGestureTimer?.invalidate()
        hotkeyGestureTimer = nil
        hotkeyMonitor?.stop()
        hotkeyMonitor = nil
        runtime.hotkeyStateMachine.reset()
    }

    private func dispatchHotkeyActionsAndScheduleNext(_ actions: [HotkeyGestureAction]) {
        dispatchHotkeyActions(actions)
        scheduleNextHotkeyGestureTimer()
    }

    private func scheduleNextHotkeyGestureTimer() {
        hotkeyGestureTimer?.invalidate()
        hotkeyGestureTimer = nil

        let now = Date()
        guard let deadline = runtime.hotkeyStateMachine.nextActionDeadline(at: now) else {
            return
        }

        let timer = Timer(
            fireAt: deadline,
            interval: 0,
            target: self,
            selector: #selector(handleHotkeyGestureTimer(_:)),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        hotkeyGestureTimer = timer
    }

    @objc private func handleHotkeyGestureTimer(_ timer: Timer) {
        dispatchHotkeyActionsAndScheduleNext(runtime.hotkeyStateMachine.tick(at: Date()))
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

        let micStatus = runtime.permissionManager.microphoneStatus()
        if micStatus != .authorized {
            if micStatus == .notDetermined {
                requestMicrophonePermission(nil)
            } else {
                presentMicrophoneDeniedAlert()
            }
            setStatus("Microphone permission required")
            return
        }

        if runtime.permissionManager.accessibilityStatus() != .authorized {
            promptForAccessibilityPermission(force: false)
            return
        }

        guard validateTranscriptionPrerequisites(origin: origin) else {
            return
        }

        captureInsertionTargetApp()

        do {
            try runtime.audioCaptureService.startCapture()
            recordingOrigin = origin
            activeOperationGeneration.beginActiveOperation()
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
            if case AudioCaptureError.audioLevelTooLow = error {
                presentNoAudioCapturedMessage()
            } else if case AudioCaptureError.captureTooShort = error, activeOrigin != .manual {
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
        let operationGeneration = activeOperationGeneration.current

        Task { [weak self] in
            defer { try? FileManager.default.removeItem(at: audioURL) }
            do {
                let request = TranscriptionRequest(
                    audioFileURL: audioURL,
                    modelID: settings.modelID,
                    language: settings.language,
                    progressHandler: { [weak self] event in
                        self?.handleTranscriptionProgress(event)
                    }
                )
                let result = try await runtime.whisperProvider.transcribe(request)
                let correctedText = runtime.dictionaryStore.apply(to: result.text)
                _ = await self?.pasteToTargetApp(correctedText, target: insertionTargetApp)
                await self?.handleTranscriptionSuccess(
                    latencyMS: result.latencyMS,
                    transcript: correctedText,
                    operationGeneration: operationGeneration
                )
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
            stopHotkeyCapture()
            applyHotkey(captured)
        }
    }

    private func capturedHotkey(from event: NSEvent) -> HotkeySetting? {
        if event.type == .flagsChanged {
            return SupportedHotkeyModifiers.hotkey(for: event.keyCode)
        }

        if event.type == .keyDown, !event.isARepeat {
            if event.keyCode == 53 { // Escape
                cancelHotkeyCapture(status: "Hotkey capture cancelled")
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
        // The hotkey changed, so rebuild the monitors to listen for the new key. This is also the
        // path that re-arms hotkey handling after a capture session (which tore it down).
        teardownHotkeyHandling()
        setupHotkeyHandling()
        setStatus("Hotkey set: \(hotkey.displayName)")
        runtime.overlayController.showTransientMessage("Hotkey set to \(hotkey.displayName)")
    }

    private func cancelHotkeyCapture(status: String) {
        setStatus(status)
        runtime.overlayController.showTransientMessage(status)
        stopHotkeyCapture()
        setupHotkeyHandling()
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
        runtime.overlayController.setState(.idle)
        updateStatusIcon()
        refreshSettingsRows()
    }

    private func refreshSettingsRows() {
        let settings = runtime.settingsStore.load()
        let modelName = settings.modelID
            .replacingOccurrences(of: "ggml-", with: "")
        infoLineItem?.title = "Model: \(modelName)"
        hotkeyLineItem?.title = isCapturingHotkey ? "Hotkey: Waiting for input..." : "Hotkey: \(settings.hotkey.displayName)"
        setHotkeyItem?.title = isCapturingHotkey ? "Cancel Hotkey Capture" : "Set Hotkey..."
        setHotkeyItem?.state = isCapturingHotkey ? .on : .off
        statusItem?.button?.toolTip = isCapturingHotkey ? "Scrawl: waiting for hotkey input" : "Scrawl: Hotkey \(settings.hotkey.displayName)"
        refreshPreferencesWindow()
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

        let state = PreferencesContentState.historyMenuState(
            isEnabled: runtime.settingsStore.load().isTranscriptHistoryEnabled,
            loadErrorDescription: runtime.transcriptHistoryStore.loadErrorDescription,
            records: runtime.transcriptHistoryStore.records()
        )

        switch state {
        case .disabled:
            let disabled = NSMenuItem(title: "Transcript history is off", action: nil, keyEquivalent: "")
            disabled.isEnabled = false
            historySubmenu.addItem(disabled)
        case .unavailable:
            let unavailable = NSMenuItem(title: "Transcript history unavailable", action: nil, keyEquivalent: "")
            unavailable.isEnabled = false
            historySubmenu.addItem(unavailable)
        case .empty:
            let empty = NSMenuItem(title: "No transcripts yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historySubmenu.addItem(empty)
        case let .records(records):
            for record in records {
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
        refreshPreferencesWindow()
    }

    private func updateRecordingActionRows() {
        let isRecording = recordingOrigin != nil
        startManualItem?.isEnabled = !isRecording
        stopManualItem?.isEnabled = isRecording
    }

    private static let ongoingStatuses: Set<String> = [
        "Recording...", "Transcribing...", hotkeyCapturePrompt
    ]

    private func setStatus(_ text: String, autoClear: Bool = true) {
        Task { @MainActor [weak self] in
            self?.applyStatus(text, autoClear: autoClear)
        }
    }

    @MainActor
    @discardableResult
    private func applyStatus(_ text: String, autoClear: Bool = true) -> UInt64 {
        let statusGeneration = activeOperationGeneration.applyStatus()
        statusAutoClearTimer?.invalidate()
        statusAutoClearTimer = nil
        latestStatusText = text

        if text == "Idle" {
            statusLineItem?.isHidden = true
            statusLineItem?.title = "Status: Idle"
            return statusGeneration
        }

        statusLineItem?.isHidden = false
        statusLineItem?.title = "Status: \(text)"

        let isOngoing = Self.ongoingStatuses.contains(text)
            || text.hasPrefix("Downloading ")
            || text.hasPrefix("Loading model:")
            || text.hasPrefix("Transcribing with ")
            || text.hasPrefix("Retrying on CPU")
        if autoClear, !isOngoing {
            scheduleStatusAutoClear(after: text == "Done" ? 2.5 : 5.0)
        }

        if !hasActiveOperation, !pendingHistoryFailures.isEmpty {
            Task { @MainActor [weak self] in
                self?.flushPendingHistoryFailuresIfPossible()
            }
        }

        #if DEBUG
        print("[Scrawl] \(text)")
        #endif
        return statusGeneration
    }

    @MainActor
    private func scheduleStatusAutoClear(after seconds: TimeInterval) {
        statusAutoClearTimer?.invalidate()
        statusAutoClearTimer = Timer.scheduledTimer(
            timeInterval: seconds,
            target: self,
            selector: #selector(handleStatusAutoClearTimer(_:)),
            userInfo: nil,
            repeats: false
        )
        if let statusAutoClearTimer {
            RunLoop.main.add(statusAutoClearTimer, forMode: .common)
        }
    }

    @objc private func handleStatusAutoClearTimer(_ timer: Timer) {
        setStatus("Idle")
    }

    @MainActor
    private func setStatusOnMain(_ text: String) {
        applyStatus(text)
    }

    private func handleTranscriptionProgress(_ event: TranscriptionProgressEvent) {
        switch event.phase {
        case .loadingModel:
            setStatus("Loading model: \(displayModelName(event.modelID))...")
        case .transcribing:
            setStatus("Transcribing with \(displayModelName(event.modelID))...")
        case .retryingOnCPU:
            setStatus("Retrying on CPU: \(displayModelName(event.modelID))...")
        }
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

    private func displayModelName(_ modelID: String) -> String {
        modelID.replacingOccurrences(of: "ggml-", with: "")
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else {
            return
        }

        let symbolName: String
        switch runtime.overlayController.state {
        case .idle:
            symbolName = "quote.bubble.fill"
        case .hotkeyCapture:
            symbolName = "keyboard.fill"
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
            case .hotkeyCapture:
                button.title = "⌨"
            case .recording:
                button.title = "R"
            case .transcribing:
                button.title = "…"
            }
        }
    }

    private var hasActiveOperation: Bool {
        switch runtime.overlayController.state {
        case .idle:
            return false
        case .hotkeyCapture, .recording, .transcribing:
            return true
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
    private func pasteToTargetApp(_ text: String, target: NSRunningApplication?) async -> PasteOutcome {
        Self.restoreFocus(to: target)
        try? await Task.sleep(nanoseconds: 180_000_000)
        do {
            try await runtime.textOutputTarget.output(text)
            return .pasted
        } catch TextOutputError.secureInputActive {
            setStatus("Secure field — transcript copied to clipboard")
            runtime.overlayController.showTransientMessage("Secure field detected — transcript copied to clipboard")
            return .copiedForSecureInput
        } catch {
            let description = describe(error)
            setStatus("Paste error: \(description)")
            runtime.overlayController.showTransientMessage("Couldn't paste — \(description)")
            return .failed(description)
        }
    }

    @MainActor
    private func pasteToPreviousApp(_ text: String) async -> PasteOutcome {
        await pasteToTargetApp(text, target: lastExternalActiveApp)
    }

    private func saveSettings(_ settings: AppSettings) {
        do {
            try runtime.settingsStore.save(settings)
            refreshSettingsRows()
            refreshModelMenu()
            refreshPreferencesWindow()
            // NOTE: hotkey monitors are intentionally NOT rebuilt here. Only applyHotkey changes the
            // hotkey, so rebuilding on every save (model select, download completion, launch defaults)
            // was needless churn — and worse, teardownHotkeyHandling resets the gesture state machine,
            // which could strand an in-progress recording until the 90s safety timeout. The rebuild now
            // lives in applyHotkey, the one place the hotkey actually changes.
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
    private func handleTranscriptionSuccess(
        latencyMS: Int,
        transcript: String,
        operationGeneration: UInt64
    ) async {
        let originatingStatusGeneration: UInt64?
        if operationGeneration == activeOperationGeneration.current {
            runtime.overlayController.setState(.idle)
            updateStatusIcon()
            if latencyMS >= 1_000 {
                originatingStatusGeneration = applyStatus(
                    String(format: "Done (%.1fs)", Double(latencyMS) / 1_000)
                )
            } else {
                originatingStatusGeneration = applyStatus("Done (\(latencyMS)ms)")
            }
        } else {
            originatingStatusGeneration = nil
        }

        let coordinator = transcriptHistoryCoordinator
        do {
            try await Task.detached(priority: .utility) {
                try coordinator.add(text: transcript)
            }.value
            refreshHistoryMenu()
            refreshPreferencesWindow()
        } catch {
            refreshHistoryMenu()
            refreshPreferencesWindow()
            if let originatingStatusGeneration,
               activeOperationGeneration.shouldPresentDelayedFailure(
                for: operationGeneration,
                originatingStatusGeneration: originatingStatusGeneration,
                hasActiveOperation: hasActiveOperation
               ) {
                applyStatus("History unavailable: \(describe(error))", autoClear: false)
                runtime.overlayController.showTransientMessage("Transcript history could not be saved")
            }
        }
    }

    @MainActor
    private func handleTranscriptionFailure(_ error: Error, reason: String) {
        runtime.overlayController.setState(.idle)
        updateStatusIcon()
        setStatus("\(reason): \(describe(error))")
        // Make sure every failure is visible without opening the menu. If no specific guidance was
        // shown, fall back to a transient overlay message in the pill the user is already watching.
        if !presentTranscriptionGuidanceIfNeeded(for: error) {
            runtime.overlayController.showTransientMessage("Transcription failed — \(describe(error))")
        }
    }
}
