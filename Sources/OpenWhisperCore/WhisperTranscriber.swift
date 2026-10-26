import Foundation

public struct WhisperTranscriber: Sendable {
    private let configuration: WhisperConfiguration
    private let cleaner: TranscriptionOutputCleaner
    private let localCleaner: LocalTranscriptCleaner
    private let serverClient: WhisperServerClient
    private let whisperKitTranscriber: WhisperKitTranscriber
    private let cloudTranscribers: [any CloudTranscriber]

    public init(
        configuration: WhisperConfiguration,
        cleaner: TranscriptionOutputCleaner = TranscriptionOutputCleaner(),
        localCleaner: LocalTranscriptCleaner = LocalTranscriptCleaner()
    ) {
        let cloudTranscribers = configuration.cloudServices.compactMap { service in
            configuration.apiKeys[service].map {
                service.transcriber(apiKey: $0, language: configuration.language, vocabulary: configuration.initialPrompt)
            }
        }
        self.init(
            configuration: configuration,
            cloudTranscribers: cloudTranscribers,
            cleaner: cleaner,
            localCleaner: localCleaner
        )
    }

    init(
        configuration: WhisperConfiguration,
        cloudTranscribers: [any CloudTranscriber],
        cleaner: TranscriptionOutputCleaner = TranscriptionOutputCleaner(),
        localCleaner: LocalTranscriptCleaner = LocalTranscriptCleaner()
    ) {
        self.configuration = configuration
        self.cleaner = cleaner
        self.localCleaner = localCleaner
        let serverProcess = WhisperServerProcess(configuration: configuration)
        self.whisperKitTranscriber = WhisperKitTranscriber(configuration: configuration)
        self.serverClient = WhisperServerClient(
            configuration: configuration,
            serverProcess: serverProcess,
            cleaner: cleaner
        )
        self.cloudTranscribers = cloudTranscribers
    }

    /// With a cloud service, the local model loads only once every service fails, so it takes no memory until
    /// then.
    public func warmUpServer() async {
        switch configuration.transcriptionEngine {
        case .openAI, .deepgram:
            await cloudTranscribers.first?.warmUp()
        case .whisperKit:
            try? await whisperKitTranscriber.warmUp()
        case .whisperCpp:
            try? await serverClient.warmUp()
        }
    }

    public func stopServer() async {
        await serverClient.stop()
    }

    /// Each cloud service is tried in turn, and a recording none of them transcribes, such as without a
    /// connection, is transcribed on this Mac.
    public func transcribe(wavURL: URL) async throws -> TranscriptionOutcome {
        let cloudFailures: [CloudTranscriptionError]
        switch try await transcribeWithCloudServices(wavURL: wavURL) {
        case .transcribed(let outcome):
            return outcome
        case .failed(let failures) where failures.isEmpty:
            return TranscriptionOutcome(text: try await transcribeOnThisMac(wavURL: wavURL))
        case .failed(let failures):
            cloudFailures = failures
        }

        do {
            return TranscriptionOutcome(text: try await transcribeOnThisMac(wavURL: wavURL), cloudFailures: cloudFailures)
        } catch {
            throw TranscriptionError.cloudAndThisMacFailed(
                cloud: cloudFailures.map(\.localizedDescription),
                thisMac: error.localizedDescription
            )
        }
    }

    func transcribeWithCloudServices(wavURL: URL) async throws -> CloudAttempt {
        var failures: [CloudTranscriptionError] = []

        for cloudTranscriber in cloudTranscribers {
            let service = cloudTranscriber.service
            do {
                let start = Date()
                let transcript = try await cloudTranscriber.transcribe(wavURL: wavURL)
                NSLog("OpenWhisper transcribed \(Self.recordingDescription(wavURL)) with \(service.displayName) in \(String(format: "%.2f", Date().timeIntervalSince(start))) s")
                return .transcribed(TranscriptionOutcome(text: cleanup(transcript), service: service, cloudFailures: failures))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                NSLog("OpenWhisper \(service.displayName) failed: \(error.localizedDescription)")
                let failure = error as? CloudTranscriptionError
                    ?? CloudTranscriptionError(service, .unreachable(code: (error as? URLError)?.code ?? .unknown, message: error.localizedDescription))
                failures.append(failure)
                if failure.isOffline {
                    break
                }
            }
        }

        return .failed(failures)
    }

    private func transcribeOnThisMac(wavURL: URL) async throws -> String {
        if configuration.transcriptionEngine != .whisperCpp {
            do {
                return cleanup(try await whisperKitTranscriber.transcribe(wavURL: wavURL))
            } catch {
                NSLog("OpenWhisper WhisperKit transcription failed, falling back to whisper.cpp: \(error.localizedDescription)")
            }
        }

        return try await transcribeWithWhisperCpp(wavURL: wavURL)
    }

    private static func recordingDescription(_ wavURL: URL) -> String {
        let bytes = (try? wavURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return String(format: "%.1f s", Double(bytes) / Double(WAVFile.bytesPerSecond))
    }

    private func transcribeWithWhisperCpp(wavURL: URL) async throws -> String {
        if configuration.missingServerRequirementMessage == nil {
            do {
                return cleanup(try await serverClient.transcribe(wavURL: wavURL))
            } catch {
                NSLog("OpenWhisper server transcription failed, falling back to whisper-cli: \(error.localizedDescription)")
            }
        }

        if let missingRequirementMessage = configuration.missingRequirementMessage {
            throw TranscriptionError.missingRequirement(missingRequirementMessage)
        }

        let outputBaseURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("openwhisper-\(UUID().uuidString)")
        let command = WhisperCommand(
            configuration: configuration,
            audioURL: wavURL,
            outputBaseURL: outputBaseURL
        )

        let result = try await Shell.run(
            executableURL: configuration.executableURL,
            arguments: command.arguments
        )

        if let transcript = try? String(contentsOf: command.transcriptURL, encoding: .utf8) {
            try? FileManager.default.removeItem(at: command.transcriptURL)
            return cleanup(cleaner.clean(transcript))
        }

        return cleanup(cleaner.clean(result.stdout))
    }

    private func cleanup(_ transcript: String) -> String {
        localCleaner.clean(transcript, mode: configuration.cleanupMode)
    }
}

enum CloudAttempt: Equatable {
    case transcribed(TranscriptionOutcome)
    /// Why each service tried did not transcribe the recording, with none when there was no service to try.
    case failed([CloudTranscriptionError])
}

public struct TranscriptionOutcome: Sendable, Equatable {
    public let text: String
    /// The service that transcribed the recording, or nil when this Mac did.
    public let service: CloudService?
    /// Why the services tried before it did not transcribe the recording.
    public let cloudFailures: [CloudTranscriptionError]

    public init(text: String, service: CloudService? = nil, cloudFailures: [CloudTranscriptionError] = []) {
        self.text = text
        self.service = service
        self.cloudFailures = cloudFailures
    }
}

public enum TranscriptionError: Error, LocalizedError, Equatable {
    case missingRequirement(String)
    case serverUnavailable(String)
    case cloudAndThisMacFailed(cloud: [String], thisMac: String)

    public var errorDescription: String? {
        switch self {
        case .missingRequirement(let message):
            return message
        case .serverUnavailable(let message):
            return "whisper-server is unavailable: \(message)"
        case .cloudAndThisMacFailed(let cloud, let thisMac):
            return "\(cloud.joined(separator: "\n"))\n\nTranscribing on this Mac failed too: \(thisMac)"
        }
    }
}
