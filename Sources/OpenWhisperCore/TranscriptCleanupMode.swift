import Foundation

public enum TranscriptCleanupMode: String, CaseIterable, Sendable, Equatable {
    case off
    case light
    case dictation

    public var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .light:
            return "Light"
        case .dictation:
            return "Dictation"
        }
    }
}
