import Foundation

public struct AudioConverter: Sendable {
    private let afconvertURL: URL

    public init(afconvertURL: URL = URL(fileURLWithPath: "/usr/bin/afconvert")) {
        self.afconvertURL = afconvertURL
    }

    public func convertToWhisperWav(inputURL: URL, outputURL: URL) async throws {
        _ = try await Shell.run(
            executableURL: afconvertURL,
            arguments: [
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1",
                inputURL.path,
                outputURL.path
            ]
        )
    }
}
