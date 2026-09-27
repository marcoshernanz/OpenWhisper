import Foundation

public struct LocalTranscriptCleaner: Sendable {
    public init() {}

    public func clean(_ transcript: String, mode: TranscriptCleanupMode) -> String {
        let normalized = normalizeWhitespace(transcript)

        switch mode {
        case .off:
            return normalized
        case .light:
            return normalizePunctuation(normalized)
        case .dictation:
            return finalizeDictation(normalizePunctuation(removeStandaloneFillers(from: normalized)))
        }
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizePunctuation(_ text: String) -> String {
        var result = text
        let replacements = [
            " ,": ",",
            " .": ".",
            " !": "!",
            " ?": "?",
            " ;": ";",
            " :": ":",
            "( ": "(",
            " )": ")",
            "[ ": "[",
            " ]": "]"
        ]

        for (source, target) in replacements {
            result = result.replacingOccurrences(of: source, with: target)
        }

        while result.contains("..") {
            result = result.replacingOccurrences(of: "..", with: ".")
        }

        while result.contains(",,") {
            result = result.replacingOccurrences(of: ",,", with: ",")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removeStandaloneFillers(from text: String) -> String {
        var kept: [String] = []
        var capitalizeNextWord = false

        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            let normalized = word
                .trimmingCharacters(in: .punctuationCharacters)
                .lowercased()

            if ["um", "uh", "erm"].contains(normalized) {
                // "It works. Um, next" should become "It works. Next".
                capitalizeNextWord = capitalizeNextWord || word.first?.isUppercase == true
                continue
            }

            kept.append(capitalizeNextWord ? word.prefix(1).uppercased() + word.dropFirst() : String(word))
            capitalizeNextWord = false
        }

        return kept.joined(separator: " ")
    }

    private func finalizeDictation(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = capitalizeFirstLetter(text)
        if let last = result.unicodeScalars.last,
           CharacterSet.alphanumerics.contains(last) {
            result.append(".")
        }

        return result
    }

    /// Whisper already capitalizes its sentences. Only the first letter needs fixing, and treating
    /// every "." as a sentence end would turn "developer.apple.com" into "developer.Apple.Com".
    private func capitalizeFirstLetter(_ text: String) -> String {
        guard let index = text.firstIndex(where: \.isLetter) else { return text }

        return text.replacingCharacters(in: index...index, with: text[index].uppercased())
    }
}
