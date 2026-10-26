import Foundation
import Testing
@testable import OpenWhisperCore

/// Serialized because the stub answers every OpenAI request in the test process.
@Suite(.serialized)
struct OpenAITranscriberTests {
    @Test func sendsTheRecordingBetweenHalfSecondsOfSilenceWithTheVocabulary() async throws {
        OpenAIStub.reset(replies: [.text("Push it to GitHub.")])
        let samples: [Int16] = [100, -200, 300]
        let recording = try writeRecording(samples)
        defer { try? FileManager.default.removeItem(at: recording) }

        let transcript = try await transcriber(apiKey: "secret", vocabulary: "GitHub, Claude Code.")
            .transcribe(wavURL: recording)

        #expect(transcript == "Push it to GitHub.")
        let (request, body) = try #require(OpenAIStub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")

        let form = try Form(request: request, body: body)
        #expect(form.names == ["model", "languages[]", "languages[]", "keywords[]", "keywords[]", "file"])
        #expect(form.strings("model") == ["gpt-transcribe"])
        #expect(form.strings("languages[]") == ["en", "es"])
        #expect(form.strings("keywords[]") == ["GitHub", "Claude Code"])
        let silence = [Int16](repeating: 0, count: 8_000)
        #expect(form.values("file") == [wav(silence + samples + silence)])
        #expect(String(decoding: body, as: UTF8.self).contains("filename=\"recording.wav\"\r\nContent-Type: audio/wav\r\n"))
    }

    @Test func namesOnlyTheChosenLanguage() async throws {
        OpenAIStub.reset(replies: [.text("Hola.")])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }

        _ = try await transcriber(language: "es").transcribe(wavURL: recording)

