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
    private lazy var transcriber = WhisperTranscriber(
        configuration: WhisperConfiguration.resolved(bundleURL: Bundle.main.bundleURL)
    )

    private var fnMonitor: FnKeyMonitor?
    private var setupWindowController: PermissionSetupWindowController?
    private var isRecording = false
    private var isTranscribing = false
    private var accessibilityPromptShown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        requestMicrophoneAccess()
        startFnMonitor()
        showSetupWindowIfNeeded()
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
            guard CGPreflightListenEventAccess() else {
                setStatus(.needsInputMonitoring)
                showSetupWindow()
                return
            }

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

    private func startDictation() {
        guard !isRecording, !isTranscribing else { return }

        guard CGPreflightListenEventAccess(), CGPreflightPostEventAccess() else {
            setStatus(.needsAccessibility)
            showSetupWindow()
            return
        }

        do {
            try audioRecorder.start()
            isRecording = true
            setStatus(.recording)
        } catch {
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

        let recordingURL: URL
        do {
            recordingURL = try audioRecorder.stop()
        } catch {
            setStatus(.error)
            return
        }

        isTranscribing = true
        setStatus(.transcribing)

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
                    self.setStatus(.idle)
                    if !transcript.isEmpty {
                        TextInserter.insert(transcript)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isTranscribing = false
                    self.setStatus(.error)
                    self.showOneTimeAlert(
                        title: "Transcription Failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func promptForAccessibilityIfNeeded() {
        guard !CGPreflightPostEventAccess(), !accessibilityPromptShown else { return }
        accessibilityPromptShown = true
        _ = CGRequestPostEventAccess()
    }

    private var permissionsNeedSetup: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
            || !CGPreflightListenEventAccess()
            || !CGPreflightPostEventAccess()
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
                requestKeyboardMonitoringPermission: {
                    _ = CGRequestListenEventAccess()
                },
                openKeyboardMonitoringSettings: {
                    SettingsOpener.openInputMonitoringSettings()
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
                        keyboardMonitoringTrusted: CGPreflightListenEventAccess(),
                        accessibilityTrusted: CGPreflightPostEventAccess()
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
                keyboardMonitoringTrusted: CGPreflightListenEventAccess(),
                accessibilityTrusted: CGPreflightPostEventAccess()
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
    case recording
    case transcribing
    case needsInputMonitoring
    case needsAccessibility
    case needsMicrophone
    case error

    var menuTitle: String {
        switch self {
        case .idle:
            return "OW"
        case .recording:
            return "OW rec"
        case .transcribing:
            return "OW ..."
        case .needsInputMonitoring:
            return "OW keys"
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
        case .recording:
            return "Recording. Release fn to transcribe."
        case .transcribing:
            return "Transcribing locally."
        case .needsInputMonitoring:
            return "Input Monitoring permission required."
        case .needsAccessibility:
            return "Accessibility permission required."
        case .needsMicrophone:
            return "Microphone permission required."
        case .error:
            return "OpenWhisper needs attention."
        }
    }
}
