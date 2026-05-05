import Foundation

public struct WhisperTranscriber: Sendable {
    private let configuration: WhisperConfiguration
    private let cleaner: TranscriptionOutputCleaner
    private let serverClient: WhisperServerClient

    public init(
        configuration: WhisperConfiguration,
        cleaner: TranscriptionOutputCleaner = TranscriptionOutputCleaner()
    ) {
        self.configuration = configuration
        self.cleaner = cleaner
        let serverProcess = WhisperServerProcess(configuration: configuration)
        self.serverClient = WhisperServerClient(
            configuration: configuration,
            serverProcess: serverProcess,
            cleaner: cleaner
        )
    }

    public func warmUpServer() async {
        try? await serverClient.warmUp()
    }

    public func stopServer() async {
        await serverClient.stop()
    }

    public func transcribe(wavURL: URL) async throws -> String {
        if configuration.missingServerRequirementMessage == nil {
            do {
                return try await serverClient.transcribe(wavURL: wavURL)
            } catch {
                NSLog("OpenWhisper server transcription failed, falling back to whisper-cli: \(error.localizedDescription)")
            }
        }

        if let missingRequirementMessage = configuration.missingRequirementMessage {
            throw TranscriptionError.missingRequirement(missingRequirementMessage)
        }

        let outputBaseURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("openwhisper-\(UUID().uuidString)")
        let command = WhisperCommand(
            configuration: configuration,
            audioURL: wavURL,
            outputBaseURL: outputBaseURL
        )

        let result = try await Shell.run(
            executableURL: configuration.executableURL,
            arguments: command.arguments
        )

        if let transcript = try? String(contentsOf: command.transcriptURL, encoding: .utf8) {
            try? FileManager.default.removeItem(at: command.transcriptURL)
            return cleaner.clean(transcript)
        }

        return cleaner.clean(result.stdout)
    }
}

public enum TranscriptionError: Error, LocalizedError, Equatable {
    case missingRequirement(String)
    case serverUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .missingRequirement(let message):
            return message
        case .serverUnavailable(let message):
            return "whisper-server is unavailable: \(message)"
        }
    }
}
