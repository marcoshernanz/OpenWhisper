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
