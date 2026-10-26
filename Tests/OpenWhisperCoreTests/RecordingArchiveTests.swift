import Foundation
import Testing
@testable import OpenWhisperCore

@Test func keepsTheMostRecentRecordingsWithTheirTranscripts() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("openwhisper-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let archive = RecordingArchive(directory: directory, limit: 2)
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    for index in 0..<3 {
        let recording = try writeRecording([Int16(index)])
        let outcome = TranscriptionOutcome(
            text: "Dictation \(index).",
            service: .deepgram,
            cloudFailures: [CloudTranscriptionError(.openAI, .unavailable(statusCode: 503, message: ""))]
        )
        try archive.keep(recording, outcome: outcome, date: start.addingTimeInterval(Double(index)))
        #expect(!FileManager.default.fileExists(atPath: recording.path))
    }

    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    #expect(files.count == 4)

    let newest = try #require(files.last { $0.hasSuffix(".json") })
    let entry = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent(newest))) as? [String: Any]
    #expect(entry?["transcript"] as? String == "Dictation 2.")
    #expect(entry?["transcribedWith"] as? String == "Deepgram")
    #expect(entry?["cloudFailures"] as? [String] == ["OpenAI is unavailable (HTTP 503)."])

    let oldest = try #require(files.first { $0.hasSuffix(".wav") })
    #expect(try Data(contentsOf: directory.appendingPathComponent(oldest)) == wav([1]))
}
