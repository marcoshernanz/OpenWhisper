import Foundation

public enum WhisperModelOption: String, CaseIterable, Sendable, Equatable {
    case largeV3Turbo = "large-v3-turbo"
    case largeV3 = "large-v3"
    case distilLargeV3 = "distil-large-v3"
    case mediumEnglish = "medium.en"
    case smallEnglish = "small.en"
    case baseEnglish = "base.en"
    case tinyEnglish = "tiny.en"

    public var displayName: String {
        switch self {
        case .largeV3Turbo:
            return "Large v3 Turbo"
        case .largeV3:
            return "Large v3"
        case .distilLargeV3:
            return "Distil Large v3"
        case .mediumEnglish:
            return "Medium English"
        case .smallEnglish:
            return "Small English"
        case .baseEnglish:
            return "Base English"
        case .tinyEnglish:
            return "Tiny English"
        }
    }

    public var fileName: String {
        switch self {
        case .distilLargeV3:
            return "ggml-distil-large-v3.bin"
        default:
            return "ggml-\(rawValue).bin"
        }
    }

    public var setupArgument: String {
        rawValue
    }

    public static func option(forFileName fileName: String) -> WhisperModelOption? {
        allCases.first { $0.fileName == fileName }
    }
}
