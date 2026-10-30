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
    #expect(cleaner.clean("o lo he entendido mal,", mode: .dictation) == "O lo he entendido mal.")
    #expect(cleaner.clean("menos 1, 0, 1;", mode: .dictation) == "Menos 1, 0, 1.")
}

@Test func dictationCleanupKeepsURLsAndAbbreviationsIntact() {
    let cleaner = LocalTranscriptCleaner()

    #expect(cleaner.clean("check developer.apple.com for it", mode: .dictation) == "Check developer.apple.com for it.")
    #expect(cleaner.clean("use e.g. the README.md file", mode: .dictation) == "Use e.g. the README.md file.")
    #expect(cleaner.clean("Ah, vale. Um, entendido", mode: .dictation) == "Ah, vale. Entendido.")
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
        ],
        storedAPIKeys: [:]
    )

    #expect(configuration.modelURL.lastPathComponent == WhisperModelOption.distilLargeV3.fileName)
    #expect(configuration.language == TranscriptionLanguage.spanish.rawValue)
    #expect(configuration.modelOption == .distilLargeV3)
    #expect(configuration.transcriptionEngine == .whisperKit)
    #expect(configuration.qualityProfile == .accurate)
    #expect(configuration.cleanupMode == .light)
}

@Test func usesTheMostAccurateServiceWithAKey() {
    func engine(_ chosen: TranscriptionEngine?, _ servicesWithKeys: Set<CloudService>) -> TranscriptionEngine {
        WhisperConfiguration.engine(chosen: chosen, servicesWithKeys: servicesWithKeys)
    }

    #expect(engine(nil, [.openAI, .deepgram]) == .openAI)
    #expect(engine(nil, [.deepgram]) == .deepgram)
    #expect(engine(nil, []) == .whisperKit)
    #expect(engine(.deepgram, [.openAI, .deepgram]) == .deepgram)
    #expect(engine(.deepgram, [.openAI]) == .openAI)
    #expect(engine(.openAI, [.deepgram]) == .deepgram)
    #expect(engine(.openAI, []) == .whisperKit)
    #expect(engine(.whisperKit, [.openAI]) == .whisperKit)
    #expect(engine(.whisperCpp, [.deepgram]) == .whisperCpp)
}

@Test func triesTheChosenServiceBeforeTheOthers() {
    func cloudServices(_ engine: TranscriptionEngine, _ apiKeys: [CloudService: String]) -> [CloudService] {
        WhisperConfiguration(
            executableURL: URL(fileURLWithPath: "/tmp/whisper-cli"),
            modelURL: URL(fileURLWithPath: "/tmp/model.bin"),
            transcriptionEngine: engine,
            apiKeys: apiKeys
        ).cloudServices
    }

    #expect(cloudServices(.openAI, [.openAI: "a", .deepgram: "d"]) == [.openAI, .deepgram])
    #expect(cloudServices(.deepgram, [.openAI: "a", .deepgram: "d"]) == [.deepgram, .openAI])
    #expect(cloudServices(.openAI, [.openAI: "a"]) == [.openAI])
    #expect(cloudServices(.whisperKit, [.openAI: "a", .deepgram: "d"]).isEmpty)
}

@Test func prefersAPIKeysFromTheEnvironment() {
    func resolved(environment: [String: String], storedKeys: [CloudService: String]) -> WhisperConfiguration {
        WhisperConfiguration.resolved(
            bundleURL: URL(fileURLWithPath: "/Applications/OpenWhisper.app"),
            environment: environment,
            storedAPIKeys: storedKeys
        )
    }

    let stored = resolved(environment: [:], storedKeys: [.openAI: "openai", .deepgram: "deepgram"])
    let overridden = resolved(environment: ["OPENWHISPER_DEEPGRAM_API_KEY": " environment "], storedKeys: [.deepgram: "stored"])
    let openAIFromEnvironment = resolved(environment: ["OPENWHISPER_OPENAI_API_KEY": "environment"], storedKeys: [:])
    let blank = resolved(environment: ["OPENWHISPER_DEEPGRAM_API_KEY": ""], storedKeys: [.deepgram: "  "])
    let local = resolved(environment: ["OPENWHISPER_ENGINE": "whisperKit"], storedKeys: [.deepgram: "stored"])

    #expect(stored.apiKeys == [.openAI: "openai", .deepgram: "deepgram"])
    #expect(overridden.apiKeys == [.deepgram: "environment"])
    #expect(openAIFromEnvironment.apiKeys == [.openAI: "environment"])
    #expect(blank.apiKeys.isEmpty)
    #expect(local.transcriptionEngine == .whisperKit)
    #expect(local.apiKeys == [.deepgram: "stored"])
}

@Test func recordsFromTheBuiltInMicrophoneUnlessTheLidIsClosed() {
    let airPods = AudioInputDeviceInfo(id: 104, transport: .other)
    let builtIn = AudioInputDeviceInfo(id: 78, transport: .builtIn)
    let usb = AudioInputDeviceInfo(id: 90, transport: .other)

    #expect(MicrophoneSelection.preferredInputDeviceID(availableInputs: [airPods, builtIn, usb], isLidClosed: false) == 78)
    #expect(MicrophoneSelection.preferredInputDeviceID(availableInputs: [airPods, builtIn, usb], isLidClosed: true) == nil)
    #expect(MicrophoneSelection.preferredInputDeviceID(availableInputs: [airPods, usb], isLidClosed: false) == nil)
}
