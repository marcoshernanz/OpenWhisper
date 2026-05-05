import AppKit
import AVFoundation

struct PermissionSetupState {
    let microphoneStatus: AVAuthorizationStatus
    let accessibilityTrusted: Bool
}

@MainActor
final class PermissionSetupWindowController: NSWindowController {
    private let requestMicrophonePermission: () -> Void
    private let openAccessibilitySettings: () -> Void
    private let openMicrophoneSettings: () -> Void
    private let relaunchApp: () -> Void
    private let readState: () -> PermissionSetupState

    private let microphoneStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let microphoneButton = NSButton()
    private let accessibilityButton = NSButton()

    init(
        requestMicrophonePermission: @escaping () -> Void,
        openAccessibilitySettings: @escaping () -> Void,
        openMicrophoneSettings: @escaping () -> Void,
        relaunchApp: @escaping () -> Void,
        readState: @escaping () -> PermissionSetupState
    ) {
        self.requestMicrophonePermission = requestMicrophonePermission
        self.openAccessibilitySettings = openAccessibilitySettings
        self.openMicrophoneSettings = openMicrophoneSettings
        self.relaunchApp = relaunchApp
        self.readState = readState

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenWhisper Setup"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.contentView = makeContentView()
        update(state: readState())
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(state: PermissionSetupState) {
        switch state.microphoneStatus {
        case .authorized:
            microphoneStatusLabel.stringValue = "Allowed"
            microphoneButton.title = "Allowed"
            microphoneButton.isEnabled = false
        case .notDetermined:
            microphoneStatusLabel.stringValue = "Not requested"
            microphoneButton.title = "Allow Microphone"
            microphoneButton.isEnabled = true
        case .denied, .restricted:
            microphoneStatusLabel.stringValue = "Needs approval"
            microphoneButton.title = "Open Microphone Settings"
            microphoneButton.isEnabled = true
        @unknown default:
            microphoneStatusLabel.stringValue = "Needs approval"
            microphoneButton.title = "Open Microphone Settings"
            microphoneButton.isEnabled = true
        }

        accessibilityStatusLabel.stringValue = state.accessibilityTrusted ? "Allowed" : "Needs approval"
        accessibilityButton.title = state.accessibilityTrusted ? "Allowed" : "Open Accessibility Settings"
        accessibilityButton.isEnabled = !state.accessibilityTrusted
    }

    private func makeContentView() -> NSView {
        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Set up OpenWhisper")
        titleLabel.font = .boldSystemFont(ofSize: 22)
        titleLabel.alignment = .center

        let bodyLabel = NSTextField(wrappingLabelWithString: "OpenWhisper runs as a menu bar app. It needs Microphone permission to record while you hold fn, and Accessibility permission to detect fn and paste the final transcript.")
        bodyLabel.alignment = .center
        bodyLabel.textColor = .secondaryLabelColor

        microphoneStatusLabel.alignment = .right
        accessibilityStatusLabel.alignment = .right

        microphoneButton.target = self
        microphoneButton.action = #selector(handleMicrophoneButton)
        microphoneButton.bezelStyle = .rounded

        accessibilityButton.target = self
        accessibilityButton.action = #selector(handleAccessibilityButton)
        accessibilityButton.bezelStyle = .rounded

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshStatus))
        refreshButton.bezelStyle = .rounded

        let relaunchButton = NSButton(title: "Relaunch", target: self, action: #selector(relaunch))
        relaunchButton.bezelStyle = .rounded

        let doneButton = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [
            titleLabel,
            bodyLabel,
            makePermissionRow(
                title: "Microphone",
                statusLabel: microphoneStatusLabel,
                actionButton: microphoneButton
            ),
            makePermissionRow(
                title: "Accessibility",
                statusLabel: accessibilityStatusLabel,
                actionButton: accessibilityButton
            ),
            makeButtonRow(
                refreshButton: refreshButton,
                relaunchButton: relaunchButton,
                doneButton: doneButton
            )
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -24),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bodyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        return rootView
    }

    private func makePermissionRow(
        title: String,
        statusLabel: NSTextField,
        actionButton: NSButton
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)

        let row = NSStackView(views: [titleLabel, statusLabel, actionButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(equalToConstant: 140),
            statusLabel.widthAnchor.constraint(equalToConstant: 120),
            actionButton.widthAnchor.constraint(equalToConstant: 230)
        ])

        return row
    }

    private func makeButtonRow(
        refreshButton: NSButton,
        relaunchButton: NSButton,
        doneButton: NSButton
    ) -> NSView {
        let spacer = NSView()
        let row = NSStackView(views: [spacer, refreshButton, relaunchButton, doneButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: 500)
        ])
        return row
    }

    @objc private func handleMicrophoneButton() {
        switch readState().microphoneStatus {
        case .notDetermined:
            requestMicrophonePermission()
        default:
            openMicrophoneSettings()
        }
        update(state: readState())
    }

    @objc private func handleAccessibilityButton() {
        NSApp.activate(ignoringOtherApps: true)
        openAccessibilitySettings()
        update(state: readState())
    }

    @objc private func refreshStatus() {
        update(state: readState())
    }

    @objc private func closeWindow() {
        window?.close()
    }

    @objc private func relaunch() {
        relaunchApp()
    }
}
