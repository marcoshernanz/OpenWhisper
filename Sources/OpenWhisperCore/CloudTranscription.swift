import Foundation

/// The services that transcribe with an API key, the more accurate first.
public enum CloudService: String, CaseIterable, Sendable {
    case openAI
    case deepgram

    public var engine: TranscriptionEngine {
        switch self {
        case .openAI:
            return .openAI
        case .deepgram:
            return .deepgram
        }
    }

    public var displayName: String {
        engine.displayName
    }

    public var keyStore: APIKeyStore {
        switch self {
        case .openAI:
            return APIKeyStore(service: "dev.openwhisper.openai", label: "OpenWhisper OpenAI API key")
        case .deepgram:
            return APIKeyStore(service: "dev.openwhisper.deepgram", label: "OpenWhisper Deepgram API key")
        }
    }

    /// Overrides the key in the keychain.
    var apiKeyEnvironmentVariable: String {
        switch self {
        case .openAI:
            return "OPENWHISPER_OPENAI_API_KEY"
        case .deepgram:
            return "OPENWHISPER_DEEPGRAM_API_KEY"
        }
    }

    public func transcriber(apiKey: String, language: String, vocabulary: String) -> any CloudTranscriber {
        switch self {
        case .openAI:
            return OpenAITranscriber(apiKey: apiKey, language: language, vocabulary: vocabulary)
        case .deepgram:
            return DeepgramTranscriber(apiKey: apiKey, language: language, vocabulary: vocabulary)
        }
    }
}

/// Uploads the whole recording once recording stops, rather than streaming it while recording, so the model
/// hears every sentence to the end before writing it.
public protocol CloudTranscriber: Sendable {
    var service: CloudService { get }

    /// Opens the connection while the person is still speaking, so the upload does not wait for it.
    func warmUp() async

    func transcribe(wavURL: URL) async throws -> String

    /// Fails with a CloudTranscriptionError that needs attention when the key cannot transcribe.
    func validateKey() async throws
}

public struct CloudTranscriptionError: Error, LocalizedError, Equatable, Sendable {
    public enum Problem: Equatable, Sendable {
        /// The key is wrong, revoked, or not allowed to transcribe.
        case rejectedKey(String)
        case outOfCredits(String)
        case rejectedRequest(String)
        case unavailable(statusCode: Int, message: String)
        case unreachable(code: URLError.Code, message: String)
        case invalidResponse
    }

    public let service: CloudService
    public let problem: Problem

    public init(_ service: CloudService, _ problem: Problem) {
        self.service = service
        self.problem = problem
    }

    /// Only problems that waiting a moment can fix. Without a connection, the local model is quicker.
    var isWorthRetrying: Bool {
        switch problem {
        case .unavailable:
            return true
        case .unreachable(let code, _):
            return code == .networkConnectionLost
        case .rejectedKey, .outOfCredits, .rejectedRequest, .invalidResponse:
            return false
        }
    }

    /// Without a connection, no other service can be reached either.
    var isOffline: Bool {
        guard case .unreachable(.notConnectedToInternet, _) = problem else { return false }
        return true
    }

    /// Whether the person needs to do something about their account with the service.
    public var needsAttention: Bool {
        switch problem {
        case .rejectedKey, .outOfCredits:
            return true
        case .rejectedRequest, .unavailable, .unreachable, .invalidResponse:
            return false
        }
    }

    public var errorDescription: String? {
        let name = service.displayName
        switch problem {
        case .rejectedKey(let message):
            return "\(name) rejected the API key\(Self.detail(message))."
        case .outOfCredits(let message):
            return "The \(name) account is out of credits\(Self.detail(message))."
        case .rejectedRequest(let message):
            return "\(name) rejected the request\(Self.detail(message))."
        case .unavailable(let statusCode, let message):
            return "\(name) is unavailable (HTTP \(statusCode))\(Self.detail(message))."
        case .unreachable(_, let message):
            return "\(name) could not be reached: \(message)"
        case .invalidResponse:
            return "\(name) sent a response OpenWhisper could not read."
        }
    }

    private static func detail(_ message: String) -> String {
        let message = message.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return message.isEmpty ? "" : ": \(message)"
    }
}

/// Sends a service's requests and turns what goes wrong into a CloudTranscriptionError.
struct CloudConnection: Sendable {
    let service: CloudService
    let session: URLSession
    let retryDelay: Duration
    /// What a response other than a success means, from its status code and body.
    let problem: @Sendable (_ statusCode: Int, _ body: Data) -> CloudTranscriptionError.Problem

    func warmUp(_ url: URL) async {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        _ = try? await session.data(for: request)
    }

    /// Tries once more when waiting a moment can fix the problem.
    func dataRetrying(for request: URLRequest) async throws -> Data {
        var attempt = 1
        while true {
            do {
                return try await data(for: request)
            } catch let error as CloudTranscriptionError where error.isWorthRetrying && attempt < Self.attempts {
                NSLog("OpenWhisper retrying \(service.displayName) after: \(error.localizedDescription)")
                attempt += 1
                try await Task.sleep(for: retryDelay)
            }
        }
    }

    func data(for request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw CloudTranscriptionError(service, .unreachable(code: error.code, message: error.localizedDescription))
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw CloudTranscriptionError(service, problem(statusCode, data))
        }

        return data
    }

    private static let attempts = 2
}

/// The custom vocabulary is a list of terms separated by commas, as the README describes, written for Whisper
/// as a sentence ending in a period.
enum Vocabulary {
    static func terms(in vocabulary: String) -> [String] {
        var vocabulary = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if vocabulary.hasSuffix(".") {
            vocabulary.removeLast()
        }

        var terms: [String] = []
        for rawTerm in vocabulary.split(whereSeparator: { ",;\n".contains($0) }) {
            let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, !terms.contains(term) else { continue }
            terms.append(term)
        }

        return terms
    }
}
