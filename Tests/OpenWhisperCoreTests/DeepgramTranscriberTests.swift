import Foundation
import Testing
@testable import OpenWhisperCore

/// Serialized because the stub answers every Deepgram request in the test process.
@Suite(.serialized)
struct DeepgramTranscriberTests {
    @Test func readsTheVocabularyAsKeyterms() {
        #expect(
            DeepgramTranscriber.keyterms(fromVocabulary: " DeepSeek, Claude Code,Next.js, GitHub. ")
                == ["DeepSeek", "Claude Code", "Next.js", "GitHub"]
        )
        #expect(DeepgramTranscriber.keyterms(fromVocabulary: "Muon,, Muon; RoPE\nYaRN") == ["Muon", "RoPE", "YaRN"])
        #expect(DeepgramTranscriber.keyterms(fromVocabulary: "e.g., Inc.") == ["e.g.", "Inc"])
        #expect(DeepgramTranscriber.keyterms(fromVocabulary: "").isEmpty)
    }

    /// Deepgram rejects the whole request when the keyterms run over its limit.
    @Test func stopsTheVocabularyAtDeepgramsLimit() {
        let vocabulary = (0..<200).map { "Term\($0)" }.joined(separator: ", ")
        let keyterms = DeepgramTranscriber.keyterms(fromVocabulary: vocabulary)

        #expect(keyterms.first == "Term0")
        #expect(keyterms.map(\.utf8.count).reduce(0, +) <= 450)
        #expect(keyterms.map(\.utf8.count).reduce(0, +) > 440)
    }

    @Test func asksForNovaThreeFollowingEnglishAndSpanish() throws {
        let transcriber = transcriber(language: "auto", vocabulary: "GitHub, Claude Code")
        let pinned = try queryItems(of: transcriber.listenURL(pinningMultilingualModel: true))

        #expect(pinned.value("model") == ["nova-3"])
        #expect(pinned.value("language") == ["multi"])
        #expect(pinned.value("version") == ["2026-01-27.9107"])
        #expect(pinned.value("language_hint").isEmpty)
        #expect(pinned.value("smart_format") == ["true"])
        #expect(pinned.value("mip_opt_out") == ["true"])
        #expect(pinned.value("keyterm") == ["GitHub", "Claude Code"])

        let newest = try queryItems(of: transcriber.listenURL(pinningMultilingualModel: false))

        #expect(newest.value("language") == ["multi"])
        #expect(newest.value("version").isEmpty)
        #expect(newest.value("language_hint") == ["en", "es"])

        let spanish = try queryItems(of: self.transcriber(language: "es").listenURL(pinningMultilingualModel: true))

        #expect(spanish.value("language") == ["es"])
        #expect(spanish.value("version").isEmpty)
        #expect(spanish.value("language_hint").isEmpty)
        #expect(spanish.value("keyterm").isEmpty)
    }

    @Test func switchesToTheNewestModelOnceDeepgramRetiresTheOldOne() async throws {
        DeepgramStub.reset(replies: [
            .status(400, #"{"err_msg":"Bad Request: No such model/language/version/tier combination found."}"#),
            .transcript("Vale, súbelo a GitHub.")
        ])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }

        #expect(try await transcriber().transcribe(wavURL: recording) == "Vale, súbelo a GitHub.")

        let urls = DeepgramStub.requests.compactMap(\.0.url)
        #expect(urls.count == 2)
        #expect(try queryItems(of: urls[0]).value("version") == ["2026-01-27.9107"])
        #expect(try queryItems(of: urls[1]).value("version").isEmpty)
    }

    @Test func asksForTheRetiredModelOnlyOnce() async throws {
        DeepgramStub.reset(replies: [
            .status(400, #"{"err_msg":"Bad Request: No such model/language/version/tier combination found."}"#),
            .transcript("first"),
            .transcript("second")
        ])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }
        let transcriber = transcriber()

        #expect(try await transcriber.transcribe(wavURL: recording) == "first")
        #expect(try await transcriber.transcribe(wavURL: recording) == "second")

        let urls = DeepgramStub.requests.compactMap(\.0.url)
        #expect(urls.count == 3)
        #expect(try queryItems(of: urls[2]).value("version").isEmpty)
    }

    /// A bad recording fails with the newest model too, which says nothing about the pinned one.
    @Test func keepsThePinnedModelAfterARequestBothReject() async throws {
        DeepgramStub.reset(replies: [
            .status(400, #"{"err_msg":"Bad Request: failed to process audio: corrupt or unsupported data"}"#),
            .status(400, #"{"err_msg":"Bad Request: failed to process audio: corrupt or unsupported data"}"#),
            .transcript("fine")
        ])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }
        let transcriber = transcriber()

        await #expect(throws: CloudTranscriptionError.self) {
            try await transcriber.transcribe(wavURL: recording)
        }
        #expect(try await transcriber.transcribe(wavURL: recording) == "fine")
        #expect(try queryItems(of: try #require(DeepgramStub.requests.last?.0.url)).value("version") == ["2026-01-27.9107"])
    }

    /// Deepgram reads "+" in a query as a space.
    @Test func keepsPlusSignsInKeyterms() throws {
        let url = transcriber(vocabulary: "C++, Claude Code").listenURL(pinningMultilingualModel: true)

        #expect(url.absoluteString.contains("keyterm=C%2B%2B"))
        #expect(url.absoluteString.contains("keyterm=Claude%20Code"))
        #expect(try queryItems(of: url).value("keyterm") == ["C++", "Claude Code"])
    }

    @Test func sendsTheRecordingBetweenHalfSecondsOfSilence() async throws {
        DeepgramStub.reset(replies: [.transcript("Hola, ¿qué tal?")])
        let samples: [Int16] = [100, -200, 300]
        let recording = try writeRecording(samples)
        defer { try? FileManager.default.removeItem(at: recording) }

        let transcript = try await transcriber(apiKey: "secret").transcribe(wavURL: recording)

        #expect(transcript == "Hola, ¿qué tal?")
        let (request, body) = try #require(DeepgramStub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/listen")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token secret")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "audio/wav")
        let silence = [Int16](repeating: 0, count: 8_000)
        #expect(body == wav(silence + samples + silence))
    }

    @Test func sendsAnEmptyTranscriptForSilence() async throws {
        DeepgramStub.reset(replies: [.transcript("")])
        let recording = try writeRecording([0, 0])
        defer { try? FileManager.default.removeItem(at: recording) }

        #expect(try await transcriber().transcribe(wavURL: recording) == "")
    }

    @Test(arguments: [
        (401, CloudTranscriptionError.Problem.rejectedKey("Invalid credentials.")),
        (403, CloudTranscriptionError.Problem.rejectedKey("Invalid credentials.")),
        (402, CloudTranscriptionError.Problem.outOfCredits("Invalid credentials.")),
        (400, CloudTranscriptionError.Problem.rejectedRequest("Invalid credentials."))
    ])
    func explainsWhatDeepgramRejected(statusCode: Int, expected: CloudTranscriptionError.Problem) async throws {
        DeepgramStub.reset(replies: [
            .status(statusCode, #"{"err_code":"INVALID_AUTH","err_msg":"Invalid credentials.","request_id":"1"}"#)
        ])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }

        await #expect(throws: CloudTranscriptionError(.deepgram, expected)) {
            try await transcriber(language: "en").transcribe(wavURL: recording)
        }
        #expect(DeepgramStub.requests.count == 1)
    }

    @Test func retriesOnceWhenDeepgramIsUnavailable() async throws {
        DeepgramStub.reset(replies: [.status(503, "busy"), .transcript("second try")])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }

        #expect(try await transcriber().transcribe(wavURL: recording) == "second try")
        #expect(DeepgramStub.requests.count == 2)
    }

    @Test func givesUpAfterTheSecondAttempt() async throws {
        DeepgramStub.reset(replies: [.status(503, "busy"), .status(429, "slow down"), .transcript("too late")])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }

        await #expect(throws: CloudTranscriptionError(.deepgram, .unavailable(statusCode: 429, message: "slow down"))) {
            try await transcriber().transcribe(wavURL: recording)
        }
        #expect(DeepgramStub.requests.count == 2)
    }

    /// Without a connection, transcribing on the Mac right away is quicker than waiting to try again.
    @Test func goesStraightToThisMacWithoutAConnection() async throws {
        DeepgramStub.reset(replies: [.failure(.notConnectedToInternet), .transcript("unexpected")])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }

        let error = await #expect(throws: CloudTranscriptionError.self) {
            try await transcriber().transcribe(wavURL: recording)
        }
        guard case .unreachable(.notConnectedToInternet, _) = error?.problem else {
            Issue.record("Expected no connection, got \(String(describing: error))")
            return
        }
        #expect(DeepgramStub.requests.count == 1)
    }

    @Test func retriesAConnectionLostOnTheWay() async throws {
        DeepgramStub.reset(replies: [.failure(.networkConnectionLost), .transcript("reconnected")])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }

        #expect(try await transcriber().transcribe(wavURL: recording) == "reconnected")
    }

    @Test func rejectsAResponseWithoutATranscript() async throws {
        DeepgramStub.reset(replies: [.status(200, #"{"results":{"channels":[]}}"#)])
        let recording = try writeRecording([1])
        defer { try? FileManager.default.removeItem(at: recording) }

        await #expect(throws: CloudTranscriptionError(.deepgram, .invalidResponse)) {
            try await transcriber().transcribe(wavURL: recording)
        }
    }

    @Test func checksTheKeyWithoutSendingAudio() async throws {
        DeepgramStub.reset(replies: [.status(200, "{}"), .status(401, "Invalid credentials.")])
        let transcriber = transcriber(apiKey: "secret")

        try await transcriber.validateKey()
        await #expect(throws: CloudTranscriptionError(.deepgram, .rejectedKey("Invalid credentials."))) {
            try await transcriber.validateKey()
        }

        let (request, body) = try #require(DeepgramStub.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/auth/token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token secret")
        #expect(body.isEmpty)
    }

    @Test func waitsLongerForLongerRecordings() {
        let tenMinutes = 10 * 60 * WAVFile.bytesPerSecond

        #expect(DeepgramTranscriber.timeout(forRecordingBytes: 0) == 20)
        #expect(DeepgramTranscriber.timeout(forRecordingBytes: tenMinutes) == 50)
    }

    @Test func describesWhyDeepgramFailed() {
        #expect(CloudTranscriptionError(.deepgram, .rejectedKey("Invalid credentials.")).localizedDescription == "Deepgram rejected the API key: Invalid credentials.")
        #expect(CloudTranscriptionError(.deepgram, .rejectedKey("")).localizedDescription == "Deepgram rejected the API key.")
        #expect(
            CloudTranscriptionError(.deepgram, .unavailable(statusCode: 503, message: "busy")).localizedDescription
                == "Deepgram is unavailable (HTTP 503): busy."
        )
    }

    @Test func onlyAskToFixTheKeyOrTheAccount() {
        #expect(CloudTranscriptionError(.deepgram, .rejectedKey("")).needsAttention)
        #expect(CloudTranscriptionError(.deepgram, .outOfCredits("")).needsAttention)
        #expect(!CloudTranscriptionError(.deepgram, .unreachable(code: .timedOut, message: "")).needsAttention)
        #expect(!CloudTranscriptionError(.deepgram, .unavailable(statusCode: 500, message: "")).needsAttention)
        #expect(!CloudTranscriptionError(.deepgram, .rejectedRequest("")).needsAttention)
    }

    private func transcriber(apiKey: String = "key", language: String = "auto", vocabulary: String = "") -> DeepgramTranscriber {
        DeepgramTranscriber(
            apiKey: apiKey,
            language: language,
            vocabulary: vocabulary,
            session: DeepgramStub.session(),
            retryDelay: .zero
        )
    }

    private func queryItems(of url: URL) throws -> [URLQueryItem] {
        try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    }
}

private extension [URLQueryItem] {
    func value(_ name: String) -> [String] {
        filter { $0.name == name }.compactMap(\.value)
    }
}
