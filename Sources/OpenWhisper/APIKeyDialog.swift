import AppKit
import OpenWhisperCore

/// Asks for a service's API key, checks it with the service, and saves it in the keychain.
@MainActor
enum APIKeyDialog {
    enum Result {
        case saved(String)
        case removed
        case cancelled
    }

    static func run(for service: CloudService) async -> Result {
        let store = service.keyStore
        let currentKey = store.read()

        let alert = NSAlert()
        alert.messageText = "\(service.displayName) API Key"
        if let currentKey {
            alert.informativeText = """
            OpenWhisper transcribes with \(service.displayName) using the key in your Keychain that ends in \
            \(currentKey.suffix(4)). Paste a new key to replace it.
            """
        } else {
            alert.informativeText = introduction(to: service)
        }

        let field = KeyField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = currentKey == nil ? "\(service.displayName) API key" : "New \(service.displayName) API key"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if currentKey != nil {
            alert.addButton(withTitle: "Remove Key")
        }
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return await save(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), for: service)
        case .alertThirdButtonReturn:
            do {
                try store.delete()
                return .removed
            } catch {
                showProblem("Could Not Remove the Key", error.localizedDescription)
                return .cancelled
            }
        default:
            return .cancelled
        }
    }

    private static func introduction(to service: CloudService) -> String {
        switch service {
        case .openAI:
            return """
            Paste an OpenAI API key to transcribe with OpenAI's GPT Transcribe model. It is saved in your Keychain.

            Recordings are sent to OpenAI, which does not train its models on them unless your account opts \
            in. When OpenAI cannot transcribe a recording, OpenWhisper uses Deepgram if it has a key for it, or \
            transcribes on this Mac.
            """
        case .deepgram:
            return """
            Paste a Deepgram API key to transcribe with Deepgram's Nova-3 model. It is saved in your Keychain.

            Recordings are sent to Deepgram, which is asked not to use them to improve its models. When \
            Deepgram cannot transcribe a recording, OpenWhisper uses OpenAI if it has a key for it, or \
            transcribes on this Mac.
            """
        }
    }

    private static func save(_ key: String, for service: CloudService) async -> Result {
        guard !key.isEmpty else { return .cancelled }

        guard APIKeyStore.isValidKey(key) else {
            showProblem("Key Not Saved", APIKeyStoreError.invalidKey.localizedDescription)
            return .cancelled
        }

        var warning: String?
        do {
            try await service.transcriber(apiKey: key, language: TranscriptionLanguage.auto.rawValue, vocabulary: "")
                .validateKey()
        } catch let error as CloudTranscriptionError where error.needsAttention {
            showProblem("Key Not Saved", "\(error.localizedDescription) Check that you copied all of it.")
            return .cancelled
        } catch {
            warning = "\(service.displayName) could not check the key just now. \(error.localizedDescription)"
        }

        do {
            try service.keyStore.save(key)
        } catch {
            showProblem("Key Not Saved", error.localizedDescription)
            return .cancelled
        }

        if let warning {
            showProblem("Key Saved Without Checking", warning)
        }
        return .saved(key)
    }

    private static func showProblem(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

/// OpenWhisper has no Edit menu, which is what normally lets a text field paste with cmd+V.
private final class KeyField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let action = Self.editActions[event.charactersIgnoringModifiers ?? ""]
        else {
            return super.performKeyEquivalent(with: event)
        }

        return NSApp.sendAction(action, to: nil, from: self)
    }

    private static let editActions: [String: Selector] = [
        "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:)),
        "x": #selector(NSText.cut(_:)),
        "z": Selector(("undo:"))
    ]
}
