import Foundation

/// The most recent transcripts, newest first, saved so that a dictation can still be recovered after a
/// newer one replaces it.
public struct TranscriptHistory: Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let date: Date
        public let text: String

        public init(date: Date, text: String) {
            self.date = date
            self.text = text
        }

        /// The text on one line, cut to `maxLength` characters.
        public func preview(maxLength: Int) -> String {
            let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard line.count > maxLength else { return line }

            return line.prefix(maxLength - 1).trimmingCharacters(in: .whitespaces) + "…"
        }
    }

    public static let defaultLimit = 50

    public static var defaultFileURL: URL {
        WhisperConfiguration.appSupportDirectory().appendingPathComponent("TranscriptHistory.json")
    }

    public private(set) var entries: [Entry]
    private let fileURL: URL
    private let limit: Int

    /// A missing or unreadable file starts an empty history.
    public init(fileURL: URL = TranscriptHistory.defaultFileURL, limit: Int = TranscriptHistory.defaultLimit) {
        self.fileURL = fileURL
        self.limit = limit

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? Data(contentsOf: fileURL))
            .flatMap { try? decoder.decode([Entry].self, from: $0) }
            ?? []
    }

    /// Keeps the transcript in memory even when saving it fails.
    public mutating func add(_ text: String, date: Date = Date()) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        entries.insert(Entry(date: date, text: text), at: 0)
        entries = Array(entries.prefix(limit))
        try save()
    }

    public mutating func clear() throws {
        entries = []
        try save()
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(entries).write(to: fileURL, options: .atomic)
    }
}
