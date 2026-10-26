import Foundation

public enum TranscriptionEngine: String, CaseIterable, Sendable, Equatable {
    case openAI
    case deepgram
    case whisperKit
    case whisperCpp

    public var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .deepgram:
            return "Deepgram"
        case .whisperKit:
            return "WhisperKit"
        case .whisperCpp:
            return "whisper.cpp"
        }
    }

    /// The service that transcribes for this engine, or nil when it transcribes on this Mac.
    public var cloudService: CloudService? {
        switch self {
        case .openAI:
            return .openAI
        case .deepgram:
            return .deepgram
        case .whisperKit, .whisperCpp:
            return nil
        }
    }
}
