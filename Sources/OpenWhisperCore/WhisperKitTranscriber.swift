import Foundation
import WhisperKit

public actor WhisperKitTranscriber {
    private let configuration: WhisperConfiguration
    private var pipelineBox: WhisperKitPipelineBox?

    public init(configuration: WhisperConfiguration) {
        self.configuration = configuration
    }

    public func warmUp() async throws {
        _ = try await loadPipeline()
    }

    public func transcribe(wavURL: URL) async throws -> String {
        let pipelineBox = try await loadPipeline()
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: wavURL.path)
        let windows = PauseSplitter.split(
            samples[...],
            maxPartLength: pipelineBox.maxWindowSamples,
            sampleRate: WhisperKit.sampleRate
        )
        let transcript = try await transcribe(windows: windows, using: pipelineBox)

        // Whisper turns silence, such as an accidental fn press, into a lone "." or similar.
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).isEmpty {
            return ""
        }

        return transcript
    }

    /// Whisper writes at most 224 tokens for each window of audio, and the vocabulary prompt counts
    /// against them. A window that runs out stops mid-sentence and the rest of its audio is never
    /// transcribed, so windows are kept short enough for what the prompt leaves, and a window that
    /// still runs out is transcribed again in two halves.
    ///
    /// Decoding many windows at once makes Core ML time out, so only a few run at a time.
    private func transcribe(windows: [ArraySlice<Float>], using pipelineBox: WhisperKitPipelineBox) async throws -> String {
        var pendingWindows = windows
        var transcripts: [(start: Int, text: String)] = []

        try await withThrowingTaskGroup(of: WindowTranscript.self) { group in
            var runningCount = 0

            while !pendingWindows.isEmpty || runningCount > 0 {
                while runningCount < Self.concurrentWindowCount, !pendingWindows.isEmpty {
                    let window = pendingWindows.removeFirst()
                    group.addTask {
                        try await self.transcribe(window: window, using: pipelineBox)
                    }
                    runningCount += 1
                }

                guard let windowTranscript = try await group.next() else { break }
                runningCount -= 1

                switch windowTranscript {
                case .text(let start, let text):
                    transcripts.append((start, text))
                case .ranOutOfTokens(let window):
                    NSLog("OpenWhisper ran out of tokens in a \(window.count / WhisperKit.sampleRate) s window, transcribing it in halves.")
                    pendingWindows.insert(
                        contentsOf: PauseSplitter.split(window, into: 2, sampleRate: WhisperKit.sampleRate),
                        at: 0
                    )
                }
            }
        }

        return Self.join(transcripts.sorted { $0.start < $1.start }.map(\.text))
    }

    /// Retries a window that fails, such as when Core ML times out, instead of losing its text.
    private func transcribe(window: ArraySlice<Float>, using pipelineBox: WhisperKitPipelineBox) async throws -> WindowTranscript {
        var attempt = 1

        while true {
            do {
                let results = try await pipelineBox.pipeline.transcribe(
                    audioArray: Array(window),
                    decodeOptions: decodingOptions(promptTokens: pipelineBox.promptTokens)
                )

                if results.contains(where: { pipelineBox.ranOutOfTokens($0) }),
                   window.count >= Self.shortestWindowToSplit {
                    return .ranOutOfTokens(window)
                }

                return .text(start: window.startIndex, text: Self.join(results.map(\.text)))
            } catch where attempt < Self.attemptsPerWindow && !(error is CancellationError) {
                NSLog("OpenWhisper retrying a window after it failed: \(error.localizedDescription)")
                attempt += 1
            }
        }
    }

    private static func join(_ transcripts: [String]) -> String {
        transcripts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func decodingOptions(promptTokens: [Int]?) -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: configuration.usesAutomaticLanguageDetection ? nil : configuration.language,
            temperature: Float(configuration.temperature),
            temperatureIncrementOnFallback: Float(configuration.temperatureIncrement),
            detectLanguage: configuration.usesAutomaticLanguageDetection,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens
        )
    }

    private func loadPipeline() async throws -> WhisperKitPipelineBox {
        if let pipelineBox {
            return pipelineBox
        }

        try FileManager.default.createDirectory(
            at: configuration.whisperKitModelDirectory,
            withIntermediateDirectories: true
        )
        NSLog(
            "OpenWhisper loading WhisperKit model \(configuration.whisperKitModel) in \(configuration.whisperKitModelDirectory.path)"
        )

        // A downloaded model loads straight from disk. Asking Hugging Face first makes loading fail
        // whenever the network is unavailable, even though nothing needs to be downloaded.
        let downloadedModelFolder = downloadedModelFolder()
        let whisperKitConfig = WhisperKitConfig(
            model: configuration.whisperKitModel,
            downloadBase: configuration.whisperKitModelDirectory,
            modelFolder: downloadedModelFolder?.path,
            computeOptions: ModelComputeOptions(),
            verbose: false,
            prewarm: false,
            load: true,
            download: downloadedModelFolder == nil
        )
        let pipeline = try await WhisperKit(whisperKitConfig)
        let pipelineBox = WhisperKitPipelineBox(
            pipeline: pipeline,
            promptTokens: vocabularyPromptTokens(for: pipeline)
        )
        self.pipelineBox = pipelineBox
        NSLog("OpenWhisper loaded WhisperKit model \(configuration.whisperKitModel)")
        return pipelineBox
    }

    private func downloadedModelFolder() -> URL? {
        let modelFolder = configuration.whisperKitModelDirectory
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(configuration.whisperKitModel)
        let requiredModels = ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"]
        let isComplete = requiredModels.allSatisfy {
            FileManager.default.fileExists(atPath: modelFolder.appendingPathComponent($0).path)
        }

        return isComplete ? modelFolder : nil
    }

    /// The InitialPrompt setting biases Whisper toward names and technical terms it would otherwise
    /// misspell, such as "GitHub" in a Spanish sentence. WhisperKit only reads its last 111 tokens.
    private func vocabularyPromptTokens(for pipeline: WhisperKit) -> [Int]? {
        guard !configuration.initialPrompt.isEmpty, let tokenizer = pipeline.tokenizer else {
            return nil
        }

        let tokens = tokenizer
            .encode(text: " " + configuration.initialPrompt)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            .suffix(Constants.maxTokenContext / 2 - 1)

        return tokens.isEmpty ? nil : Array(tokens)
    }

    private static let shortestWindowToSplit = 4 * WhisperKit.sampleRate
    private static let concurrentWindowCount = 4
    private static let attemptsPerWindow = 3
}

