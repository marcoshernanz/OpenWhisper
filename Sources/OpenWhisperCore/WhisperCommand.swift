import Foundation

public struct WhisperCommand: Sendable, Equatable {
    public let configuration: WhisperConfiguration
    public let audioURL: URL
    public let outputBaseURL: URL

    public init(
        configuration: WhisperConfiguration,
        audioURL: URL,
        outputBaseURL: URL
    ) {
        self.configuration = configuration
        self.audioURL = audioURL
        self.outputBaseURL = outputBaseURL
    }

    public var arguments: [String] {
        var arguments = [
            "-m", configuration.modelURL.path,
            "-f", audioURL.path,
            "-otxt",
            "-of", outputBaseURL.path,
            "-nt",
            "-l", configuration.language,
            "-bo", "\(configuration.bestOf)",
            "-bs", "\(configuration.beamSize)",
            "-ac", "\(configuration.audioContext)",
            "-tp", format(configuration.temperature),
            "-tpi", format(configuration.temperatureIncrement),
            "-np"
        ]

        if configuration.suppressNonSpeechTokens {
            arguments.append("-sns")
        }

        if !configuration.initialPrompt.isEmpty {
            arguments.append(contentsOf: ["--prompt", configuration.initialPrompt])
        }

        return arguments
    }

    public var transcriptURL: URL {
        URL(fileURLWithPath: outputBaseURL.path + ".txt")
    }

    private func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(value)
    }
}
