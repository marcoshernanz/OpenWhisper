import Foundation
import Testing
@testable import OpenWhisperCore

@Test func buildsWhisperCLIArgumentsForLocalTranscription() {
    let configuration = WhisperConfiguration(
        executableURL: URL(fileURLWithPath: "/tmp/whisper-cli"),
        modelURL: URL(fileURLWithPath: "/tmp/model.bin"),
        language: "auto",
        qualityProfile: .balanced,
        cleanupMode: .off,
        initialPrompt: "OpenWhisper, Wispr Flow"
    )
    let command = WhisperCommand(
        configuration: configuration,
        audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
        outputBaseURL: URL(fileURLWithPath: "/tmp/transcript")
    )

    #expect(command.arguments == [
        "-m", "/tmp/model.bin",
        "-f", "/tmp/audio.wav",
        "-otxt",
        "-of", "/tmp/transcript",
        "-nt",
        "-l", "auto",
        "-bo", "2",
        "-bs", "2",
        "-ac", "0",
        "-tp", "0",
        "-tpi", "0.2",
        "-np",
        "-sns",
        "--prompt", "OpenWhisper, Wispr Flow"
    ])
    #expect(command.transcriptURL.path == "/tmp/transcript.txt")
}

@Test func derivesDefaultServerExecutableAndURLs() {
    let configuration = WhisperConfiguration(
        executableURL: URL(fileURLWithPath: "/tmp/whisper.cpp/build/bin/whisper-cli"),
        modelURL: URL(fileURLWithPath: "/tmp/model.bin"),
        serverHost: "127.0.0.1",
        serverPort: 58442
    )

    #expect(configuration.serverExecutableURL.path == "/tmp/whisper.cpp/build/bin/whisper-server")
    #expect(configuration.serverHealthURL.absoluteString == "http://127.0.0.1:58442/health")
    #expect(configuration.serverInferenceURL.absoluteString == "http://127.0.0.1:58442/inference")
    #expect(configuration.audioContext == 0)
    #expect(configuration.beamSize == 2)
    #expect(configuration.bestOf == 2)
    #expect(configuration.transcriptionEngine == .whisperKit)
    #expect(configuration.whisperKitModel == "openai_whisper-large-v3-v20240930_626MB")
    #expect(configuration.cleanupMode == .dictation)
}
