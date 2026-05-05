import Foundation

public struct WhisperConfiguration: Sendable, Equatable {
    public let executableURL: URL
    public let serverExecutableURL: URL
    public let modelURL: URL
    public let language: String
    public let serverHost: String
    public let serverPort: Int
    public let serverThreadCount: Int
    public let audioContext: Int

    public init(
        executableURL: URL,
        serverExecutableURL: URL? = nil,
        modelURL: URL,
        language: String = "en",
        serverHost: String = "127.0.0.1",
        serverPort: Int = 58442,
        serverThreadCount: Int = WhisperConfiguration.defaultServerThreadCount,
        audioContext: Int = 512
    ) {
        self.executableURL = executableURL
        self.serverExecutableURL = serverExecutableURL
            ?? executableURL.deletingLastPathComponent().appendingPathComponent("whisper-server")
        self.modelURL = modelURL
        self.language = language
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.serverThreadCount = max(1, serverThreadCount)
        self.audioContext = max(0, audioContext)
    }

    public static func resolved(
        bundleURL: URL,
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> WhisperConfiguration {
        let repoRoot = inferRepoRoot(bundleURL: bundleURL, currentDirectoryURL: currentDirectoryURL)
        let appSupportConfiguration = readAppSupportConfiguration()
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

        let model = firstExistingPath(
            candidates: [
                environment["OPENWHISPER_MODEL"],
                appSupportConfiguration.modelPath,
                repoRoot.appendingPathComponent("Models/ggml-large-v3-turbo.bin").path,
                repoRoot.appendingPathComponent("Models/ggml-large-v3.bin").path,
                repoRoot.appendingPathComponent("Models/ggml-medium.en.bin").path,
                repoRoot.appendingPathComponent("Models/ggml-base.en.bin").path,
                repoRoot.appendingPathComponent("Models/ggml-tiny.en.bin").path
            ]
        ) ?? expandHome(environment["OPENWHISPER_MODEL"])
            ?? expandHome(appSupportConfiguration.modelPath)
            ?? repoRoot.appendingPathComponent("Models/ggml-large-v3-turbo.bin").path

        return WhisperConfiguration(
            executableURL: URL(fileURLWithPath: executable),
            serverExecutableURL: URL(fileURLWithPath: serverExecutable),
            modelURL: URL(fileURLWithPath: model),
            language: environment["OPENWHISPER_LANGUAGE"] ?? "en",
            serverHost: environment["OPENWHISPER_SERVER_HOST"] ?? "127.0.0.1",
            serverPort: Int(environment["OPENWHISPER_SERVER_PORT"] ?? "") ?? 58442,
            serverThreadCount: Int(environment["OPENWHISPER_THREADS"] ?? "")
                ?? WhisperConfiguration.defaultServerThreadCount,
            audioContext: Int(environment["OPENWHISPER_AUDIO_CONTEXT"] ?? "") ?? 512
        )
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

    private static func readAppSupportConfiguration() -> (
        executablePath: String?,
        serverExecutablePath: String?,
        modelPath: String?
    ) {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return (nil, nil, nil)
        }

        let configurationURL = applicationSupportURL
            .appendingPathComponent("OpenWhisper")
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
}
