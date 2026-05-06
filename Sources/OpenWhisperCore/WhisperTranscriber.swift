import Foundation

public struct WhisperTranscriber: Sendable {
    private let configuration: WhisperConfiguration
    private let cleaner: TranscriptionOutputCleaner
    private let localCleaner: LocalTranscriptCleaner
    private let serverClient: WhisperServerClient
    private let whisperKitTranscriber: WhisperKitTranscriber

    public init(
        configuration: WhisperConfiguration,
        cleaner: TranscriptionOutputCleaner = TranscriptionOutputCleaner(),
        localCleaner: LocalTranscriptCleaner = LocalTranscriptCleaner()
    ) {
        self.configuration = configuration
        self.cleaner = cleaner
        self.localCleaner = localCleaner
        let serverProcess = WhisperServerProcess(configuration: configuration)
        self.whisperKitTranscriber = WhisperKitTranscriber(configuration: configuration)
        self.serverClient = WhisperServerClient(
            configuration: configuration,
            serverProcess: serverProcess,
            cleaner: cleaner
        )
    }

    public func warmUpServer() async {
        switch configuration.transcriptionEngine {
        case .whisperKit:
            try? await whisperKitTranscriber.warmUp()
        case .whisperCpp:
            try? await serverClient.warmUp()
        }
    }

    public func stopServer() async {
        await serverClient.stop()
    }

    public func transcribe(wavURL: URL) async throws -> String {
        if configuration.transcriptionEngine == .whisperKit {
            do {
                return cleanup(try await whisperKitTranscriber.transcribe(wavURL: wavURL))
            } catch {
                NSLog("OpenWhisper WhisperKit transcription failed, falling back to whisper.cpp: \(error.localizedDescription)")
            }
        }

        return try await transcribeWithWhisperCpp(wavURL: wavURL)
    }

    private func transcribeWithWhisperCpp(wavURL: URL) async throws -> String {
        if configuration.missingServerRequirementMessage == nil {
            do {
                return cleanup(try await serverClient.transcribe(wavURL: wavURL))
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
            return cleanup(cleaner.clean(transcript))
        }

        return cleanup(cleaner.clean(result.stdout))
    }

    private func cleanup(_ transcript: String) -> String {
        localCleaner.clean(transcript, mode: configuration.cleanupMode)
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
