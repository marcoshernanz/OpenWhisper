import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import OpenWhisperCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let lastTranscriptDefaultsKey = "LastTranscript"

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let audioRecorder = AudioRecorder()
    private let dictationOverlay = DictationOverlayWindowController()
    private var manualPasteHotKeyMonitor: ManualPasteHotKeyMonitor?
    private var whisperConfiguration: WhisperConfiguration?
    private var transcriber: WhisperTranscriber?

    private var fnMonitor: FnKeyMonitor?
    private var setupWindowController: PermissionSetupWindowController?
    private var engineMenuItems: [NSMenuItem] = []
    private var languageMenuItems: [NSMenuItem] = []
    private var qualityMenuItems: [NSMenuItem] = []
    private var modelMenuItems: [NSMenuItem] = []
    private var cleanupMenuItems: [NSMenuItem] = []
    private var transcriberReloadGeneration = 0
    private var isRecording = false
    private var isTranscribing = false
    private var isWarmingUp = false
    private var isTerminating = false
    private var functionKeyGesture = FunctionKeyDictationGesture()
    private var pendingFunctionKeyTapWorkItem: DispatchWorkItem?
    private var transcriptionQueue: [URL] = []
    private var lastTranscript: String?
    private var pasteLastTranscriptMenuItem: NSMenuItem?
    private var accessibilityPromptShown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureTranscriberFromSettings(warmUp: false)
        configureStatusItem()
        restoreLastTranscript()
        warmUpTranscriberIfPossible()
        requestMicrophoneAccess()
        startFnMonitor()
        startManualPasteHotKey()
        showSetupWindowIfNeeded()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        isTerminating = true

        let transcriber = self.transcriber
        Task {
            await transcriber?.stopServer()
            await MainActor.run {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }

        return .terminateLater
    }

    private func configureStatusItem() {
        statusItem.button?.title = "OW"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "OpenWhisper", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Setup Permissions...",
            action: #selector(showSetupWindow),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Open Setup Instructions",
            action: #selector(openSetupInstructions),
            keyEquivalent: ""
        ))
        addSettingsMenus(to: menu)
        menu.addItem(NSMenuItem.separator())
        let pasteLastTranscriptMenuItem = NSMenuItem(
            title: "Paste Last Transcript",
            action: #selector(pasteLastTranscript),
            keyEquivalent: "v"
        )
        pasteLastTranscriptMenuItem.keyEquivalentModifierMask = [.command, .control]
        pasteLastTranscriptMenuItem.isEnabled = false
        pasteLastTranscriptMenuItem.target = self
        menu.addItem(pasteLastTranscriptMenuItem)
        self.pasteLastTranscriptMenuItem = pasteLastTranscriptMenuItem
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu

        updateSettingsMenuItems()
        setStatus(currentReadyStatus)
    }

    private func addSettingsMenus(to menu: NSMenu) {
        let engineMenuItem = NSMenuItem(title: "Engine", action: nil, keyEquivalent: "")
        let engineMenu = NSMenu()
        engineMenuItems = LocalTranscriptionEngine.allCases.map { engine in
            let item = NSMenuItem(
                title: engine.displayName,
                action: #selector(selectTranscriptionEngine(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = engine.rawValue
            engineMenu.addItem(item)
            return item
        }
        menu.addItem(engineMenuItem)
        menu.setSubmenu(engineMenu, for: engineMenuItem)

        let languageMenuItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        languageMenuItems = TranscriptionLanguage.allCases.map { language in
            let item = NSMenuItem(
                title: language.displayName,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.rawValue
            languageMenu.addItem(item)
            return item
        }
        menu.addItem(languageMenuItem)
        menu.setSubmenu(languageMenu, for: languageMenuItem)

        let qualityMenuItem = NSMenuItem(title: "Quality", action: nil, keyEquivalent: "")
        let qualityMenu = NSMenu()
        qualityMenuItems = TranscriptionQualityProfile.allCases.map { profile in
            let item = NSMenuItem(
                title: profile.displayName,
                action: #selector(selectQualityProfile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = profile.rawValue
            qualityMenu.addItem(item)
            return item
        }
        menu.addItem(qualityMenuItem)
        menu.setSubmenu(qualityMenu, for: qualityMenuItem)

        let modelMenuItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        modelMenuItems = WhisperModelOption.allCases.map { option in
            let item = NSMenuItem(
                title: option.displayName,
                action: #selector(selectModelOption(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = option.rawValue
            modelMenu.addItem(item)
            return item
        }
        menu.addItem(modelMenuItem)
        menu.setSubmenu(modelMenu, for: modelMenuItem)

        let cleanupMenuItem = NSMenuItem(title: "Cleanup", action: nil, keyEquivalent: "")
        let cleanupMenu = NSMenu()
        cleanupMenuItems = TranscriptCleanupMode.allCases.map { mode in
            let item = NSMenuItem(
                title: mode.displayName,
                action: #selector(selectCleanupMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            cleanupMenu.addItem(item)
            return item
        }
        menu.addItem(cleanupMenuItem)
        menu.setSubmenu(cleanupMenu, for: cleanupMenuItem)
    }

    private func configureTranscriberFromSettings(warmUp: Bool = true) {
        let previousTranscriber = transcriber
        let configuration = WhisperConfiguration.resolved(bundleURL: Bundle.main.bundleURL)
        let nextTranscriber = WhisperTranscriber(configuration: configuration)
        transcriberReloadGeneration += 1
        let generation = transcriberReloadGeneration

        whisperConfiguration = configuration
        updateSettingsMenuItems()

        guard warmUp else {
            transcriber = nextTranscriber
            return
        }

        transcriber = nil
        isWarmingUp = true
        refreshActivityStatus()

        Task {
            await previousTranscriber?.stopServer()

            await MainActor.run {
                guard self.transcriberReloadGeneration == generation else { return }
                self.transcriber = nextTranscriber
            }

            if configuration.canWarmUpTranscriber {
                await nextTranscriber.warmUpServer()
            }

            await MainActor.run {
                guard self.transcriberReloadGeneration == generation else { return }
                self.isWarmingUp = false
                self.refreshActivityStatus()
            }
        }
    }

    private func updateSettingsMenuItems() {
        guard let whisperConfiguration else { return }

        for item in engineMenuItems {
            let engine = LocalTranscriptionEngine(rawValue: item.representedObject as? String ?? "")
            item.state = engine == whisperConfiguration.transcriptionEngine ? .on : .off
        }

        for item in languageMenuItems {
            let language = TranscriptionLanguage(rawValue: item.representedObject as? String ?? "")
            item.state = language?.rawValue == whisperConfiguration.language ? .on : .off
        }

        for item in qualityMenuItems {
            let profile = TranscriptionQualityProfile(rawValue: item.representedObject as? String ?? "")
            item.state = profile == whisperConfiguration.qualityProfile ? .on : .off
        }

        for item in modelMenuItems {
            guard let option = WhisperModelOption(rawValue: item.representedObject as? String ?? "") else {
                continue
            }

            let modelURL = modelURL(for: option)
            let isInstalled = FileManager.default.fileExists(atPath: modelURL.path)
            item.title = isInstalled ? option.displayName : "\(option.displayName) - Download Required"
            item.state = option == whisperConfiguration.modelOption ? .on : .off
        }

        for item in cleanupMenuItems {
            let mode = TranscriptCleanupMode(rawValue: item.representedObject as? String ?? "")
            item.state = mode == whisperConfiguration.cleanupMode ? .on : .off
        }
    }

    private func modelURL(for option: WhisperModelOption) -> URL {
        let modelsDirectory = whisperConfiguration?.modelURL.deletingLastPathComponent()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Models")

        return modelsDirectory.appendingPathComponent(option.fileName)
    }

    private func startFnMonitor() {
        promptForAccessibilityIfNeeded()

        let monitor = FnKeyMonitor { [weak self] isDown in
            Task { @MainActor in
                self?.handleFunctionKeyChange(isDown: isDown)
            }
        }

        do {
            try monitor.start()
            fnMonitor = monitor
        } catch {
            setStatus(.needsAccessibility)
            showSetupWindow()
        }
    }

    private func startManualPasteHotKey() {
        let monitor = ManualPasteHotKeyMonitor { [weak self] in
            Task { @MainActor in
                self?.pasteLastTranscript()
            }
        }

        do {
            try monitor.start()
            manualPasteHotKeyMonitor = monitor
        } catch {
            NSLog("OpenWhisper paste shortcut registration failed: \(error.localizedDescription)")
        }
    }

    private func requestMicrophoneAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    if !granted {
                        self?.setStatus(.needsMicrophone)
                        self?.showSetupWindow()
                    } else {
                        self?.updateSetupWindow()
                    }
                }
            }
        default:
            setStatus(.needsMicrophone)
        }
    }

    private func warmUpTranscriberIfPossible() {
        guard let whisperConfiguration,
              let transcriber,
              whisperConfiguration.canWarmUpTranscriber
        else {
            return
        }

        isWarmingUp = true
        setStatus(.warmingUp)

        Task {
            await transcriber.warmUpServer()
            await MainActor.run {
                self.isWarmingUp = false
                if !self.isRecording && !self.isTranscribing {
                    self.setStatus(self.currentReadyStatus)
                }
            }
        }
    }

    private func handleFunctionKeyChange(isDown: Bool) {
        let timestamp = currentFunctionKeyTimestamp()

        if isDown {
            handleFunctionKeyGestureAction(functionKeyGesture.expirePendingTap(at: timestamp))
            handleFunctionKeyGestureAction(functionKeyGesture.keyDown(at: timestamp))
        } else {
            handleFunctionKeyGestureAction(functionKeyGesture.keyUp(at: timestamp))
        }
    }

    private func handleFunctionKeyGestureAction(_ action: FunctionKeyDictationGesture.Action) {
        switch action {
        case .none:
            break
        case .startRecording:
            cancelPendingFunctionKeyTap()
            if !startDictation() {
                functionKeyGesture.cancel()
            }
        case .finishRecording:
            cancelPendingFunctionKeyTap()
            finishDictation()
        case .waitForSecondTap(let deadline):
            schedulePendingFunctionKeyTap(deadline: deadline)
        case .lockRecording:
            cancelPendingFunctionKeyTap()
            refreshActivityStatus()
        }
    }

    private func schedulePendingFunctionKeyTap(deadline: TimeInterval) {
        cancelPendingFunctionKeyTap()

        let delay = max(0, deadline - currentFunctionKeyTimestamp())
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.handleFunctionKeyGestureAction(
                self.functionKeyGesture.expirePendingTap(at: self.currentFunctionKeyTimestamp())
            )
        }
        pendingFunctionKeyTapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPendingFunctionKeyTap() {
        pendingFunctionKeyTapWorkItem?.cancel()
        pendingFunctionKeyTapWorkItem = nil
    }

    private func currentFunctionKeyTimestamp() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    @discardableResult
    private func startDictation() -> Bool {
        guard !isRecording else { return false }

        guard AXIsProcessTrusted() else {
            setStatus(.needsAccessibility)
            showSetupWindow()
            return false
        }

        dictationOverlay.show()
        warmTranscriberDuringRecording()

        do {
            let overlay = dictationOverlay
            try audioRecorder.start { level in
                Task { @MainActor in
                    overlay.updateLevel(level)
                }
            }
            isRecording = true
            refreshActivityStatus()
            return true
        } catch {
            dictationOverlay.hide()
            setStatus(.error)
            if permissionsNeedSetup {
                showSetupWindow()
            } else {
                showOneTimeAlert(
                    title: "Could Not Start Recording",
                    message: error.localizedDescription
                )
            }
            return false
        }
    }

    private func warmTranscriberDuringRecording() {
        guard let whisperConfiguration,
              let transcriber,
              whisperConfiguration.canWarmUpTranscriber
        else {
            return
        }

        Task {
            await transcriber.warmUpServer()
        }
    }

    private func finishDictation() {
        guard isRecording else { return }
        isRecording = false
        dictationOverlay.hide()

        let recordingURL: URL
        do {
            recordingURL = try audioRecorder.stop()
        } catch {
            dictationOverlay.hide()
            setStatus(.error)
            return
        }

        enqueueForTranscription(recordingURL)
    }

    private func enqueueForTranscription(_ recordingURL: URL) {
        transcriptionQueue.append(recordingURL)
        processNextQueuedRecording()
        refreshActivityStatus()
    }

    private func processNextQueuedRecording() {
        guard !isTranscribing else {
            refreshActivityStatus()
            return
        }

        guard !transcriptionQueue.isEmpty else {
            refreshActivityStatus()
            return
        }

        guard let transcriber else {
            refreshActivityStatus()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.processNextQueuedRecording()
            }
            return
        }

        let recordingURL = transcriptionQueue.removeFirst()
        isTranscribing = true
        refreshActivityStatus()

        Task {
            do {
                let transcript = try await transcriber.transcribe(wavURL: recordingURL)
                try? FileManager.default.removeItem(at: recordingURL)

                await MainActor.run {
                    self.isTranscribing = false
                    if !transcript.isEmpty {
                        self.rememberTranscript(transcript)
                        TextInserter.insert(transcript)
                    }
                    self.processNextQueuedRecording()
                }
            } catch {
                try? FileManager.default.removeItem(at: recordingURL)

                await MainActor.run {
                    self.isTranscribing = false
                    self.setStatus(.error)
                    self.showOneTimeAlert(
                        title: "Transcription Failed",
                        message: error.localizedDescription
                    )
                    self.processNextQueuedRecording()
                }
            }
        }
    }

    private func promptForAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted(), !accessibilityPromptShown else { return }
        accessibilityPromptShown = true
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private var permissionsNeedSetup: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
            || !AXIsProcessTrusted()
    }

    private var currentReadyStatus: AppStatus {
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            return .needsMicrophone
        }

        if !AXIsProcessTrusted() {
            return .needsAccessibility
        }

        if whisperConfiguration?.transcriptionEngine == .whisperCpp,
           whisperConfiguration?.missingServerRequirementMessage != nil {
            return .missingModel
        }

        return isWarmingUp ? .warmingUp : .idle
    }

    private func refreshActivityStatus() {
        if isRecording {
            setStatus(.recording)
        } else if isTranscribing || !transcriptionQueue.isEmpty {
            setStatus(.transcribing)
        } else {
            setStatus(currentReadyStatus)
        }
    }

    private func restoreLastTranscript() {
        guard let transcript = UserDefaults.standard.string(forKey: Self.lastTranscriptDefaultsKey),
              !transcript.isEmpty
        else {
            return
        }

        rememberTranscript(transcript)
    }

    private func rememberTranscript(_ transcript: String) {
        lastTranscript = transcript
        UserDefaults.standard.set(transcript, forKey: Self.lastTranscriptDefaultsKey)
        pasteLastTranscriptMenuItem?.isEnabled = true
    }

    private func showSetupWindowIfNeeded() {
        guard permissionsNeedSetup else { return }
        showSetupWindow()
    }

    @objc private func showSetupWindow() {
        if setupWindowController == nil {
            setupWindowController = PermissionSetupWindowController(
                requestMicrophonePermission: { [weak self] in
                    self?.requestMicrophoneAccess()
                },
                openAccessibilitySettings: {
                    SettingsOpener.openAccessibilitySettings()
                },
                openMicrophoneSettings: {
                    SettingsOpener.openMicrophoneSettings()
                },
                relaunchApp: {
                    AppRelauncher.relaunch()
                },
                readState: {
                    PermissionSetupState(
                        microphoneStatus: AVCaptureDevice.authorizationStatus(for: .audio),
                        accessibilityTrusted: AXIsProcessTrusted()
                    )
                }
            )
        }

        updateSetupWindow()
        setupWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateSetupWindow() {
        setupWindowController?.update(
            state: PermissionSetupState(
                microphoneStatus: AVCaptureDevice.authorizationStatus(for: .audio),
                accessibilityTrusted: AXIsProcessTrusted()
            )
        )
    }

    private func setStatus(_ status: AppStatus) {
        statusItem.button?.title = status.menuTitle
        statusItem.button?.toolTip = status.tooltip
    }

    private func showOneTimeAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func openSetupInstructions() {
        NSWorkspace.shared.open(readmeURL())
    }

    @objc private func selectTranscriptionEngine(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              LocalTranscriptionEngine(rawValue: rawValue) != nil
        else {
            return
        }

        UserDefaults.standard.set(rawValue, forKey: OpenWhisperDefaultsKey.transcriptionEngine)
        configureTranscriberFromSettings()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              TranscriptionLanguage(rawValue: rawValue) != nil
        else {
            return
        }

        UserDefaults.standard.set(rawValue, forKey: OpenWhisperDefaultsKey.language)
        configureTranscriberFromSettings()
    }

    @objc private func selectQualityProfile(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              TranscriptionQualityProfile(rawValue: rawValue) != nil
        else {
            return
        }

        UserDefaults.standard.set(rawValue, forKey: OpenWhisperDefaultsKey.qualityProfile)
        configureTranscriberFromSettings()
    }

    @objc private func selectModelOption(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let option = WhisperModelOption(rawValue: rawValue)
        else {
            return
        }

        let url = modelURL(for: option)
        guard FileManager.default.fileExists(atPath: url.path) else {
            showOneTimeAlert(
                title: "Model Not Installed",
                message: "Install it first from the repo with:\n\nscripts/setup-whisper.sh \(option.setupArgument)"
            )
            updateSettingsMenuItems()
            return
        }

        UserDefaults.standard.set(rawValue, forKey: OpenWhisperDefaultsKey.modelOption)
        configureTranscriberFromSettings()
    }

    @objc private func selectCleanupMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              TranscriptCleanupMode(rawValue: rawValue) != nil
        else {
            return
        }

        UserDefaults.standard.set(rawValue, forKey: OpenWhisperDefaultsKey.cleanupMode)
        configureTranscriberFromSettings()
    }

    @objc private func pasteLastTranscript() {
        guard let transcript = lastTranscript ?? UserDefaults.standard.string(forKey: Self.lastTranscriptDefaultsKey),
              !transcript.isEmpty
        else {
            NSSound.beep()
            return
        }

        waitForManualPasteModifiersThenInsert(transcript, attemptsRemaining: 40)
    }

    private func waitForManualPasteModifiersThenInsert(_ transcript: String, attemptsRemaining: Int) {
        let flags = CGEventSource.flagsState(.hidSystemState)
        let modifiersAreStillDown = flags.contains(.maskCommand) || flags.contains(.maskControl)

        guard modifiersAreStillDown, attemptsRemaining > 0 else {
            TextInserter.insert(transcript)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            self?.waitForManualPasteModifiersThenInsert(
                transcript,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func readmeURL() -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app",
           bundleURL.deletingLastPathComponent().lastPathComponent == ".build" {
            return bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("README.md")
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return currentDirectory.appendingPathComponent("README.md")
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private enum AppStatus {
    case idle
    case warmingUp
    case recording
    case transcribing
    case needsAccessibility
    case needsMicrophone
    case missingModel
    case error

    var menuTitle: String {
        switch self {
        case .idle:
            return "OW"
        case .warmingUp:
            return "OW load"
        case .recording:
            return "OW rec"
        case .transcribing:
            return "OW ..."
        case .needsAccessibility:
            return "OW AX"
        case .needsMicrophone:
            return "OW mic"
        case .missingModel:
            return "OW model"
        case .error:
            return "OW !"
        }
    }

    var tooltip: String {
        switch self {
        case .idle:
            return "Hold fn to dictate, double-press fn to lock recording, or press ctrl+cmd+V to paste the last transcript."
        case .warmingUp:
            return "Loading the local Whisper model."
        case .recording:
            return "Recording. Release fn to transcribe, or press fn again after double-tap to stop."
        case .transcribing:
            return "Transcribing locally."
        case .needsAccessibility:
            return "Accessibility permission required."
        case .needsMicrophone:
            return "Microphone permission required."
        case .missingModel:
            return "Selected Whisper model is not installed."
        case .error:
            return "OpenWhisper needs attention."
        }
    }
}

private extension WhisperConfiguration {
    var canWarmUpTranscriber: Bool {
        transcriptionEngine == .whisperKit || missingServerRequirementMessage == nil
    }
}
