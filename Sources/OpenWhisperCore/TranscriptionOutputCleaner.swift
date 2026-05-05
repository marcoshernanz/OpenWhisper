import Foundation

public struct TranscriptionOutputCleaner: Sendable {
    public init() {}

    public func clean(_ rawOutput: String) -> String {
        let strippedANSI = rawOutput.replacing(
            #/\u{001B}\[[0-9;]*[A-Za-z]/#,
            with: ""
        )

        let cleanedLines = strippedANSI
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine -> String? in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return nil }
                guard !isWhisperLogLine(line) else { return nil }
                return removeTimestampPrefix(from: line)
            }

        return cleanedLines
            .joined(separator: " ")
            .replacing(#/\s+/#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isWhisperLogLine(_ line: String) -> Bool {
        let prefixes = [
            "whisper_",
            "ggml_",
            "main:",
            "system_info:",
            "error:",
            "warning:",
            "output_txt:",
            "sampling:",
            "encode:",
            "decode:"
        ]

        return prefixes.contains { line.localizedCaseInsensitiveCompare($0) == .orderedSame }
            || prefixes.contains { line.lowercased().hasPrefix($0) }
    }

    private func removeTimestampPrefix(from line: String) -> String {
        guard line.hasPrefix("["),
              let closeBracket = line.firstIndex(of: "]")
        else {
            return line
        }

        let afterBracket = line[line.index(after: closeBracket)...]
        return afterBracket.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
