import Foundation

public struct WhisperConfiguration: Sendable, Equatable {
    public let executableURL: URL
    public let serverExecutableURL: URL
    public let modelURL: URL
    public let language: String
    public let serverHost: String
    public let serverPort: Int
    public let serverThreadCount: Int
    public let transcriptionEngine: LocalTranscriptionEngine
    public let qualityProfile: TranscriptionQualityProfile
    public let cleanupMode: TranscriptCleanupMode
    public let initialPrompt: String
    public let modelOption: WhisperModelOption?
    public let whisperKitModel: String
    public let whisperKitModelDirectory: URL

    public init(
        executableURL: URL,
        serverExecutableURL: URL? = nil,
        modelURL: URL,
        language: String = "en",
        serverHost: String = "127.0.0.1",
        serverPort: Int = 58442,
        serverThreadCount: Int = WhisperConfiguration.defaultServerThreadCount,
        transcriptionEngine: LocalTranscriptionEngine = .whisperKit,
        qualityProfile: TranscriptionQualityProfile = .balanced,
        cleanupMode: TranscriptCleanupMode = .dictation,
        initialPrompt: String = "",
        modelOption: WhisperModelOption? = nil,
        whisperKitModel: String = WhisperConfiguration.defaultWhisperKitModel,
        whisperKitModelDirectory: URL = WhisperConfiguration.defaultWhisperKitModelDirectory
    ) {
        self.executableURL = executableURL
        self.serverExecutableURL = serverExecutableURL
            ?? executableURL.deletingLastPathComponent().appendingPathComponent("whisper-server")
        self.modelURL = modelURL
        self.language = language
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.serverThreadCount = max(1, serverThreadCount)
        self.transcriptionEngine = transcriptionEngine
        self.qualityProfile = qualityProfile
        self.cleanupMode = cleanupMode
        self.initialPrompt = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelOption = modelOption ?? WhisperModelOption.option(forFileName: modelURL.lastPathComponent)
        self.whisperKitModel = whisperKitModel
        self.whisperKitModelDirectory = whisperKitModelDirectory
    }

