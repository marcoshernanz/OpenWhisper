import Foundation
import Testing
@testable import OpenWhisperCore

@Test func transcribesWhisperKitAudioFixtureWhenEnabled() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["OPENWHISPER_RUN_WHISPERKIT_INTEGRATION"] == "1" else {
        return
    }

    guard let audioPath = environment["OPENWHISPER_TEST_AUDIO"], !audioPath.isEmpty else {
        Issue.record("Set OPENWHISPER_TEST_AUDIO to a local WAV fixture.")
        return
    }

    let configuration = WhisperConfiguration(
        executableURL: URL(fileURLWithPath: "/tmp/whisper-cli"),
        modelURL: URL(fileURLWithPath: "/tmp/whisper-model.bin"),
        language: "en",
        transcriptionEngine: .whisperKit,
        qualityProfile: .balanced,
        cleanupMode: .off,
        whisperKitModelDirectory: URL(
            fileURLWithPath: environment["OPENWHISPER_WHISPERKIT_MODEL_DIR"]
                ?? WhisperConfiguration.defaultWhisperKitModelDirectory.path
        )
    )
    let transcriber = WhisperKitTranscriber(configuration: configuration)
    let transcript = try await transcriber.transcribe(wavURL: URL(fileURLWithPath: audioPath))
        .lowercased()

    #expect(transcript.contains("openwhisper"))
    #expect(transcript.contains("local transcription"))
}
