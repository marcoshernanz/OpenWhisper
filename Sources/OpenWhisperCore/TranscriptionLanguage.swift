import Foundation

public enum TranscriptionLanguage: String, CaseIterable, Sendable, Equatable {
    case english = "en"
    case spanish = "es"
    case auto = "auto"

    public var displayName: String {
        switch self {
        case .english:
            return "English"
        case .spanish:
            return "Spanish"
        case .auto:
            return "Auto Detect"
        }
    }
}