    public static func resolved(
        bundleURL: URL,
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> WhisperConfiguration {
        let repoRoot = inferRepoRoot(bundleURL: bundleURL, currentDirectoryURL: currentDirectoryURL)
        let appSupportConfiguration = readAppSupportConfiguration()
        let defaults = UserDefaults.standard
        let transcriptionEngine = LocalTranscriptionEngine(
            rawValue: environment["OPENWHISPER_ENGINE"]
                ?? defaults.string(forKey: OpenWhisperDefaultsKey.transcriptionEngine)
                ?? ""
        ) ?? .whisperKit
        let selectedModelOption = WhisperModelOption(
            rawValue: environment["OPENWHISPER_MODEL_OPTION"]
                ?? defaults.string(forKey: OpenWhisperDefaultsKey.modelOption)
                ?? ""
        )
        let qualityProfile = TranscriptionQualityProfile(
            rawValue: environment["OPENWHISPER_QUALITY"]
                ?? defaults.string(forKey: OpenWhisperDefaultsKey.qualityProfile)
                ?? ""
        ) ?? .balanced
        let cleanupMode = TranscriptCleanupMode(
            rawValue: environment["OPENWHISPER_CLEANUP"]
                ?? defaults.string(forKey: OpenWhisperDefaultsKey.cleanupMode)
                ?? ""
        ) ?? .dictation
        let initialPrompt = environment["OPENWHISPER_PROMPT"]
            ?? defaults.string(forKey: OpenWhisperDefaultsKey.initialPrompt)
            ?? ""
        let whisperKitModel = environment["OPENWHISPER_WHISPERKIT_MODEL"]
            ?? defaultWhisperKitModel
        let whisperKitModelDirectory = URL(
            fileURLWithPath: expandHome(environment["OPENWHISPER_WHISPERKIT_MODEL_DIR"])
                ?? appSupportDirectory()
                    .appendingPathComponent("WhisperKit")
                    .path
        )
        let executable = firstExistingPath(
            candidates: [
                environment["OPENWHISPER_WHISPER_BIN"],
                appSupportConfiguration.executablePath,
                repoRoot.appendingPathComponent("Dependencies/whisper.cpp/build/bin/whisper-cli").path,
                repoRoot.appendingPathComponent("Dependencies/whisper.cpp/build/bin/Release/whisper-cli").path,
                "/opt/homebrew/bin/whisper-cli",
                "/usr/local/bin/whisper-cli"
            ]
        ) ?? expandHome(environment["OPENWHISPER_WHISPER_BIN"])
            ?? repoRoot.appendingPathComponent("Dependencies/whisper.cpp/build/bin/whisper-cli").path

        let serverExecutable = firstExistingPath(
            candidates: [
                environment["OPENWHISPER_SERVER_BIN"],
                appSupportConfiguration.serverExecutablePath,
                repoRoot.appendingPathComponent("Dependencies/whisper.cpp/build/bin/whisper-server").path,
                repoRoot.appendingPathComponent("Dependencies/whisper.cpp/build/bin/Release/whisper-server").path,
                "/opt/homebrew/bin/whisper-server",
                "/usr/local/bin/whisper-server"
            ]
        ) ?? expandHome(environment["OPENWHISPER_SERVER_BIN"])
            ?? repoRoot.appendingPathComponent("Dependencies/whisper.cpp/build/bin/whisper-server").path

        let model = resolvedModelPath(
            repoRoot: repoRoot,
            environmentModelPath: environment["OPENWHISPER_MODEL"],
            appSupportModelPath: appSupportConfiguration.modelPath,
            selectedModelOption: selectedModelOption
        )

        return WhisperConfiguration(
            executableURL: URL(fileURLWithPath: executable),
            serverExecutableURL: URL(fileURLWithPath: serverExecutable),
            modelURL: URL(fileURLWithPath: model),
            language: environment["OPENWHISPER_LANGUAGE"] ?? "en",
            serverHost: environment["OPENWHISPER_SERVER_HOST"] ?? "127.0.0.1",
            serverPort: Int(environment["OPENWHISPER_SERVER_PORT"] ?? "") ?? 58442,
            serverThreadCount: Int(environment["OPENWHISPER_THREADS"] ?? "")
                ?? WhisperConfiguration.defaultServerThreadCount,
            transcriptionEngine: transcriptionEngine,
            qualityProfile: qualityProfile,
            cleanupMode: cleanupMode,
            initialPrompt: initialPrompt,
            modelOption: selectedModelOption,
            whisperKitModel: whisperKitModel,
            whisperKitModelDirectory: whisperKitModelDirectory
        )
    }

    public static let defaultWhisperKitModel = "openai_whisper-large-v3-v20240930_626MB"

    public static var defaultWhisperKitModelDirectory: URL {
        appSupportDirectory().appendingPathComponent("WhisperKit")
    }

    public static var defaultServerThreadCount: Int {
        min(8, max(4, ProcessInfo.processInfo.activeProcessorCount - 2))
    }

    public var missingRequirementMessage: String? {
        let fileManager = FileManager.default

        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            return "Missing whisper.cpp executable at \(executableURL.path). Run scripts/setup-whisper.sh."
        }

        guard fileManager.fileExists(atPath: modelURL.path) else {
            return "Missing Whisper model at \(modelURL.path). Run scripts/setup-whisper.sh large-v3-turbo."
        }

        return nil
    }

    public var missingServerRequirementMessage: String? {
        let fileManager = FileManager.default

        guard fileManager.isExecutableFile(atPath: serverExecutableURL.path) else {
            return "Missing whisper.cpp server at \(serverExecutableURL.path). Run scripts/setup-whisper.sh."
        }

        guard fileManager.fileExists(atPath: modelURL.path) else {
            return "Missing Whisper model at \(modelURL.path). Run scripts/setup-whisper.sh large-v3-turbo."
        }

        return nil
    }

