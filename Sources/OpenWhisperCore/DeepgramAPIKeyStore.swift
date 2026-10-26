import Foundation

/// Keeps the Deepgram API key in the login keychain, where this saves it:
///
///     security add-generic-password -s dev.openwhisper.deepgram -a api-key -w
///
/// It goes through the `security` tool rather than the Security framework. OpenWhisper is signed ad hoc, so
/// the keychain sees every build as a different app, and reading a key through the framework would ask for
/// the login password after every update. Items that `security` creates trust `security` itself.
public struct DeepgramAPIKeyStore: Sendable {
    public static let standard = DeepgramAPIKeyStore(service: "dev.openwhisper.deepgram")

    private let service: String
    private let account = "api-key"

    public init(service: String) {
        self.service = service
    }

    /// Blocks until the keychain answers, which takes a few milliseconds, without running the run loop.
    public func read() -> String? {
        guard let result = try? Self.runSecurity(["find-generic-password", "-s", service, "-a", account, "-w"]),
              result.exitCode == 0
        else {
            return nil
        }

        let key = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// The key goes to `security` on its standard input rather than its arguments, which other processes can
    /// read while it runs.
    public func save(_ key: String) throws {
        guard Self.isValidKey(key) else {
            throw DeepgramAPIKeyStoreError.invalidKey
        }

        let command = "add-generic-password -U -s \"\(service)\" -a \"\(account)\" -l \"OpenWhisper Deepgram API key\" -w \"\(key)\"\n"
        let result = try Self.runSecurity(["-i"], input: command)

        // `security -i` exits successfully even when a command in it fails.
        guard read() == key else {
            throw DeepgramAPIKeyStoreError.couldNotSave(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func delete() throws {
        let result = try Self.runSecurity(["delete-generic-password", "-s", service, "-a", account])

        // 44 means there was no key to delete.
        guard result.exitCode == 0 || result.exitCode == 44 else {
            throw DeepgramAPIKeyStoreError.couldNotDelete(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Deepgram keys are 40 hexadecimal characters. Other tokens are accepted as long as they cannot break
    /// out of the quotes in the `security` command.
    public static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty
            && key.count <= 512
            && key.unicodeScalars.allSatisfy { allowedKeyCharacters.contains($0) }
    }

    private static let allowedKeyCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        .intersection(CharacterSet(charactersIn: Unicode.Scalar(0x21)...Unicode.Scalar(0x7E)))

    private static func runSecurity(_ arguments: [String], input: String? = nil) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        // Process.waitUntilExit runs the run loop, which would handle fn presses in the middle of this.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        try process.run()
        if let input {
            stdinPipe.fileHandleForWriting.write(Data(input.utf8))
        }
        try stdinPipe.fileHandleForWriting.close()

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        exited.wait()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout, encoding: .utf8) ?? "",
            stderr: String(data: stderr, encoding: .utf8) ?? ""
        )
    }
}

public enum DeepgramAPIKeyStoreError: Error, LocalizedError, Equatable {
    case invalidKey
    case couldNotSave(String)
    case couldNotDelete(String)

    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "That doesn't look like a Deepgram API key. Keys are made of letters and numbers."
        case .couldNotSave(let detail):
            return detail.isEmpty ? "The key could not be saved in the keychain." : "The key could not be saved in the keychain: \(detail)"
        case .couldNotDelete(let detail):
            return detail.isEmpty ? "The key could not be removed from the keychain." : "The key could not be removed from the keychain: \(detail)"
        }
    }
}
