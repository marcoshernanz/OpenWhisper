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
        let results = try await pipelineBox.pipeline.transcribe(
            audioPath: wavURL.path,
            decodeOptions: decodingOptions(promptTokens: pipelineBox.promptTokens)
        )

        let transcript = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if Self.isSilenceHallucination(transcript, audioURL: wavURL) {
            return ""
        }

        return transcript
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
            promptTokens: promptTokens,
            chunkingStrategy: .vad
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
    /// misspell, such as "GitHub" in a Spanish sentence.
    private func vocabularyPromptTokens(for pipeline: WhisperKit) -> [Int]? {
        guard !configuration.initialPrompt.isEmpty, let tokenizer = pipeline.tokenizer else {
            return nil
        }

        return tokenizer
            .encode(text: " " + configuration.initialPrompt)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
    }

    /// Whisper turns silence, such as an accidental fn press, into short stock phrases or a lone ".".
    /// Only drop the phrases when the recording really is silent, so that dictating "Thank you." still works.
    private static func isSilenceHallucination(_ transcript: String, audioURL: URL) -> Bool {
        let normalized = transcript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if normalized.isEmpty {
            return true
        }

        guard silenceHallucinations.contains(normalized),
              let samples = try? AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        else {
            return false
        }

        // -40 dBFS: well above a quiet room, and below even softly spoken words.
        return !EnergyVAD(energyThreshold: 0.01).voiceActivity(in: samples).contains(true)
    }

    private static let silenceHallucinations: Set<String> = [
        "you",
        "thank",
        "thank you",
        "thanks for watching",
        "thank you for watching",
        "gracias"
    ]
}

private final class WhisperKitPipelineBox: @unchecked Sendable {
    let pipeline: WhisperKit
    let promptTokens: [Int]?

    init(pipeline: WhisperKit, promptTokens: [Int]?) {
        self.pipeline = pipeline
        self.promptTokens = promptTokens
    }
}
