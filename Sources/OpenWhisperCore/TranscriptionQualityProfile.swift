import Foundation

public enum TranscriptionQualityProfile: String, CaseIterable, Sendable, Equatable {
    case fast
    case balanced
    case accurate

    public var displayName: String {
        switch self {
        case .fast:
            return "Fast"
        case .balanced:
            return "Balanced"
        case .accurate:
            return "Accurate"
        }
    }

    public var audioContext: Int {
        switch self {
        case .fast:
            return 512
        case .balanced, .accurate:
            return 0
        }
    }

    public var beamSize: Int {
        switch self {
        case .fast:
            return 1
        case .balanced:
            return 2
        case .accurate:
            return 5
        }
    }

    public var bestOf: Int {
        switch self {
        case .fast:
            return 1
        case .balanced:
            return 2
        case .accurate:
            return 5
        }
    }

    public var temperature: Double {
        0
    }

    public var temperatureIncrement: Double {
        switch self {
        case .fast:
            return 0
        case .balanced, .accurate:
            return 0.2
        }
    }

    public var suppressNonSpeechTokens: Bool {
        true
    }
}
