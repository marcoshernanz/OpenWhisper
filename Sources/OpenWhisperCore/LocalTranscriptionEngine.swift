import Foundation

public enum LocalTranscriptionEngine: String, CaseIterable, Sendable, Equatable {
    case whisperKit
    case whisperCpp

    public var displayName: String {
        switch self {
        case .whisperKit:
            return "WhisperKit"
        case .whisperCpp:
            return "whisper.cpp"
        }
    }
}
