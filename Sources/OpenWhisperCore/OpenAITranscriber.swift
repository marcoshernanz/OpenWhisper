import Foundation

/// Transcribes a recording with OpenAI's GPT Transcribe. On Artificial Analysis's English benchmark it gets
/// 3.3% of words wrong, where Deepgram's Nova-3 gets 5.2%.
public struct OpenAITranscriber: CloudTranscriber {
    public let service = CloudService.openAI
    private let apiKey: String
    private let languages: [String]
    private let keywords: [String]
    private let baseURL: URL
    private let connection: CloudConnection

    public init(
        apiKey: String,
        language: String,
        vocabulary: String,
        baseURL: URL = OpenAITranscriber.defaultBaseURL,
        session: URLSession = .shared,
        retryDelay: Duration = .seconds(1)
    ) {
        self.apiKey = apiKey
        // Naming both keeps a dictation in one of them, without detecting the language of a short one wrong.
        self.languages = language == TranscriptionLanguage.auto.rawValue
            ? [TranscriptionLanguage.english.rawValue, TranscriptionLanguage.spanish.rawValue]
            : [language]
        self.keywords = Self.keywords(fromVocabulary: vocabulary)
        self.baseURL = baseURL
        self.connection = CloudConnection(
            service: .openAI,
            session: session,
            retryDelay: retryDelay,
            problem: Self.problem(statusCode:body:)
        )
    }

    public static let defaultBaseURL = URL(string: "https://api.openai.com/v1/")!

    public func warmUp() async {
        await connection.warmUp(baseURL)
    }

    public func transcribe(wavURL: URL) async throws -> String {
        let recording = try Data(contentsOf: wavURL)
        let audio = WAVFile.paddingWithSilence(Self.padding, around: recording) ?? recording

        guard audio.count <= Self.maxUploadBytes else {
            throw CloudTranscriptionError(.openAI, .rejectedRequest("recordings over 25 MB, about 13 minutes, are too long"))
        }

        return try await transcribe(audio, retrying: true)
    }

    /// Transcribes a second of silence, which costs less than a hundredth of a cent, because a key can be limited to
    /// some of the API, and listing the models would not show whether it can transcribe.
    public func validateKey() async throws {
        _ = try await transcribe(WAVFile.silence(1), retrying: false)
    }

    private func transcribe(_ audio: Data, retrying: Bool) async throws -> String {
        let request = transcriptionRequest(for: audio)
        let data = retrying ? try await connection.dataRetrying(for: request) : try await connection.data(for: request)

        guard let response = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            throw CloudTranscriptionError(.openAI, .invalidResponse)
        }

        return response.text
    }

    func transcriptionRequest(for audio: Data) -> URLRequest {
        let boundary = "OpenWhisper-\(UUID().uuidString)"
        var form = MultipartForm(boundary: boundary)
        form.append("model", Self.model)
        for language in languages {
            form.append("languages[]", language)
        }
        for keyword in keywords {
            form.append("keywords[]", keyword)
        }
        form.appendFile("file", fileName: "recording.wav", contentType: "audio/wav", data: audio)

        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.timeout(forRecordingBytes: audio.count)
        request.httpBody = form.body
        return request
    }

    /// OpenAI rejects the whole request when a keyword has a line break or an angle bracket in it.
    static func keywords(fromVocabulary vocabulary: String) -> [String] {
        Vocabulary.terms(in: vocabulary).filter { !$0.contains("<") && !$0.contains(">") }
    }

    static let model = "gpt-transcribe"
    /// As with Deepgram, a word right at the start or the end of the audio is the easiest to lose.
    private static let padding: TimeInterval = 0.5
    /// OpenAI takes files up to 25 MB.
    private static let maxUploadBytes = 25_000_000

    /// The timeout is how long the connection may sit idle. OpenAI sends nothing while it transcribes, which
    /// takes about two and a half seconds for every minute of audio.
    static func timeout(forRecordingBytes bytes: Int) -> TimeInterval {
        let minutes = Double(bytes) / Double(WAVFile.bytesPerSecond * 60)
        return 20 + minutes * 6
    }
}

extension OpenAITranscriber {
    static func problem(statusCode: Int, body: Data) -> CloudTranscriptionError.Problem {
        let error = (try? JSONDecoder().decode(ErrorResponse.self, from: body))?.error
        let message = error?.message
            ?? String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        switch statusCode {
        case 401, 403:
            return .rejectedKey(message)
        // OpenAI uses 429 both for running out of credits and for too many requests at once.
        case 429 where error?.code == "insufficient_quota":
            return .outOfCredits(message)
        case 400..<500 where statusCode != 408 && statusCode != 429:
            return .rejectedRequest(message)
        default:
            return .unavailable(statusCode: statusCode, message: message)
        }
    }
}

private struct MultipartForm {
    private let boundary: String
    private var parts = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    var body: Data {
        parts + Data("--\(boundary)--\r\n".utf8)
    }

    mutating func append(_ name: String, _ value: String) {
        parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func appendFile(_ name: String, fileName: String, contentType: String, data: Data) {
        parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".utf8))
        parts.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        parts.append(data)
        parts.append(Data("\r\n".utf8))
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

private struct ErrorResponse: Decodable {
    struct Details: Decodable {
        let message: String?
        let code: String?
    }

    let error: Details
}
