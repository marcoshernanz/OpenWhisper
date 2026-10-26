import Foundation

/// Transcribes a recording with Deepgram's Nova-3, its most accurate model. A dictation of several minutes
/// comes back in seconds.
public struct DeepgramTranscriber: CloudTranscriber {
    public let service = CloudService.deepgram
    private let apiKey: String
    private let language: String
    private let keyterms: [String]
    private let baseURL: URL
    private let connection: CloudConnection
    private let multilingualModel = PinnedModel()

    public init(
        apiKey: String,
        language: String,
        vocabulary: String,
        baseURL: URL = DeepgramTranscriber.defaultBaseURL,
        session: URLSession = .shared,
        retryDelay: Duration = .seconds(1)
    ) {
        self.apiKey = apiKey
        self.language = language
        self.keyterms = Self.keyterms(fromVocabulary: vocabulary)
        self.baseURL = baseURL
        self.connection = CloudConnection(
            service: .deepgram,
            session: session,
            retryDelay: retryDelay,
            problem: Self.problem(statusCode:body:)
        )
    }

    public static let defaultBaseURL = URL(string: "https://api.deepgram.com")!

    public func warmUp() async {
        await connection.warmUp(baseURL)
    }

    public func transcribe(wavURL: URL) async throws -> String {
        let recording = try Data(contentsOf: wavURL)
        let audio = WAVFile.paddingWithSilence(Self.padding, around: recording) ?? recording

        guard language == TranscriptionLanguage.auto.rawValue else {
            return try await transcribe(audio, at: listenURL(pinningMultilingualModel: false))
        }

        guard multilingualModel.isAvailable else {
            return try await transcribe(audio, at: listenURL(pinningMultilingualModel: false))
        }

        do {
            return try await transcribe(audio, at: listenURL(pinningMultilingualModel: true))
        } catch let error as CloudTranscriptionError {
            guard case .rejectedRequest(let message) = error.problem else { throw error }

            // Deepgram retires old versions of its models eventually.
            NSLog("OpenWhisper retrying Deepgram with its newest multilingual model after: \(message)")
            let transcript = try await transcribe(audio, at: listenURL(pinningMultilingualModel: false))
            multilingualModel.isAvailable = false
            return transcript
        }
    }

    private func transcribe(_ audio: Data, at url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.timeout(forRecordingBytes: audio.count)
        request.httpBody = audio

        let data = try await connection.dataRetrying(for: request)
        guard let response = try? JSONDecoder().decode(ListenResponse.self, from: data),
              let alternative = response.results.channels.first?.alternatives.first
        else {
            throw CloudTranscriptionError(.deepgram, .invalidResponse)
        }

        return alternative.transcript
    }

    /// Checks the key without sending any audio.
    public func validateKey() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/auth/token"))
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        _ = try await connection.data(for: request)
    }

    /// Multilingual Nova-3 follows a switch between English and Spanish in the middle of a sentence, where a
    /// single language garbles the other one, and detecting one language misjudges short dictations.
    ///
    /// Its October 2026 version covers 55 languages instead of 10, and was less accurate in English and
    /// Spanish: on synthesized dictations it made three times the errors in mixed ones, and turned a short
    /// Spanish one into Arabic script. The January version made no errors in 32 short dictations.
    func listenURL(pinningMultilingualModel: Bool) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/listen"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "smart_format", value: "true"),
            // Deepgram does not use the audio to train its models.
            URLQueryItem(name: "mip_opt_out", value: "true")
        ]

        if language == TranscriptionLanguage.auto.rawValue {
            items.append(URLQueryItem(name: "language", value: "multi"))
            if pinningMultilingualModel {
                // It does not take language hints.
                items.append(URLQueryItem(name: "version", value: Self.multilingualModelVersion))
            } else {
                items.append(URLQueryItem(name: "language_hint", value: TranscriptionLanguage.english.rawValue))
                items.append(URLQueryItem(name: "language_hint", value: TranscriptionLanguage.spanish.rawValue))
            }
        } else {
            items.append(URLQueryItem(name: "language", value: language))
        }

        items += keyterms.map { URLQueryItem(name: "keyterm", value: $0) }
        components.queryItems = items

        // URLComponents leaves "+" alone, which Deepgram reads as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// Deepgram takes each term of the vocabulary separately and rejects a request with more than 500 tokens
    /// of them, so the list stops at what fits.
    static func keyterms(fromVocabulary vocabulary: String) -> [String] {
        var keyterms: [String] = []
        var estimatedTokens = 0

        for term in Vocabulary.terms(in: vocabulary) {
            let tokens = term.utf8.count
            guard estimatedTokens + tokens <= maxKeytermTokens else { break }
            estimatedTokens += tokens
            keyterms.append(term)
        }

        return keyterms
    }

    /// Deepgram drops a word right at the start or the end of the audio, which is where a dictation that
    /// starts recording late on a busy Mac, or that stops as the last word ends, has one.
    private static let padding: TimeInterval = 0.5
    /// More accurate in English and Spanish than the October 2026 version, which covers more languages.
    static let multilingualModelVersion = "2026-01-27.9107"
    /// Deepgram does not say how it counts tokens. Its limit measured at 476 to 568 characters, so this counts
    /// a token for every byte and stays under the lowest.
    private static let maxKeytermTokens = 450

    /// The timeout is how long the connection may sit idle. Deepgram sends nothing while it transcribes, which
    /// takes about a second for every minute of audio.
    static func timeout(forRecordingBytes bytes: Int) -> TimeInterval {
        let minutes = Double(bytes) / Double(WAVFile.bytesPerSecond * 60)
        return 20 + minutes * 3
    }
}

/// Whether Deepgram still has the pinned multilingual model, so a retired one costs a single failed request.
/// The newest model succeeding where the pinned one failed means the pinned one is gone, not that the audio
/// was bad.
private final class PinnedModel: @unchecked Sendable {
    private let lock = NSLock()
    private var available = true

    var isAvailable: Bool {
        get { lock.withLock { available } }
        set { lock.withLock { available = newValue } }
    }
}

extension DeepgramTranscriber {
    static func problem(statusCode: Int, body: Data) -> CloudTranscriptionError.Problem {
        let message = (try? JSONDecoder().decode(ErrorResponse.self, from: body))?.message
            ?? String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        switch statusCode {
        case 401, 403:
            return .rejectedKey(message)
        case 402:
            return .outOfCredits(message)
        case 400..<500 where statusCode != 408 && statusCode != 429:
            return .rejectedRequest(message)
        default:
            return .unavailable(statusCode: statusCode, message: message)
        }
    }
}

private struct ListenResponse: Decodable {
    struct Results: Decodable {
        let channels: [Channel]
    }

    struct Channel: Decodable {
        let alternatives: [Alternative]
    }

    struct Alternative: Decodable {
        let transcript: String
    }

    let results: Results
}

private struct ErrorResponse: Decodable {
    let message: String

    enum CodingKeys: String, CodingKey {
        case message = "err_msg"
    }
}
