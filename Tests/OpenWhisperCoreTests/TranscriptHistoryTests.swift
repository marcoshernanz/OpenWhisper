import Foundation
import Testing
@testable import OpenWhisperCore

private func temporaryHistoryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("openwhisper-history-\(UUID().uuidString)")
        .appendingPathComponent("TranscriptHistory.json")
}

@Test func keepsTranscriptsNewestFirstAcrossLaunches() throws {
    let url = temporaryHistoryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    var history = TranscriptHistory(fileURL: url)
    try history.add("First dictation.", date: Date(timeIntervalSince1970: 1_790_000_000))
    try history.add("Second dictation.", date: Date(timeIntervalSince1970: 1_790_000_060))

    let reloaded = TranscriptHistory(fileURL: url)

    #expect(reloaded.entries == [
        TranscriptHistory.Entry(date: Date(timeIntervalSince1970: 1_790_000_060), text: "Second dictation."),
        TranscriptHistory.Entry(date: Date(timeIntervalSince1970: 1_790_000_000), text: "First dictation.")
    ])
}

@Test func dropsTheOldestTranscriptsPastTheLimit() throws {
    let url = temporaryHistoryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    var history = TranscriptHistory(fileURL: url, limit: 3)
    for number in 1...5 {
        try history.add("Dictation \(number).")
    }

    #expect(history.entries.map(\.text) == ["Dictation 5.", "Dictation 4.", "Dictation 3."])
    #expect(TranscriptHistory(fileURL: url, limit: 3).entries.map(\.text) == history.entries.map(\.text))
}

@Test func keepsLongTranscriptsWhole() throws {
    let url = temporaryHistoryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let longTranscript = String(repeating: "A super long message with \"quotes\" and a / slash.\n", count: 500)

    var history = TranscriptHistory(fileURL: url)
    try history.add(longTranscript)

    #expect(TranscriptHistory(fileURL: url).entries.first?.text == longTranscript)
}

@Test func ignoresBlankTranscripts() throws {
    let url = temporaryHistoryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    var history = TranscriptHistory(fileURL: url)
    try history.add("  \n ")

    #expect(history.entries.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func clearingRemovesSavedTranscripts() throws {
    let url = temporaryHistoryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    var history = TranscriptHistory(fileURL: url)
    try history.add("Something private.")
    try history.clear()

    #expect(history.entries.isEmpty)
    #expect(TranscriptHistory(fileURL: url).entries.isEmpty)
}

@Test func startsEmptyWithoutAReadableFile() throws {
    let url = temporaryHistoryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    #expect(TranscriptHistory(fileURL: url).entries.isEmpty)

    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)

    #expect(TranscriptHistory(fileURL: url).entries.isEmpty)
}

@Test func previewsFitOnOneLine() {
    let entry = TranscriptHistory.Entry(date: Date(), text: "Hello there.\nThis is  a   longer dictation.")

    #expect(entry.preview(maxLength: 100) == "Hello there. This is a longer dictation.")
    #expect(entry.preview(maxLength: 13) == "Hello there.…")
    #expect(entry.preview(maxLength: 13).count == 13)
}
