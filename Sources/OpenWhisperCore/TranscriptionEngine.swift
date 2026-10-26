import Foundation

public enum TranscriptionEngine: String, CaseIterable, Sendable, Equatable {
    case deepgram
    case whisperKit
    case whisperCpp

    public var displayName: String {
        switch self {
        case .deepgram:
            return "Deepgram"
        case .whisperKit:
            return "WhisperKit"
        case .whisperCpp:
            return "whisper.cpp"
        }
    }
}
