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
            decodeOptions: decodingOptions
        )

        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var decodingOptions: DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: configuration.usesAutomaticLanguageDetection ? nil : configuration.language,
            temperature: Float(configuration.temperature),
            temperatureIncrementOnFallback: Float(configuration.temperatureIncrement),
            detectLanguage: configuration.usesAutomaticLanguageDetection,
            skipSpecialTokens: true,
            withoutTimestamps: true,
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

        let whisperKitConfig = WhisperKitConfig(
            model: configuration.whisperKitModel,
            downloadBase: configuration.whisperKitModelDirectory,
            computeOptions: ModelComputeOptions(),
            verbose: false,
            prewarm: false,
            load: true,
            download: true
        )
        let pipelineBox = WhisperKitPipelineBox(pipeline: try await WhisperKit(whisperKitConfig))
        self.pipelineBox = pipelineBox
        NSLog("OpenWhisper loaded WhisperKit model \(configuration.whisperKitModel)")
        return pipelineBox
    }
}

private final class WhisperKitPipelineBox: @unchecked Sendable {
    let pipeline: WhisperKit

    init(pipeline: WhisperKit) {
        self.pipeline = pipeline
    }
}
