import Foundation
import Testing
@testable import OpenWhisperCore

struct CloudFallbackTests {
    @Test func usesTheNextServiceWhenOneFails() async throws {
        let openAI = FakeCloudTranscriber(.openAI, .failure(CloudTranscriptionError(.openAI, .rejectedKey("Incorrect API key provided."))))
        let deepgram = FakeCloudTranscriber(.deepgram, .success("hello from deepgram"))

        let attempt = try await transcriber(openAI, deepgram).transcribeWithCloudServices(wavURL: Self.recording)

        #expect(attempt == .transcribed(TranscriptionOutcome(
            text: "hello from deepgram",
            service: .deepgram,
            cloudFailures: [CloudTranscriptionError(.openAI, .rejectedKey("Incorrect API key provided."))]
        )))
        #expect(openAI.calls == 1)
        #expect(deepgram.calls == 1)
    }

    @Test func stopsAtTheFirstServiceThatTranscribes() async throws {
        let openAI = FakeCloudTranscriber(.openAI, .success("hello from openai"))
        let deepgram = FakeCloudTranscriber(.deepgram, .success("hello from deepgram"))

        let attempt = try await transcriber(openAI, deepgram).transcribeWithCloudServices(wavURL: Self.recording)

        #expect(attempt == .transcribed(TranscriptionOutcome(text: "hello from openai", service: .openAI)))
        #expect(deepgram.calls == 0)
    }

    /// Without a connection, this Mac transcribes right away.
    @Test func skipsTheOtherServicesWithoutAConnection() async throws {
        let offline = CloudTranscriptionError(.openAI, .unreachable(code: .notConnectedToInternet, message: "The Internet connection appears to be offline."))
        let openAI = FakeCloudTranscriber(.openAI, .failure(offline))
        let deepgram = FakeCloudTranscriber(.deepgram, .success("unexpected"))

        let attempt = try await transcriber(openAI, deepgram).transcribeWithCloudServices(wavURL: Self.recording)

        #expect(attempt == .failed([offline]))
        #expect(deepgram.calls == 0)
    }

    @Test func reportsEveryServiceThatFailed() async throws {
        let openAI = FakeCloudTranscriber(.openAI, .failure(CloudTranscriptionError(.openAI, .unavailable(statusCode: 503, message: ""))))
        let deepgram = FakeCloudTranscriber(.deepgram, .failure(CloudTranscriptionError(.deepgram, .outOfCredits(""))))

        let attempt = try await transcriber(openAI, deepgram).transcribeWithCloudServices(wavURL: Self.recording)

        #expect(attempt == .failed([
            CloudTranscriptionError(.openAI, .unavailable(statusCode: 503, message: "")),
            CloudTranscriptionError(.deepgram, .outOfCredits(""))
        ]))
    }

    @Test func describesWhatFailedWhenNothingTranscribes() {
        let error = TranscriptionError.cloudAndThisMacFailed(
            cloud: ["OpenAI rejected the API key.", "Deepgram is unavailable (HTTP 503)."],
            thisMac: "Missing Whisper model."
        )

        #expect(error.localizedDescription == """
        OpenAI rejected the API key.
        Deepgram is unavailable (HTTP 503).

        Transcribing on this Mac failed too: Missing Whisper model.
        """)
    }

    private static let recording = URL(fileURLWithPath: "/tmp/openwhisper-test.wav")

    private func transcriber(_ cloudTranscribers: any CloudTranscriber...) -> WhisperTranscriber {
        WhisperTranscriber(
            configuration: WhisperConfiguration(
                executableURL: URL(fileURLWithPath: "/tmp/whisper-cli"),
                modelURL: URL(fileURLWithPath: "/tmp/model.bin"),
                transcriptionEngine: .openAI,
                cleanupMode: .off
            ),
            cloudTranscribers: cloudTranscribers
        )
    }
}

private final class FakeCloudTranscriber: CloudTranscriber, @unchecked Sendable {
    let service: CloudService
    private let result: Result<String, CloudTranscriptionError>
    private let lock = NSLock()
    private var callCount = 0

    init(_ service: CloudService, _ result: Result<String, CloudTranscriptionError>) {
        self.service = service
        self.result = result
    }

    var calls: Int {
        lock.withLock { callCount }
    }

    func warmUp() async {}

    func transcribe(wavURL: URL) async throws -> String {
        lock.withLock { callCount += 1 }
        return try result.get()
    }

    func validateKey() async throws {}
}
