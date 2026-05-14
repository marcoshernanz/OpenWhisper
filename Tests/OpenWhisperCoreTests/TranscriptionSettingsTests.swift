import Foundation
import Testing
@testable import OpenWhisperCore

@Test func exposesQualityProfilesForDictationTradeoffs() {
    #expect(TranscriptionQualityProfile.fast.audioContext == 512)
    #expect(TranscriptionQualityProfile.fast.beamSize == 1)
    #expect(TranscriptionQualityProfile.balanced.audioContext == 0)
    #expect(TranscriptionQualityProfile.balanced.beamSize == 2)
    #expect(TranscriptionQualityProfile.accurate.audioContext == 0)
    #expect(TranscriptionQualityProfile.accurate.beamSize == 5)
    #expect(TranscriptionQualityProfile.accurate.bestOf == 5)
}

@Test func exposesLanguageModesForBilingualDictation() {
    #expect(TranscriptionLanguage.english.rawValue == "en")
    #expect(TranscriptionLanguage.spanish.rawValue == "es")
    #expect(TranscriptionLanguage.auto.rawValue == "auto")
    #expect(WhisperConfiguration.defaultLanguage == TranscriptionLanguage.auto.rawValue)

    let autoConfiguration = WhisperConfiguration(
        executableURL: URL(fileURLWithPath: "/tmp/whisper-cli"),
        modelURL: URL(fileURLWithPath: "/tmp/model.bin")
    )
    let englishConfiguration = WhisperConfiguration(
        executableURL: URL(fileURLWithPath: "/tmp/whisper-cli"),
        modelURL: URL(fileURLWithPath: "/tmp/model.bin"),
        language: TranscriptionLanguage.english.rawValue
    )

    #expect(autoConfiguration.usesAutomaticLanguageDetection)
    #expect(!englishConfiguration.usesAutomaticLanguageDetection)
}

@Test func exposesModelOptionsAndExpectedFilenames() {
    #expect(WhisperModelOption.largeV3Turbo.fileName == "ggml-large-v3-turbo.bin")
    #expect(WhisperModelOption.largeV3.fileName == "ggml-large-v3.bin")
    #expect(WhisperModelOption.distilLargeV3.fileName == "ggml-distil-large-v3.bin")
    #expect(WhisperModelOption.mediumEnglish.fileName == "ggml-medium.en.bin")
    #expect(WhisperModelOption.option(forFileName: "ggml-small.en.bin") == .smallEnglish)
}

@Test func appliesLocalDictationCleanup() {
    let cleaner = LocalTranscriptCleaner()

    #expect(cleaner.clean("  um hello   world  ", mode: .dictation) == "Hello world.")
    #expect(cleaner.clean("hello , world", mode: .light) == "hello, world")
    #expect(cleaner.clean("  hello   world  ", mode: .off) == "hello world")
}

@Test func resolvesSelectedModelFromEnvironment() {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("openwhisper-tests-\(UUID().uuidString)")
    let modelsDirectory = temporaryRoot.appendingPathComponent("Models")
    try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    FileManager.default.createFile(
        atPath: temporaryRoot.appendingPathComponent("Package.swift").path,
        contents: Data()
    )
    FileManager.default.createFile(
        atPath: modelsDirectory.appendingPathComponent(WhisperModelOption.distilLargeV3.fileName).path,
        contents: Data()
    )
    defer {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    let configuration = WhisperConfiguration.resolved(
        bundleURL: temporaryRoot,
        currentDirectoryURL: temporaryRoot,
        environment: [
            "OPENWHISPER_LANGUAGE": TranscriptionLanguage.spanish.rawValue,
            "OPENWHISPER_MODEL_OPTION": WhisperModelOption.distilLargeV3.rawValue,
            "OPENWHISPER_QUALITY": TranscriptionQualityProfile.accurate.rawValue,
            "OPENWHISPER_CLEANUP": TranscriptCleanupMode.light.rawValue
        ]
    )

    #expect(configuration.modelURL.lastPathComponent == WhisperModelOption.distilLargeV3.fileName)
    #expect(configuration.language == TranscriptionLanguage.spanish.rawValue)
    #expect(configuration.modelOption == .distilLargeV3)
    #expect(configuration.transcriptionEngine == .whisperKit)
    #expect(configuration.qualityProfile == .accurate)
    #expect(configuration.cleanupMode == .light)
}