private enum WindowTranscript: Sendable {
    case text(start: Int, text: String)
    case ranOutOfTokens(ArraySlice<Float>)
}

private final class WhisperKitPipelineBox: @unchecked Sendable {
    let pipeline: WhisperKit
    let promptTokens: [Int]?
    /// The longest window whose transcript still fits in the tokens the prompt leaves, even for fast speech.
    let maxWindowSamples: Int
    /// The prompt goes in after a start-of-previous-text token.
    private let promptLength: Int

    init(pipeline: WhisperKit, promptTokens: [Int]?) {
        self.pipeline = pipeline
        self.promptTokens = promptTokens
        promptLength = promptTokens.map { $0.count + 1 } ?? 0

        // Start of transcript, language, task and no timestamps come before the transcript itself.
        let transcriptTokens = Constants.maxTokenContext - 1 - promptLength - 4
        maxWindowSamples = min(
            Constants.defaultWindowSamples,
            transcriptTokens * WhisperKit.sampleRate / Self.fastSpeechTokensPerSecond
        )
    }

    /// The decoder stops once the prompt and transcript fill its token context. A segment's tokens run from
    /// the start of transcript to an end token added afterwards. Coming within a couple of tokens of the
    /// limit counts too, because an unneeded split only costs time.
    func ranOutOfTokens(_ result: TranscriptionResult) -> Bool {
        result.segments.contains { segment in
            promptLength + segment.tokens.count - 1 >= Constants.maxTokenContext - 3
        }
    }

    /// Fast dictation in English and Spanish measured about six tokens a second.
    private static let fastSpeechTokensPerSecond = 6
}
