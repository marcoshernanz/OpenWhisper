import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import OpenWhisperCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let audioRecorder = AudioRecorder()
    private let audioConverter = AudioConverter()
    private let dictationOverlay = DictationOverlayWindowController()
    private lazy var whisperConfiguration = WhisperConfiguration.resolved(bundleURL: Bundle.main.bundleURL)
    private lazy var transcriber = WhisperTranscriber(
        configuration: whisperConfiguration
    )

    private var fnMonitor: FnKeyMonitor?
    private var setupWindowController: PermissionSetupWindowController?
    private var isRecording = false
    private var isTranscribing = false
    private var isWarmingUp = false
    private var isTerminating = false
    private var transcriptionQueue: [URL] = []
    private var accessibilityPromptShown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        warmUpTranscriberIfPossible()
        requestMicrophoneAccess()
        startFnMonitor()
        showSetupWindowIfNeeded()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        isTerminating = true

        let transcriber = self.transcriber
        Task {
            await transcriber.stopServer()
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
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu

        setStatus(.idle)
    }

    private func startFnMonitor() {
        promptForAccessibilityIfNeeded()

        let monitor = FnKeyMonitor { [weak self] isDown in
            Task { @MainActor in
                if isDown {
                    self?.startDictation()
                } else {
                    self?.finishDictation()
                }
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
        guard whisperConfiguration.missingServerRequirementMessage == nil else { return }

        isWarmingUp = true
        setStatus(.warmingUp)

        let transcriber = self.transcriber
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

    private func startDictation() {
        guard !isRecording else { return }

        guard AXIsProcessTrusted() else {
            setStatus(.needsAccessibility)
            showSetupWindow()
            return
        }

        dictationOverlay.show()

        do {
            let overlay = dictationOverlay
            try audioRecorder.start { level in
                Task { @MainActor in
                    overlay.updateLevel(level)
                }
            }
            isRecording = true
            refreshActivityStatus()
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

        let recordingURL = transcriptionQueue.removeFirst()
        isTranscribing = true
        refreshActivityStatus()

        Task {
            do {
                let wavURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("openwhisper-\(UUID().uuidString).wav")
                try await audioConverter.convertToWhisperWav(
                    inputURL: recordingURL,
                    outputURL: wavURL
                )

                let transcript = try await transcriber.transcribe(wavURL: wavURL)
                try? FileManager.default.removeItem(at: recordingURL)
                try? FileManager.default.removeItem(at: wavURL)

                await MainActor.run {
                    self.isTranscribing = false
                    if !transcript.isEmpty {
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
        case .error:
            return "OW !"
        }
    }

    var tooltip: String {
        switch self {
        case .idle:
            return "Hold fn to dictate. Text is inserted after release."
        case .warmingUp:
            return "Loading the local Whisper model."
        case .recording:
            return "Recording. Release fn to transcribe."
        case .transcribing:
            return "Transcribing locally."
        case .needsAccessibility:
            return "Accessibility permission required."
        case .needsMicrophone:
            return "Microphone permission required."
        case .error:
            return "OpenWhisper needs attention."
        }
    }
}
