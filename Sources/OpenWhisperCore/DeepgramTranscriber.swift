import Foundation

/// Transcribes a recording with Deepgram's Nova-3, its most accurate model, after recording stops.
///
/// Uploading the whole recording, rather than streaming it while recording, lets the model hear every
/// sentence to the end before writing it. A dictation of several minutes still comes back in seconds.
public struct DeepgramTranscriber: Sendable {
    private let apiKey: String
    private let language: String
    private let keyterms: [String]
    private let baseURL: URL
    private let session: URLSession
    private let retryDelay: Duration
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
        self.session = session
        self.retryDelay = retryDelay
    }

    public static let defaultBaseURL = URL(string: "https://api.deepgram.com")!

    /// Opens the connection to Deepgram while the person is still speaking, so the upload does not wait for it.
    public func warmUp() async {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        _ = try? await session.data(for: request)
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
        } catch DeepgramError.rejectedRequest(let message) {
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

        var attempt = 1
        while true {
            do {
                return try await send(request)
            } catch let error as DeepgramError where error.isWorthRetrying && attempt < Self.attempts {
                NSLog("OpenWhisper retrying Deepgram after: \(error.localizedDescription)")
                attempt += 1
                try await Task.sleep(for: retryDelay)
            }
        }
    }

    /// Checks the key without sending any audio.
    public func validateKey() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/auth/token"))
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        _ = try await response(for: request)
    }

    private func send(_ request: URLRequest) async throws -> String {
        let data = try await response(for: request)

        guard let response = try? JSONDecoder().decode(ListenResponse.self, from: data),
              let alternative = response.results.channels.first?.alternatives.first
        else {
            throw DeepgramError.invalidResponse
        }

        return alternative.transcript
    }

    private func response(for request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw DeepgramError.unreachable(code: error.code, message: error.localizedDescription)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw DeepgramError(statusCode: statusCode, body: data)
        }

        return data
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

    /// The vocabulary is a list of terms separated by commas, as the README describes, written for Whisper as
    /// a sentence ending in a period. Deepgram takes each term separately and rejects a request with more than
    /// 500 tokens of them, so the list stops at what fits.
    static func keyterms(fromVocabulary vocabulary: String) -> [String] {
        var vocabulary = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if vocabulary.hasSuffix(".") {
            vocabulary.removeLast()
        }

        var keyterms: [String] = []
        var estimatedTokens = 0

        for rawTerm in vocabulary.split(whereSeparator: { ",;\n".contains($0) }) {
            let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, !keyterms.contains(term) else { continue }

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
    private static let attempts = 2
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

public enum DeepgramError: Error, LocalizedError, Equatable, Sendable {
    /// The key is wrong, revoked, or not allowed to transcribe.
    case rejectedKey(String)
    case outOfCredits(String)
    case rejectedRequest(String)
    case unavailable(statusCode: Int, message: String)
    case unreachable(code: URLError.Code, message: String)
    case invalidResponse

    init(statusCode: Int, body: Data) {
        let message = (try? JSONDecoder().decode(ErrorResponse.self, from: body))?.message
            ?? String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        switch statusCode {
        case 401, 403:
            self = .rejectedKey(message)
        case 402:
            self = .outOfCredits(message)
        case 400..<500 where statusCode != 408 && statusCode != 429:
            self = .rejectedRequest(message)
        default:
            self = .unavailable(statusCode: statusCode, message: message)
        }
    }

    /// Only problems that waiting a moment can fix. Without a connection, the local model is quicker.
    var isWorthRetrying: Bool {
        switch self {
        case .unavailable:
            return true
        case .unreachable(let code, _):
            return code == .networkConnectionLost
        case .rejectedKey, .outOfCredits, .rejectedRequest, .invalidResponse:
            return false
        }
    }

    /// Whether the person needs to do something about their Deepgram account.
    public var needsAttention: Bool {
        switch self {
        case .rejectedKey, .outOfCredits:
            return true
        case .rejectedRequest, .unavailable, .unreachable, .invalidResponse:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .rejectedKey(let message):
            return "Deepgram rejected the API key\(Self.detail(message))."
        case .outOfCredits(let message):
            return "The Deepgram account is out of credits\(Self.detail(message))."
        case .rejectedRequest(let message):
            return "Deepgram rejected the request\(Self.detail(message))."
        case .unavailable(let statusCode, let message):
            return "Deepgram is unavailable (HTTP \(statusCode))\(Self.detail(message))."
        case .unreachable(_, let message):
            return "Deepgram could not be reached: \(message)"
        case .invalidResponse:
            return "Deepgram sent a response OpenWhisper could not read."
        }
    }

    private static func detail(_ message: String) -> String {
        let message = message.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return message.isEmpty ? "" : ": \(message)"
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
