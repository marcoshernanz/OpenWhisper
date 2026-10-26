import Foundation

/// Keeps the most recent recordings, each with a JSON file of its transcript beside it, so engines can be
/// compared on real dictations.
public struct RecordingArchive: Sendable {
    public static let standard = RecordingArchive(
        directory: WhisperConfiguration.appSupportDirectory().appendingPathComponent("Recordings")
    )
    public static let defaultLimit = 30

    public let directory: URL
    private let limit: Int

    public init(directory: URL, limit: Int = RecordingArchive.defaultLimit) {
        self.directory = directory
        self.limit = limit
    }

    /// Moves the recording into the archive, and removes the oldest ones beyond the limit.
    public func keep(_ recordingURL: URL, outcome: TranscriptionOutcome, date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let name = Self.name(for: date)
        let entry = Entry(
            date: date,
            transcript: outcome.text,
            transcribedWith: outcome.service?.displayName ?? "This Mac",
            cloudFailures: outcome.cloudFailures.map(\.localizedDescription)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        try FileManager.default.moveItem(at: recordingURL, to: directory.appendingPathComponent("\(name).wav"))
        try encoder.encode(entry).write(to: directory.appendingPathComponent("\(name).json"))
        removeOldest()
    }

    /// Recordings sort by their names, which start with the date.
    private func removeOldest() {
        let recordings = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let names = Set(recordings.map { $0.deletingPathExtension().lastPathComponent })

        for name in names.sorted(by: >).dropFirst(limit) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(name).wav"))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(name).json"))
        }
    }

    private static func name(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        return formatter.string(from: date)
    }

    private struct Entry: Encodable {
        let date: Date
        let transcript: String
        let transcribedWith: String
        let cloudFailures: [String]
    }
}
