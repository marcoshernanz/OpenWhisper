import Foundation

public struct WhisperTranscriber: Sendable {
    private let configuration: WhisperConfiguration
    private let cleaner: TranscriptionOutputCleaner

    public init(
        configuration: WhisperConfiguration,
        cleaner: TranscriptionOutputCleaner = TranscriptionOutputCleaner()
    ) {
        self.configuration = configuration
        self.cleaner = cleaner
    }

    public func transcribe(wavURL: URL) async throws -> String {
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

    public var errorDescription: String? {
        switch self {
        case .missingRequirement(let message):
            return message
        }
    }
}