        let (request, body) = try #require(OpenAIStub.requests.first)
        let form = try Form(request: request, body: body)
        #expect(form.strings("languages[]") == ["es"])
        #expect(form.strings("keywords[]").isEmpty)
    }

    /// OpenAI rejects the whole request over one of them.
    @Test func leavesOutKeywordsWithAngleBrackets() {
        #expect(OpenAITranscriber.keywords(fromVocabulary: "C++, <b>, a > b; GitHub.") == ["C++", "GitHub"])
    }

    @Test(arguments: [
        (401, "invalid_api_key", CloudTranscriptionError.Problem.rejectedKey("Incorrect API key provided.")),
        (403, "missing_scope", CloudTranscriptionError.Problem.rejectedKey("Incorrect API key provided.")),
        (429, "insufficient_quota", CloudTranscriptionError.Problem.outOfCredits("Incorrect API key provided.")),
        (404, "model_not_found", CloudTranscriptionError.Problem.rejectedRequest("Incorrect API key provided.")),
        (400, "invalid_value", CloudTranscriptionError.Problem.rejectedRequest("Incorrect API key provided."))
    ])
    func explainsWhatOpenAIRejected(statusCode: Int, code: String, expected: CloudTranscriptionError.Problem) async throws {
        OpenAIStub.reset(replies: [.status(statusCode, Self.errorBody("Incorrect API key provided.", code: code))])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }

        await #expect(throws: CloudTranscriptionError(.openAI, expected)) {
            try await transcriber().transcribe(wavURL: recording)
        }
        #expect(OpenAIStub.requests.count == 1)
    }

    @Test func retriesOnceWhenOpenAIIsBusy() async throws {
        OpenAIStub.reset(replies: [
            .status(429, Self.errorBody("Rate limit reached.", code: "rate_limit_exceeded")),
            .text("second try")
        ])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }

        #expect(try await transcriber().transcribe(wavURL: recording) == "second try")
        #expect(OpenAIStub.requests.count == 2)
    }

    @Test func givesUpAfterTheSecondAttempt() async throws {
        OpenAIStub.reset(replies: [.status(500, "oops"), .status(503, Self.errorBody("Overloaded.", code: "")), .text("too late")])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }

        await #expect(throws: CloudTranscriptionError(.openAI, .unavailable(statusCode: 503, message: "Overloaded."))) {
            try await transcriber().transcribe(wavURL: recording)
        }
        #expect(OpenAIStub.requests.count == 2)
    }

    @Test func givesUpRightAwayWithoutAConnection() async throws {
        OpenAIStub.reset(replies: [.failure(.notConnectedToInternet), .text("unexpected")])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }

        let error = await #expect(throws: CloudTranscriptionError.self) {
            try await transcriber().transcribe(wavURL: recording)
        }
        #expect(error?.isOffline == true)
        #expect(OpenAIStub.requests.count == 1)
    }

    @Test func rejectsAResponseWithoutText() async throws {
        OpenAIStub.reset(replies: [.status(200, #"{"languages":[]}"#)])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }

        await #expect(throws: CloudTranscriptionError(.openAI, .invalidResponse)) {
            try await transcriber().transcribe(wavURL: recording)
        }
    }

    /// OpenAI takes files up to 25 MB, so Deepgram or this Mac transcribes longer ones.
    @Test func leavesRecordingsOverTwentyFiveMegabytesToTheOthers() async throws {
        OpenAIStub.reset(replies: [.text("unexpected")])
        let samples = Data(count: 14 * 60 * WAVFile.bytesPerSecond)
        let recording = FileManager.default.temporaryDirectory.appendingPathComponent("openwhisper-test-\(UUID().uuidString).wav")
        try (WAVFile.header(dataByteCount: UInt32(samples.count)) + samples).write(to: recording)
        defer { try? FileManager.default.removeItem(at: recording) }

        let error = await #expect(throws: CloudTranscriptionError.self) {
            try await transcriber().transcribe(wavURL: recording)
        }
        guard case .rejectedRequest = error?.problem else {
            Issue.record("Expected the recording to be refused, got \(String(describing: error))")
            return
        }
        #expect(OpenAIStub.requests.isEmpty)
    }

    @Test func checksTheKeyWithASecondOfSilence() async throws {
        OpenAIStub.reset(replies: [
            .text(""),
            .status(401, Self.errorBody("Incorrect API key provided.", code: "invalid_api_key")),
            .status(503, "busy")
        ])
        let transcriber = transcriber(apiKey: "secret")

        try await transcriber.validateKey()
        await #expect(throws: CloudTranscriptionError(.openAI, .rejectedKey("Incorrect API key provided."))) {
            try await transcriber.validateKey()
        }
        await #expect(throws: CloudTranscriptionError(.openAI, .unavailable(statusCode: 503, message: "busy"))) {
            try await transcriber.validateKey()
        }

        let (request, body) = try #require(OpenAIStub.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(try Form(request: request, body: body).values("file") == [WAVFile.silence(1)])
        #expect(OpenAIStub.requests.count == 3)
    }

    @Test func waitsLongerForLongerRecordings() {
        let tenMinutes = 10 * 60 * WAVFile.bytesPerSecond

        #expect(OpenAITranscriber.timeout(forRecordingBytes: 0) == 20)
        #expect(OpenAITranscriber.timeout(forRecordingBytes: tenMinutes) == 80)
    }

    @Test func describesWhyOpenAIFailed() {
        #expect(
            CloudTranscriptionError(.openAI, .outOfCredits("You exceeded your current quota.")).localizedDescription
                == "The OpenAI account is out of credits: You exceeded your current quota."
        )
        #expect(
            CloudTranscriptionError(.openAI, .unreachable(code: .timedOut, message: "The request timed out.")).localizedDescription
                == "OpenAI could not be reached: The request timed out."
        )
    }

    private func transcriber(apiKey: String = "key", language: String = "auto", vocabulary: String = "") -> OpenAITranscriber {
        OpenAITranscriber(
            apiKey: apiKey,
            language: language,
            vocabulary: vocabulary,
            session: OpenAIStub.session(),
            retryDelay: .zero
        )
    }

    private static func errorBody(_ message: String, code: String) -> String {
        #"{"error":{"message":"\#(message)","type":"invalid_request_error","param":null,"code":"\#(code)"}}"#
    }
}

/// The fields of a multipart form, in order.
private struct Form {
    private let fields: [(name: String, value: Data)]

    init(request: URLRequest, body: Data) throws {
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        let boundary = try #require(contentType.components(separatedBy: "boundary=").last)
        let delimiter = Data("--\(boundary)".utf8)
        #expect(body.suffix(delimiter.count + 4) == delimiter + Data("--\r\n".utf8))

        var fields: [(String, Data)] = []
        var rest = body
        while let start = rest.range(of: delimiter), let end = rest[start.upperBound...].range(of: delimiter) {
            // Each part sits between line breaks after and before the delimiters.
            let part = rest[(start.upperBound + 2)..<(end.lowerBound - 2)]
            let headersEnd = try #require(part.range(of: Data("\r\n\r\n".utf8)))
            let headers = String(decoding: part[..<headersEnd.lowerBound], as: UTF8.self)
            let name = try #require(headers.firstMatch(of: /name="([^"]*)"/)?.1)
            fields.append((String(name), Data(part[headersEnd.upperBound...])))
            rest = rest[end.lowerBound...]
        }
        self.fields = fields
    }

    var names: [String] {
        fields.map(\.name)
    }

    func values(_ name: String) -> [Data] {
        fields.filter { $0.name == name }.map(\.value)
    }

    func strings(_ name: String) -> [String] {
        values(name).map { String(decoding: $0, as: UTF8.self) }
    }
}
