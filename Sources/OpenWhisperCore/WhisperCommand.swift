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
        [
            "-m", configuration.modelURL.path,
            "-f", audioURL.path,
            "-otxt",
            "-of", outputBaseURL.path,
            "-nt",
            "-l", configuration.language,
            "-np"
        ]
    }

    public var transcriptURL: URL {
        URL(fileURLWithPath: outputBaseURL.path + ".txt")
    }
}
