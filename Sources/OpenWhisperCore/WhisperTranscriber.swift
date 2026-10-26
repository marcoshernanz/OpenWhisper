import Foundation

public struct WhisperTranscriber: Sendable {
    private let configuration: WhisperConfiguration
    private let cleaner: TranscriptionOutputCleaner
    private let localCleaner: LocalTranscriptCleaner
    private let serverClient: WhisperServerClient
    private let whisperKitTranscriber: WhisperKitTranscriber
    private let deepgramTranscriber: DeepgramTranscriber?

    public init(
        configuration: WhisperConfiguration,
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
        if configuration.transcriptionEngine == .deepgram, let apiKey = configuration.deepgramAPIKey {
            self.deepgramTranscriber = DeepgramTranscriber(
                apiKey: apiKey,
                language: configuration.language,
                vocabulary: configuration.initialPrompt
            )
        } else {
            self.deepgramTranscriber = nil
        }
    }

    /// With Deepgram, the local model loads only once Deepgram fails, so it takes no memory until then.
    public func warmUpServer() async {
        switch configuration.transcriptionEngine {
        case .deepgram:
            await deepgramTranscriber?.warmUp()
        case .whisperKit:
            try? await whisperKitTranscriber.warmUp()
        case .whisperCpp:
            try? await serverClient.warmUp()
        }
    }

    public func stopServer() async {
        await serverClient.stop()
    }

    /// A recording that Deepgram cannot transcribe, such as without a connection, is transcribed on this Mac.
    public func transcribe(wavURL: URL) async throws -> TranscriptionOutcome {
        guard let deepgramTranscriber else {
            return TranscriptionOutcome(text: try await transcribeOnThisMac(wavURL: wavURL))
        }

        let deepgramFailure: DeepgramError
        do {
            let start = Date()
            let transcript = try await deepgramTranscriber.transcribe(wavURL: wavURL)
            NSLog("OpenWhisper transcribed \(Self.recordingDescription(wavURL)) with Deepgram in \(String(format: "%.2f", Date().timeIntervalSince(start))) s")
            return TranscriptionOutcome(text: cleanup(transcript))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            NSLog("OpenWhisper transcribing on this Mac after Deepgram failed: \(error.localizedDescription)")
            deepgramFailure = error as? DeepgramError
                ?? .unreachable(code: (error as? URLError)?.code ?? .unknown, message: error.localizedDescription)
        }

        do {
            return TranscriptionOutcome(text: try await transcribeOnThisMac(wavURL: wavURL), deepgramFailure: deepgramFailure)
        } catch {
            throw TranscriptionError.deepgramAndThisMacFailed(
                deepgram: deepgramFailure.localizedDescription,
                thisMac: error.localizedDescription
            )
        }
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

public struct TranscriptionOutcome: Sendable, Equatable {
    public let text: String
    /// Why Deepgram was not used, when the recording was transcribed on this Mac instead.
    public let deepgramFailure: DeepgramError?

    public init(text: String, deepgramFailure: DeepgramError? = nil) {
        self.text = text
        self.deepgramFailure = deepgramFailure
    }
}

public enum TranscriptionError: Error, LocalizedError, Equatable {
    case missingRequirement(String)
    case serverUnavailable(String)
    case deepgramAndThisMacFailed(deepgram: String, thisMac: String)

    public var errorDescription: String? {
        switch self {
        case .missingRequirement(let message):
            return message
        case .serverUnavailable(let message):
            return "whisper-server is unavailable: \(message)"
        case .deepgramAndThisMacFailed(let deepgram, let thisMac):
            return "\(deepgram)\n\nTranscribing on this Mac failed too: \(thisMac)"
        }
    }
}
