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
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        let filtered = words.filter { word in
            let normalized = word
                .trimmingCharacters(in: .punctuationCharacters)
                .lowercased()

            return !["um", "uh", "erm", "ah"].contains(normalized)
        }

        return filtered.joined(separator: " ")
    }

    private func finalizeDictation(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = capitalizeSentenceStarts(text)
        if let last = result.unicodeScalars.last,
           CharacterSet.alphanumerics.contains(last) {
            result.append(".")
        }

        return result
    }

    private func capitalizeSentenceStarts(_ text: String) -> String {
        var result = ""
        var shouldCapitalize = true

        for character in text {
            if shouldCapitalize, character.isLetter {
                result.append(String(character).uppercased())
                shouldCapitalize = false
            } else {
                result.append(character)
                if character.isLetter || character.isNumber {
                    shouldCapitalize = false
                }
            }

            if ".!?".contains(character) {
                shouldCapitalize = true
            }
        }

        return result
    }
}
