import AppKit
import AudioCapture
import DictionaryStore
import HotkeyEngine
import Permissions
import SettingsStore
import TextOutput
import TranscriptHistoryStore
import TranscriptionCore

/// Pure decision for how to guide the user toward granting Accessibility, given the
/// current authorization state and whether the macOS system prompt has already been
/// shown this session. Side-effect-free so it is unit-testable.
///
/// The macOS prompt (shown by `AXIsProcessTrustedWithOptions(prompt:)`) already includes
/// an "Open System Settings" button and only appears once per TCC record, so the first
/// request must show the prompt *only* — opening Settings as well pops the notification
/// AND the Settings page at once. Settings is the fallback for a later, still-denied retry.
enum AccessibilityPromptDecision: Equatable {
    case alreadyAuthorized
    case showSystemPrompt
    case openSettings

    static func decide(isAuthorized: Bool, hasShownSystemPrompt: Bool) -> AccessibilityPromptDecision {
        if isAuthorized { return .alreadyAuthorized }
        return hasShownSystemPrompt ? .openSettings : .showSystemPrompt
    }
}

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
    private var recordingStartedAt: Date?
    private var recordingSafetyTimer: Timer?
    private var insertionTargetApp: NSRunningApplication?
    private var lastExternalActiveApp: NSRunningApplication?

    private var workspaceActivationObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var hotkeyMonitor: HotkeyMonitor?
    private var hotkeyGestureTimer: Timer?

    private var hotkeyCaptureGlobalMonitor: Any?
    private var hotkeyCaptureLocalMonitor: Any?
    private var hotkeyCaptureTimeoutTimer: Timer?
    private var statusAutoClearTimer: Timer?
    private var isCapturingHotkey = false

    private var isModelDownloadInProgress = false
    private var downloadingModelID: String?
    private var cancelledModelID: String?
    private var currentDownloadProgressText: String?
    private var modelDownloadGeneration: UUID?
    private var modelDownloadTask: Task<Void, Never>?
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
        let tempDir = FileManager.default.temporaryDirectory
        DispatchQueue.global(qos: .utility).async {
            TempFileSweeper.sweep(directory: tempDir)
        }

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
        if let provider = runtime.whisperProvider as? any ModelRetainingTranscriptionProvider {
            let shutdownComplete = DispatchSemaphore(value: 0)
            Task {
                await provider.shutdown()
                shutdownComplete.signal()
            }
            _ = shutdownComplete.wait(timeout: .now() + 1)
        }
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
        promptForAccessibilityPermission()
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
        // A "Download cancelled" badge from an earlier session is stale by the time Settings
        // is reopened; clear it so a freshly-opened window doesn't show an alarming leftover.
        cancelledModelID = nil
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
                cancelDownload: { [weak self] in
                    self?.cancelModelDownload()
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
                setModelOffloadPolicy: { [weak self] policy in
                    self?.setModelOffloadPolicy(policy)
                },
                setKeepTranscriptsInClipboardHistory: { [weak self] keep in
                    self?.mutateSettings { $0.keepTranscriptsInClipboardHistory = keep }
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
                saveDictionaryEntry: { [weak self] originalWrong, wrong, correct, completion in
                    self?.saveDictionaryEntry(
                        originalWrong: originalWrong,
                        wrong: wrong,
                        correct: correct,
                        completion: completion
                    )
                },
                deleteDictionaryEntries: { [weak self] wrongValues, completion in
                    self?.deleteDictionaryEntries(wrongValues: wrongValues, completion: completion)
                },
                recoverDictionary: { [weak self] completion in
                    self?.recoverDictionary(completion: completion)
                },
                openProjectPage: {
                    guard let url = URL(string: "https://github.com/Jetemple/Scrawl") else { return }
                    NSWorkspace.shared.open(url)
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
            downloadingModelID: downloadingModelID,
            cancelledModelID: cancelledModelID,
            downloadProgressText: currentDownloadProgressText
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
                downloadProgressText: currentDownloadProgressText,
                transcriptHistory: runtime.transcriptHistoryStore.records(),
                transcriptHistoryLoadErrorDescription: runtime.transcriptHistoryStore.loadErrorDescription,
                dictionaryEntries: runtime.dictionaryStore.terms().map {
                    DictionaryEntry(wrong: $0.value, correct: $0.value)
                },
                dictionaryLoadErrorDescription: runtime.dictionaryStore.loadErrorDescription
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

    private func setModelOffloadPolicy(_ policy: ModelOffloadPolicy) {
        mutateSettings { $0.modelOffloadPolicy = policy }
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

    private func saveDictionaryEntry(
        originalWrong: String?,
        wrong: String,
        correct: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let store = runtime.dictionaryStore
        dictionaryActionQueue.async { [weak self] in
            let result = Result {
                if let originalWrong {
                    try store.replaceTerm(original: originalWrong, with: correct)
                } else {
                    try store.addTerm(correct)
                }
            }
            DispatchQueue.main.async {
                if case .success = result {
                    self?.refreshPreferencesWindow()
                }
                completion(result)
            }
        }
    }

    private func deleteDictionaryEntries(
        wrongValues: Set<String>,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let store = runtime.dictionaryStore
        dictionaryActionQueue.async { [weak self] in
            let result = Result { try store.deleteTerms(wrongValues) }
            DispatchQueue.main.async {
                if case .success = result {
                    self?.refreshPreferencesWindow()
                }
                completion(result)
            }
        }
    }

    private func recoverDictionary(completion: @escaping (Result<Void, Error>) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Reset Vocabulary?"
        alert.informativeText = "The unreadable vocabulary file will be preserved as a backup before Scrawl creates an empty vocabulary."
        alert.addButton(withTitle: "Reset Vocabulary")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            completion(.success(()))
            return
        }

        let store = runtime.dictionaryStore
        dictionaryActionQueue.async { [weak self] in
            let result = Result { try store.clear() }
            DispatchQueue.main.async {
                if case .success = result {
                    self?.refreshPreferencesWindow()
                }
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

        // Refuse if a recording is active.  stopRecordingAndTranscribe is
        // synchronous only up to the audio-stop; the transcription itself runs
        // in an async Task that will call setState(.idle) when it finishes —
        // which would race with and clobber the hotkeyCapture overlay state.
        // Refusing is the safe choice: it preserves the in-flight recording and
        // gives the user a clear message rather than silently breaking the UI.
        if recordingOrigin != nil {
            runtime.overlayController.showTransientMessage("Stop recording before changing the hotkey")
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
            // Return nil to consume the event so captured keypresses don't
            // also type into the prefs window or trigger window actions.
            // flagsChanged events are not consumed here — they represent
            // modifier key state and returning nil for them causes issues
            // with the event dispatch system.
            if event.type == .keyDown {
                return nil
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
        cancelledModelID = nil // Choosing a model clears any stale "Download cancelled" badge.
        mutateSettings {
            $0.selectedModelID = modelID
            if $0.defaultModelID.isEmpty {
                $0.defaultModelID = modelID
            }
        }
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
        let selected = runtime.settingsStore.load().selectedModelID

        guard modelManager.modelExists(id: selected) else {
            setStatus("No installed model to delete")
            return
        }

        // Build confirmation alert matching existing NSAlert style in this file.
        let displayName = LocalModelManager.downloadableModels
            .first(where: { $0.id == selected })?.displayName
            ?? selected.replacingOccurrences(of: "ggml-", with: "")

        let modelURL = modelManager.modelURL(id: selected)
        var sizeNote = ""
        if let attrs = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
           let bytes = attrs[.size] as? Int64, bytes > 0 {
            let mb = Double(bytes) / (1024 * 1024)
            sizeNote = " (\(String(format: "%.0f", mb)) MB)"
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \"\(displayName)\"?"
        alert.informativeText = "This removes the model file\(sizeNote) from your Mac. You can re-download it later."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try modelManager.deleteModel(id: selected)
            let installed = modelManager.installedModelIDs()
            if let fallback = installed.first {
                mutateSettings { settings in
                    settings.selectedModelID = fallback
                }
                setStatus("Deleted model: \(selected)")
            } else {
                // No models remain — clear the dangling selection so the menu
                // shows a truthful "no model" state and transcription prereq
                // checks prompt the user to download.
                mutateSettings { settings in
                    settings.selectedModelID = ""
                }
                setStatus("No model installed — download one in Settings → Models")
                runtime.overlayController.showTransientMessage(
                    "No model installed — download one in Settings → Models"
                )
            }
        } catch {
            setStatus("Delete failed: \(describe(error))")
        }
    }

    private func cancelModelDownload() {
        // `isModelDownloadInProgress` is the UI's source of truth: it flips true
        // synchronously when the user starts a download — before the async Task registers
        // the operation inside LocalModelManager. Tearing down on this flag (rather than on
        // the manager's return value) guarantees a cancel during that window, or as the
        // download finishes, still resets the UI instead of leaving it stuck on "Downloading".
        guard isModelDownloadInProgress else { return }
        _ = modelManager.cancelDownload()
        let cancelledID = downloadingModelID
        modelDownloadGeneration = nil
        modelDownloadTask?.cancel()
        modelDownloadTask = nil
        isModelDownloadInProgress = false
        downloadingModelID = nil
        cancelledModelID = cancelledID
        currentDownloadProgressText = nil
        refreshModelMenu()
        refreshPreferencesWindow()
        setStatus("Download cancelled")
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
        cancelledModelID = nil
        currentDownloadProgressText = nil
        let downloadGeneration = UUID()
        modelDownloadGeneration = downloadGeneration
        refreshModelMenu()
        refreshPreferencesWindow()
        setStatus("Downloading \(model.displayName)...")

        modelDownloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.modelManager.download(model: model) { [weak self] receivedBytes, totalBytes in
                    guard let self else { return }
                    Task { @MainActor [weak self] in
                        guard let self, self.modelDownloadGeneration == downloadGeneration else { return }
                        let newText = self.downloadProgressText(
                            for: model,
                            receivedBytes: receivedBytes,
                            totalBytes: totalBytes
                        )
                        self.setStatus(newText)
                        // Only rebuild the Models page when the rendered progress string
                        // changes — the callback fires on every URLSession data chunk,
                        // which is far more often than the text visually changes.
                        let progressLabel = self.formatProgressLabel(receivedBytes: receivedBytes, totalBytes: totalBytes)
                        guard progressLabel != self.currentDownloadProgressText else { return }
                        self.currentDownloadProgressText = progressLabel
                        self.refreshPreferencesWindow()
                    }
                }
                await MainActor.run {
                    guard self.modelDownloadGeneration == downloadGeneration else { return }
                    self.mutateSettings {
                        $0.selectedModelID = model.id
                        if $0.defaultModelID.isEmpty {
                            $0.defaultModelID = model.id
                        }
                    }
                    self.setStatus("Downloaded \(model.id)")
                }
            } catch {
                await MainActor.run {
                    guard self.modelDownloadGeneration == downloadGeneration else { return }
                    // User-initiated cancel: the quiet "Download cancelled" status
                    // set by cancelModelDownload() is the only user-visible surface.
                    if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
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
                guard self.modelDownloadGeneration == downloadGeneration else { return }
                self.modelDownloadGeneration = nil
                self.modelDownloadTask = nil
                self.isModelDownloadInProgress = false
                self.downloadingModelID = nil
                self.currentDownloadProgressText = nil
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

    /// Compact progress string shown inline in the Models page row, e.g. "25% (412/1621 MB)".
    private func formatProgressLabel(receivedBytes: Int64, totalBytes: Int64?) -> String {
        let receivedMB = formatMegabytes(receivedBytes)
        guard let totalBytes, totalBytes > 0 else {
            return "\(receivedMB) MB"
        }
        let totalMB = formatMegabytes(totalBytes)
        let ratio = max(0, min(1, Double(receivedBytes) / Double(totalBytes)))
        let percent = Int((ratio * 100).rounded())
        return "\(percent)% (\(receivedMB)/\(totalMB) MB)"
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
            mutateSettings { $0.selectedModelID = fallback }
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

    private func promptForAccessibilityPermission() {
        let isAuthorized = runtime.permissionManager.accessibilityStatus() == .authorized
        cachedAccessibilityAuthorized = isAuthorized

        switch AccessibilityPromptDecision.decide(
            isAuthorized: isAuthorized,
            hasShownSystemPrompt: hasPromptedAccessibilityForHotkeyAttempt
        ) {
        case .alreadyAuthorized:
            hasPromptedAccessibilityForHotkeyAttempt = false
            updatePermissionRows()
            teardownHotkeyHandling()
            setupHotkeyHandling()
            setStatus("Hotkey ready")

        case .showSystemPrompt:
            hasPromptedAccessibilityForHotkeyAttempt = true
            // The macOS prompt already includes an "Open System Settings" button, so we
            // must NOT also open Settings — doing both pops the notification AND the
            // Settings page at once. Settings is reserved for a later still-denied retry.
            _ = runtime.permissionManager.requestAccessibilityAccess(prompt: true)
            cachedAccessibilityAuthorized = runtime.permissionManager.accessibilityStatus() == .authorized
            updatePermissionRows()
            if cachedAccessibilityAuthorized {
                hasPromptedAccessibilityForHotkeyAttempt = false
                teardownHotkeyHandling()
                setupHotkeyHandling()
                setStatus("Hotkey ready")
            } else {
                runtime.overlayController.showTransientMessage("Allow Accessibility for Scrawl, then try again")
                setStatus("Waiting for Accessibility permission")
            }

        case .openSettings:
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
        let recommendedID = runtime.recommendedDefaultModelID

        // Pre-check: skip the write entirely when nothing needs changing.
        // (There is a tiny TOCTOU between this read and the mutate below, but at startup
        // with no concurrent writers that is acceptable.)
        let current = runtime.settingsStore.load()
        let needsChange = !hasStoredSettings
            || current.defaultModelID.isEmpty || current.defaultModelID == "ggml-small"
            || current.selectedModelID.isEmpty || current.selectedModelID == "ggml-small"
        guard needsChange else { return }

        do {
            try runtime.settingsStore.mutate { settings in
                if !hasStoredSettings {
                    settings.defaultModelID = recommendedID
                    settings.selectedModelID = recommendedID
                }
                if settings.defaultModelID.isEmpty || settings.defaultModelID == "ggml-small" {
                    settings.defaultModelID = recommendedID
                }
                if settings.selectedModelID.isEmpty || settings.selectedModelID == "ggml-small" {
                    settings.selectedModelID = settings.defaultModelID
                }
            }
        } catch {
            setStatus("Settings error: \(describe(error))")
            return
        }
        refreshSettingsRows()
        refreshModelMenu()
        refreshPreferencesWindow()
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
            promptForAccessibilityPermission()
            return
        }

        guard validateTranscriptionPrerequisites(origin: origin) else {
            return
        }

        captureInsertionTargetApp()

        do {
            try runtime.audioCaptureService.startCapture()
            let settings = runtime.settingsStore.load()
            if let provider = runtime.whisperProvider as? any ModelRetainingTranscriptionProvider {
                Task {
                    await provider.setIdleOffloadSeconds(settings.modelOffloadPolicy.idleSeconds)
                    await provider.warmUp(modelID: settings.modelID, language: settings.language)
                }
            }
            recordingOrigin = origin
            recordingStartedAt = .now
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
        let recordingDurationMS = recordingStartedAt.map { Int(Date().timeIntervalSince($0) * 1_000) }
        do {
            audioURL = try runtime.audioCaptureService.stopCapture()
        } catch {
            recordingOrigin = nil
            recordingStartedAt = nil
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
        recordingStartedAt = nil
        updateRecordingActionRows()
        runtime.overlayController.setState(.transcribing)
        updateStatusIcon()
        setStatus("Transcribing...")

        let settings = runtime.settingsStore.load()
        let runtime = self.runtime
        let insertionTargetApp = self.insertionTargetApp
        let operationGeneration = activeOperationGeneration.current
        let promptContext = PreferencesContentState.vocabularyPrompt(terms: runtime.dictionaryStore.terms())

        Task { [weak self] in
            defer { try? FileManager.default.removeItem(at: audioURL) }
            do {
                let request = TranscriptionRequest(
                    audioFileURL: audioURL,
                    modelID: settings.modelID,
                    language: settings.language,
                    promptContext: promptContext,
                    progressHandler: { [weak self] event in
                        self?.handleTranscriptionProgress(event)
                    }
                )
                let result = try await runtime.whisperProvider.transcribe(request)
                _ = await self?.pasteToTargetApp(result.text, target: insertionTargetApp)
                await self?.handleTranscriptionSuccess(
                    latencyMS: result.latencyMS,
                    recordingDurationMS: recordingDurationMS,
                    transcript: result.text,
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

        // Stop any active recording before the system sleeps so audio capture
        // is not left open across a lid-close / sleep cycle.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.recordingOrigin != nil else { return }
            self.setStatus("Auto-stopping...")
            self.stopRecordingAndTranscribe(reason: "System sleep")
        }

        // On wake, reset the hotkey gesture state machine so any partially
        // recognised gesture (e.g. a hold that started before sleep) does not
        // fire spuriously when the keyboard becomes active again.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.hotkeyGestureTimer?.invalidate()
            self.hotkeyGestureTimer = nil
            self.runtime.hotkeyStateMachine.reset()
        }
    }

    private func stopObservingWorkspaceActivations() {
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
            self.workspaceActivationObserver = nil
        }
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
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

            // Reject keys that would type visible text (printable characters,
            // arrow keys) — they cannot be used safely as hotkeys because the
            // global monitor cannot swallow keystrokes.
            if !HotkeyCaptureFilter.isAccepted(keyCode: event.keyCode, characters: event.characters) {
                runtime.overlayController.showTransientMessage(
                    "That key types text — choose a modifier, Fn, or a function key."
                )
                // Keep capture active so the user can try another key.
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
        mutateSettings { $0.hotkey = hotkey }
        // The hotkey changed, so rebuild the monitors to listen for the new key. This is also the
        // path that re-arms hotkey handling after a capture session (which tore it down).
        teardownHotkeyHandling()
        setupHotkeyHandling()
        setStatus("Hotkey set: \(hotkey.displayName)")
        runtime.overlayController.showTransientMessage("Hotkey set to \(hotkey.displayName)")
    }

    private func cancelHotkeyCapture(status: String) {
        setStatus(status)
        stopHotkeyCapture()
        setupHotkeyHandling()
        runtime.overlayController.showTransientMessage(status)
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
            let keepInHistory = runtime.settingsStore.load().keepTranscriptsInClipboardHistory
            try await runtime.textOutputTarget.output(text, markPrivate: !keepInHistory)
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

    /// Atomically applies `transform` to the stored settings, then triggers provider
    /// side-effects (model shutdown / idle-offload update) and UI refresh.
    ///
    /// Hotkey monitors are intentionally NOT rebuilt here.  Only `applyHotkey` changes the
    /// hotkey, so rebuilding on every mutate (model select, download completion, launch
    /// defaults) was needless churn — and worse, `teardownHotkeyHandling` resets the gesture
    /// state machine, which could strand an in-progress recording until the 90 s safety
    /// timeout.  The rebuild lives in `applyHotkey`, the one place the hotkey actually changes.
    private func mutateSettings(_ transform: (inout AppSettings) -> Void) {
        do {
            var previousSettings: AppSettings?
            var updatedSettings: AppSettings?
            try runtime.settingsStore.mutate { current in
                previousSettings = current
                transform(&current)
                updatedSettings = current
            }
            if let previousSettings, let updatedSettings,
               let provider = runtime.whisperProvider as? any ModelRetainingTranscriptionProvider {
                Task {
                    if previousSettings.modelID != updatedSettings.modelID {
                        await provider.shutdown()
                    }
                    if previousSettings.modelOffloadPolicy != updatedSettings.modelOffloadPolicy {
                        await provider.setIdleOffloadSeconds(updatedSettings.modelOffloadPolicy.idleSeconds)
                    }
                }
            }
            refreshSettingsRows()
            refreshModelMenu()
            refreshPreferencesWindow()
            // NOTE: hotkey monitors are intentionally NOT rebuilt here — see doc-comment above.
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
        recordingDurationMS: Int?,
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
                try coordinator.add(
                    text: transcript,
                    recordingDurationMS: recordingDurationMS,
                    transcriptionLatencyMS: latencyMS
                )
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
