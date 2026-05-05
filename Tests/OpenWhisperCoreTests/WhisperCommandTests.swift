import Foundation
import Testing
@testable import OpenWhisperCore

@Test func buildsWhisperCLIArgumentsForLocalTranscription() {
    let configuration = WhisperConfiguration(
        executableURL: URL(fileURLWithPath: "/tmp/whisper-cli"),
        modelURL: URL(fileURLWithPath: "/tmp/model.bin"),
        language: "auto"
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
        "-np"
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
    #expect(configuration.audioContext == 512)
}
