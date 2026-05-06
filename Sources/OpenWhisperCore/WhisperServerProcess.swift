import Foundation

public actor WhisperServerProcess {
    private let configuration: WhisperConfiguration
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    public init(configuration: WhisperConfiguration) {
        self.configuration = configuration
    }

    public func warmUp() async throws {
        _ = try await ensureReady()
    }

    public func ensureReady() async throws -> Bool {
        if process?.isRunning == true, await isHealthy() {
            return false
        }

        if process?.isRunning != true {
            await terminateStaleServerIfNeeded()
        }

        try startIfNeeded()
        try await waitUntilHealthy(timeoutSeconds: 60)
        return true
    }

    public func stop() {
        process?.terminate()
        process = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    private func startIfNeeded() throws {
        if process?.isRunning == true {
            return
        }

        if let missingServerRequirementMessage = configuration.missingServerRequirementMessage {
            throw TranscriptionError.missingRequirement(missingServerRequirementMessage)
        }

        let process = Process()
        process.executableURL = configuration.serverExecutableURL
        var arguments = [
            "-m", configuration.modelURL.path,
            "--host", configuration.serverHost,
            "--port", "\(configuration.serverPort)",
            "-t", "\(configuration.serverThreadCount)",
            "-bo", "\(configuration.bestOf)",
            "-bs", "\(configuration.beamSize)",
            "-ac", "\(configuration.audioContext)",
            "-nt",
            "-l", configuration.language
        ]

        if configuration.suppressNonSpeechTokens {
            arguments.append("-sns")
        }

        if !configuration.initialPrompt.isEmpty {
            arguments.append(contentsOf: ["--prompt", configuration.initialPrompt])
        }
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        stdoutPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            _ = fileHandle.availableData
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            _ = fileHandle.availableData
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        do {
            try process.run()
        } catch {
            self.process = nil
            self.stdoutPipe = nil
            self.stderrPipe = nil
            throw ShellError.launchFailed(error.localizedDescription)
        }
    }

    private func waitUntilHealthy(timeoutSeconds: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            if await isHealthy() {
                return
            }

            if let process, !process.isRunning {
                throw ShellError.failed(
                    executable: configuration.serverExecutableURL.path,
                    exitCode: process.terminationStatus,
                    stderr: "whisper-server exited before it became ready."
                )
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        throw TranscriptionError.serverUnavailable("Timed out waiting for whisper-server to load the model.")
    }

    private func terminateStaleServerIfNeeded() async {
        guard await isHealthy() else { return }

        _ = try? await Shell.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/pkill"),
            arguments: [
                "-f",
                "\(configuration.serverExecutableURL.path).*--port \(configuration.serverPort)"
            ]
        )

        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func isHealthy() async -> Bool {
        var request = URLRequest(url: configuration.serverHealthURL)
        request.timeoutInterval = 0.5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
