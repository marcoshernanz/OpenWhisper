import AppKit
import OpenWhisperCore

/// Asks for a Deepgram API key, checks it with Deepgram, and saves it in the keychain.
@MainActor
enum DeepgramAPIKeyDialog {
    enum Result {
        case saved(String)
        case removed
        case cancelled
    }

    static func run(store: DeepgramAPIKeyStore = .standard) async -> Result {
        let currentKey = store.read()

        let alert = NSAlert()
        alert.messageText = "Deepgram API Key"
        if let currentKey {
            alert.informativeText = """
            OpenWhisper transcribes with Deepgram using the key in your Keychain that ends in \
            \(currentKey.suffix(4)). Paste a new key to replace it.
            """
        } else {
            alert.informativeText = """
            Paste a Deepgram API key to transcribe with Deepgram's Nova-3 model. It is saved in your Keychain.

            Recordings are sent to Deepgram, which is asked not to use them to improve its models. When \
            Deepgram cannot be reached, OpenWhisper transcribes on this Mac.
            """
        }

        let field = KeyField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = currentKey == nil ? "Deepgram API key" : "New Deepgram API key"
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
            return await save(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), to: store)
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

    private static func save(_ key: String, to store: DeepgramAPIKeyStore) async -> Result {
        guard !key.isEmpty else { return .cancelled }

        guard DeepgramAPIKeyStore.isValidKey(key) else {
            showProblem("Key Not Saved", DeepgramAPIKeyStoreError.invalidKey.localizedDescription)
            return .cancelled
        }

        var warning: String?
        do {
            try await DeepgramTranscriber(apiKey: key, language: TranscriptionLanguage.auto.rawValue, vocabulary: "")
                .validateKey()
        } catch let error as DeepgramError where error.needsAttention {
            showProblem("Key Not Saved", "\(error.localizedDescription) Check that you copied all of it.")
            return .cancelled
        } catch {
            warning = "Deepgram could not check the key just now. \(error.localizedDescription)"
        }

        do {
            try store.save(key)
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
