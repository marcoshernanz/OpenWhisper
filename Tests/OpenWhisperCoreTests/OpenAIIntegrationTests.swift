import Foundation
import Testing
@testable import OpenWhisperCore

/// These send synthesized speech to OpenAI with the key from OPENWHISPER_OPENAI_API_KEY or the keychain, so
/// they run only with OPENWHISPER_RUN_OPENAI_INTEGRATION=1.
@Suite struct OpenAIIntegrationTests {
    /// They start and stop right on their words, as when recording starts late or stops as the last word ends.
    @Test(arguments: DeepgramIntegrationTests.shortDictations)
    func keepsShortDictationsInTheirLanguage(fixture: SpokenFixture) async throws {
        guard let apiKey = Self.apiKey() else { return }

        let recording = try await DeepgramIntegrationTests.concatenate([fixture], pause: 0, trimmingEnds: true)
        defer { try? FileManager.default.removeItem(at: recording) }

        let outcome = try await Self.transcriber(apiKeys: [.openAI: apiKey]).transcribe(wavURL: recording)

        // OpenAI once wrote "súbelo" as "subelo", which is still Spanish.
        let withoutAccents = { (text: String) in text.folding(options: .diacriticInsensitive, locale: nil) }
        #expect(outcome.service == .openAI)
        DeepgramIntegrationTests.expect(withoutAccents(outcome.text), contains: fixture.expectedPhrases.map(withoutAccents))
    }

    @Test func transcribesALongDictation() async throws {
        guard let apiKey = Self.apiKey() else { return }

        let english = DeepgramIntegrationTests.dictations[3]
        let recording = try await DeepgramIntegrationTests.concatenate(
            DeepgramIntegrationTests.dictations + [english],
            pause: 1.5
        )
        defer { try? FileManager.default.removeItem(at: recording) }

        let start = Date()
        let outcome = try await Self.transcriber(apiKeys: [.openAI: apiKey]).transcribe(wavURL: recording)
        let seconds = Date().timeIntervalSince(start)

        #expect(outcome.service == .openAI)
        #expect(seconds < 30, "Took \(seconds) s")
        DeepgramIntegrationTests.expect(outcome.text, contains: english.expectedPhrases + ["cargador de datos", "sobel"])
        #expect(outcome.text.lowercased().components(separatedBy: "orange giraffe").count == 3)
    }

    @Test func fallsBackToDeepgramWhenOpenAIRejectsTheKey() async throws {
        guard Self.apiKey() != nil, let deepgramKey = CloudService.deepgram.keyStore.read() else { return }

        let recording = try await DeepgramIntegrationTests.dictations[3].synthesize()
        defer { try? FileManager.default.removeItem(at: recording) }

        let outcome = try await Self.transcriber(apiKeys: [.openAI: "sk-not-a-key", .deepgram: deepgramKey])
            .transcribe(wavURL: recording)

        #expect(outcome.service == .deepgram)
        #expect(outcome.cloudFailures.map(\.service) == [.openAI])
        #expect(outcome.cloudFailures.first?.needsAttention == true)
        DeepgramIntegrationTests.expect(outcome.text, contains: ["data loader", "orange giraffe"])
    }

    @Test func checksTheKey() async throws {
        guard let apiKey = Self.apiKey() else { return }

        try await OpenAITranscriber(apiKey: apiKey, language: "auto", vocabulary: "").validateKey()
        let error = await #expect(throws: CloudTranscriptionError.self) {
            try await OpenAITranscriber(apiKey: "sk-not-a-key", language: "auto", vocabulary: "").validateKey()
        }
        #expect(error?.needsAttention == true)
    }

    private static func apiKey() -> String? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENWHISPER_RUN_OPENAI_INTEGRATION"] == "1" else { return nil }

        return environment["OPENWHISPER_OPENAI_API_KEY"] ?? CloudService.openAI.keyStore.read()
    }

    private static func transcriber(apiKeys: [CloudService: String]) -> WhisperTranscriber {
        WhisperTranscriber(configuration: WhisperConfiguration(
            executableURL: URL(fileURLWithPath: "/tmp/whisper-cli"),
            modelURL: URL(fileURLWithPath: "/tmp/whisper-model.bin"),
            transcriptionEngine: .openAI,
            initialPrompt: DeepgramIntegrationTests.vocabulary,
            apiKeys: apiKeys
        ))
    }
}
