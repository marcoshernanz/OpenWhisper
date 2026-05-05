import Foundation

public struct WhisperConfiguration: Sendable, Equatable {
    public let executableURL: URL
    public let modelURL: URL
    public let language: String

    public init(executableURL: URL, modelURL: URL, language: String = "auto") {
        self.executableURL = executableURL
        self.modelURL = modelURL
        self.language = language
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
            modelURL: URL(fileURLWithPath: model),
            language: environment["OPENWHISPER_LANGUAGE"] ?? "auto"
        )
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

    private static func readAppSupportConfiguration() -> (executablePath: String?, modelPath: String?) {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return (nil, nil)
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
            return (nil, nil)
        }

        return (
            dictionary["whisperExecutable"],
            dictionary["model"]
        )
    }

    private static func expandHome(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return (path as NSString).expandingTildeInPath
    }
}