    public var serverHealthURL: URL {
        URL(string: "http://\(serverHost):\(serverPort)/health")!
    }

    public var serverInferenceURL: URL {
        URL(string: "http://\(serverHost):\(serverPort)/inference")!
    }

    public var audioContext: Int {
        qualityProfile.audioContext
    }

    public var beamSize: Int {
        qualityProfile.beamSize
    }

    public var bestOf: Int {
        qualityProfile.bestOf
    }

    public var temperature: Double {
        qualityProfile.temperature
    }

    public var temperatureIncrement: Double {
        qualityProfile.temperatureIncrement
    }

    public var suppressNonSpeechTokens: Bool {
        qualityProfile.suppressNonSpeechTokens
    }

    private static func inferRepoRoot(bundleURL: URL, currentDirectoryURL: URL) -> URL {
        if bundleURL.pathExtension == "app",
           bundleURL.deletingLastPathComponent().lastPathComponent == ".build" {
            return bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        }

        if FileManager.default.fileExists(
            atPath: currentDirectoryURL.appendingPathComponent("Package.swift").path
        ) {
            return currentDirectoryURL
        }

        return bundleURL.deletingLastPathComponent()
    }

    private static func firstExistingPath(candidates: [String?]) -> String? {
        candidates
            .compactMap(expandHome)
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func resolvedModelPath(
        repoRoot: URL,
        environmentModelPath: String?,
        appSupportModelPath: String?,
        selectedModelOption: WhisperModelOption?
    ) -> String {
        if let environmentModel = expandHome(environmentModelPath) {
            return environmentModel
        }

        let appSupportModel = expandHome(appSupportModelPath)
        let configuredModelsDirectory = appSupportModel.map {
            URL(fileURLWithPath: $0).deletingLastPathComponent()
        }
        let repoModelsDirectory = repoRoot.appendingPathComponent("Models")

        if let selectedModelOption {
            let selectedCandidates: [String?] = [
                configuredModelsDirectory?.appendingPathComponent(selectedModelOption.fileName).path,
                repoModelsDirectory.appendingPathComponent(selectedModelOption.fileName).path
            ]

            return firstExistingPath(candidates: selectedCandidates)
                ?? selectedCandidates.compactMap { $0 }.first
                ?? repoModelsDirectory.appendingPathComponent(selectedModelOption.fileName).path
        }

        return firstExistingPath(
            candidates: [
                appSupportModel,
                repoModelsDirectory.appendingPathComponent(WhisperModelOption.largeV3Turbo.fileName).path,
                repoModelsDirectory.appendingPathComponent(WhisperModelOption.largeV3.fileName).path,
                repoModelsDirectory.appendingPathComponent(WhisperModelOption.distilLargeV3.fileName).path,
                repoModelsDirectory.appendingPathComponent(WhisperModelOption.mediumEnglish.fileName).path,
                repoModelsDirectory.appendingPathComponent(WhisperModelOption.smallEnglish.fileName).path,
                repoModelsDirectory.appendingPathComponent(WhisperModelOption.baseEnglish.fileName).path,
                repoModelsDirectory.appendingPathComponent(WhisperModelOption.tinyEnglish.fileName).path
            ]
        ) ?? appSupportModel
            ?? repoModelsDirectory.appendingPathComponent(WhisperModelOption.largeV3Turbo.fileName).path
    }

    private static func readAppSupportConfiguration() -> (
        executablePath: String?,
        serverExecutablePath: String?,
        modelPath: String?
    ) {
        let configurationURL = appSupportDirectory()
            .appendingPathComponent("config.plist")

        guard let data = try? Data(contentsOf: configurationURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ),
              let dictionary = plist as? [String: String]
        else {
            return (nil, nil, nil)
        }

        return (
            dictionary["whisperExecutable"],
            dictionary["whisperServerExecutable"],
            dictionary["model"]
        )
    }

    private static func expandHome(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return (path as NSString).expandingTildeInPath
    }

    private static func appSupportDirectory() -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser

        return applicationSupportURL.appendingPathComponent("OpenWhisper")
    }
}
