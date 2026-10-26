import AVFoundation
import Foundation
import Testing
@testable import OpenWhisperCore

/// These send synthesized speech to Deepgram with the key from OPENWHISPER_DEEPGRAM_API_KEY or the keychain,
/// so they run only with OPENWHISPER_RUN_DEEPGRAM_INTEGRATION=1.
@Suite struct DeepgramIntegrationTests {
    static let vocabulary = """
    DeepSeek, Kimi, Qwen, Claude Code, Anthropic, OpenAI, xAI, Grok, Grokex, Codex, GLM, AdamW, Muon, \
    RoPE, YaRN, mHC, MLA, MoE, RMSNorm, FineWeb, RunPod, Kaggle, H100, PyTorch, Andrej Karpathy, \
    Vercel, Next.js, GitHub, Paseo, OpenWhisper.
    """

    static let dictations = [
        SpokenFixture(
            voice: "Paulina",
            rate: 165,
            text: """
            Para esta, no valdría algo como... [[slnc 1800]] menos uno, cero, uno. [[slnc 1200]] Menos dos, \
            cero, dos. [[slnc 1200]] Menos uno, cero, uno. [[slnc 2500]] Porque así detectamos los bordes \
            verticales, ¿no? [[slnc 2000]] Y para los horizontales sería la traspuesta: menos uno, menos dos, \
            menos uno. Cero, cero, cero. Uno, dos, uno. [[slnc 2200]] ¿Eso es lo que nos piden en el \
            ejercicio, o lo he entendido mal?
            """,
            expectedPhrases: ["no valdría algo como", "bordes verticales", "menos 1, menos 2, menos 1", "lo he entendido mal"]
        ),
        SpokenFixture(
            voice: "Paulina",
            rate: 140,
            text: """
            Para esta no valdría algo como [[slnc 2500]] 0, menos 1, 0, menos 1, 4, menos 1, 0, menos 1, 0, \
            [[slnc 3000]] y la de media sería 1, 1, 1, 1, 1, 1, 1, 1, 1, dividido entre 9, [[slnc 2500]] o la de \
            Sobel, menos 1, 0, 1, menos 2, 0, 2, menos 1, 0, 1, [[slnc 2000]] y su traspuesta menos 1, menos 2, \
            menos 1, 0, 0, 0, 1, 2, 1.
            """,
            expectedPhrases: ["no valdría algo como", "la de media sería", "dividido entre 9", "sobel", "y su traspuesta"]
        ),
        SpokenFixture(
            voice: "Eddy (Spanish (Spain))",
            rate: 220,
            text: """
            Quiero contarte cómo fue el nuevo entrenamiento, porque hubo varias sorpresas que vale la pena \
            apuntar antes de que se me olviden. Primero, el calentamiento de la tasa de aprendizaje era demasiado \
            corto, así que la pérdida se disparó durante los primeros mil pasos y tuvimos que reiniciar desde el \
            último punto de control. Segundo, el cargador de datos leía el mismo fragmento dos veces, lo que hacía \
            que las métricas de validación parecieran mejores de lo que realmente eran. Lo último que quiero \
            mencionar es que el panel por fin vuelve a funcionar.
            """,
            expectedPhrases: ["quiero contarte", "cargador de datos", "vuelve a funcionar"]
        ),
        SpokenFixture(
            voice: "Samantha",
            rate: 230,
            text: """
            I want to explain how the new training run went, because there were a few surprises worth writing \
            down before I forget them. First, the learning rate warmup was too short, so the loss spiked during \
            the first thousand steps and we had to restart from the last checkpoint. Second, the data loader was \
            reading the same shard twice. Next week we will try a larger batch size. Finally, remember that the \
            orange giraffe report is due on Friday.
            """,
            expectedPhrases: ["i want to explain", "data loader", "batch size", "orange giraffe"]
        )
    ]

    static let shortDictations = [
        SpokenFixture(voice: "Paulina", rate: 175, text: "Vale, súbelo a GitHub.", expectedPhrases: ["súbelo a github"]),
        SpokenFixture(voice: "Paulina", rate: 175, text: "Hazlo con PyTorch.", expectedPhrases: ["hazlo con pytorch"]),
        SpokenFixture(voice: "Paulina", rate: 175, text: "Mañana lo comparo con DeepSeek.", expectedPhrases: ["deepseek"]),
        SpokenFixture(voice: "Paulina", rate: 175, text: "Sí, perfecto.", expectedPhrases: ["perfecto"]),
        SpokenFixture(voice: "Samantha", rate: 200, text: "Ship it to Vercel.", expectedPhrases: ["ship it to vercel"]),
        SpokenFixture(voice: "Samantha", rate: 200, text: "Ask Claude Code to fix it.", expectedPhrases: ["claude code"]),
        SpokenFixture(voice: "Samantha", rate: 200, text: "Merge it.", expectedPhrases: ["merge it"])
    ]

    /// Deepgram's newest multilingual model turned "Vale, súbelo a GitHub." into Arabic script. These start
    /// and stop right on their words, as when recording starts late or stops as the last word ends.
    @Test(arguments: shortDictations)
    func keepsShortDictationsInTheirLanguage(fixture: SpokenFixture) async throws {
        guard let apiKey = Self.apiKey() else { return }

        let recording = try await Self.concatenate([fixture], pause: 0, trimmingEnds: true)
        defer { try? FileManager.default.removeItem(at: recording) }

        let outcome = try await Self.transcriber(apiKey: apiKey).transcribe(wavURL: recording)

        Self.expect(outcome.text, contains: fixture.expectedPhrases)
        #expect(
            outcome.text.unicodeScalars.allSatisfy { $0.isASCII || CharacterSet.latinLetters.contains($0) || !CharacterSet.letters.contains($0) },
            "Not in Latin script: \(outcome.text)"
        )
    }

    @Test(arguments: dictations)
    func keepsEveryPartOfADictation(fixture: SpokenFixture) async throws {
        guard let apiKey = Self.apiKey() else { return }

        let recording = try await fixture.synthesize()
        defer { try? FileManager.default.removeItem(at: recording) }

        let outcome = try await Self.transcriber(apiKey: apiKey).transcribe(wavURL: recording)

        #expect(outcome.deepgramFailure == nil)
        Self.expect(outcome.text, contains: fixture.expectedPhrases)
    }

    /// Whisper translated an English sentence inside Spanish dictation into Spanish.
    @Test func followsSwitchesBetweenSpanishAndEnglish() async throws {
        guard let apiKey = Self.apiKey() else { return }

        let recording = try await Self.concatenate([
            SpokenFixture(voice: "Paulina", rate: 175, text: "Vale, entonces le he pedido a Claude Code que", expectedPhrases: []),
            SpokenFixture(voice: "Samantha", rate: 190, text: "refactor the data loader.", expectedPhrases: []),
            SpokenFixture(
                voice: "Paulina",
                rate: 175,
                text: "Y luego he subido el cambio a GitHub, pero el deploy en Vercel falla.",
                expectedPhrases: []
            ),
            SpokenFixture(voice: "Samantha", rate: 190, text: "Can you check the build logs?", expectedPhrases: []),
            SpokenFixture(voice: "Paulina", rate: 175, text: "Mañana lo comparo con Kimi.", expectedPhrases: [])
        ], pause: 0.15, trimmingEnds: true)
        defer { try? FileManager.default.removeItem(at: recording) }

        let outcome = try await Self.transcriber(apiKey: apiKey).transcribe(wavURL: recording)

        Self.expect(outcome.text, contains: [
            "claude code", "refactor the data loader", "github", "vercel", "can you check the build logs", "kimi"
        ])
    }

    /// A dictation of several minutes took WhisperKit over a minute on an M4.
    @Test func transcribesALongDictationInSeconds() async throws {
        guard let apiKey = Self.apiKey() else { return }

        let recording = try await Self.concatenate(Self.dictations + Self.dictations, pause: 1.5)
        defer { try? FileManager.default.removeItem(at: recording) }

        let start = Date()
        let outcome = try await Self.transcriber(apiKey: apiKey).transcribe(wavURL: recording)
        let seconds = Date().timeIntervalSince(start)

        #expect(outcome.deepgramFailure == nil)
        #expect(seconds < 30, "Took \(seconds) s")
        Self.expect(outcome.text, contains: Self.dictations.flatMap(\.expectedPhrases))
        #expect(outcome.text.lowercased().components(separatedBy: "orange giraffe").count == 3)
    }

    /// Deepgram rejects a request whose keyterms run over its limit, instead of ignoring the extra ones.
    @Test func acceptsTheLongestVocabularyThatFits() async throws {
        guard let apiKey = Self.apiKey() else { return }

        let recording = try await Self.dictations[3].synthesize()
        defer { try? FileManager.default.removeItem(at: recording) }

        let vocabulary = Self.vocabulary + ", " + (0..<300).map { "Term\($0)" }.joined(separator: ", ")
        let transcript = try await DeepgramTranscriber(apiKey: apiKey, language: "auto", vocabulary: vocabulary)
            .transcribe(wavURL: recording)

        Self.expect(transcript, contains: ["orange giraffe"])
    }

    @Test func fallsBackToThisMacWhenDeepgramRejectsTheKey() async throws {
        guard Self.apiKey() != nil,
              ProcessInfo.processInfo.environment["OPENWHISPER_RUN_WHISPERKIT_INTEGRATION"] == "1"
        else {
            return
        }

        let recording = try await Self.dictations[3].synthesize()
        defer { try? FileManager.default.removeItem(at: recording) }

        let outcome = try await Self.transcriber(apiKey: String(repeating: "0", count: 40)).transcribe(wavURL: recording)

        #expect(outcome.deepgramFailure == .rejectedKey("Invalid credentials."))
        Self.expect(outcome.text, contains: ["data loader", "orange giraffe"])
    }

    @Test func checksTheKey() async throws {
        guard let apiKey = Self.apiKey() else { return }

        try await DeepgramTranscriber(apiKey: apiKey, language: "auto", vocabulary: "").validateKey()
        await #expect(throws: DeepgramError.rejectedKey("Invalid credentials.")) {
            try await DeepgramTranscriber(apiKey: String(repeating: "0", count: 40), language: "auto", vocabulary: "")
                .validateKey()
        }
    }

    private static func apiKey() -> String? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENWHISPER_RUN_DEEPGRAM_INTEGRATION"] == "1" else { return nil }

        return environment["OPENWHISPER_DEEPGRAM_API_KEY"] ?? DeepgramAPIKeyStore.standard.read()
    }

    private static func transcriber(apiKey: String) -> WhisperTranscriber {
        WhisperTranscriber(configuration: WhisperConfiguration(
            executableURL: URL(fileURLWithPath: "/tmp/whisper-cli"),
            modelURL: URL(fileURLWithPath: "/tmp/whisper-model.bin"),
            transcriptionEngine: .deepgram,
            initialPrompt: vocabulary,
            deepgramAPIKey: apiKey
        ))
    }

    private static func expect(_ transcript: String, contains phrases: [String]) {
        for phrase in phrases {
            #expect(transcript.lowercased().contains(phrase), "Missing \"\(phrase)\" in: \(transcript)")
        }
    }

    /// One recording of the fixtures spoken one after another, written like AudioRecorder writes it.
    /// `trimmingEnds` takes away the silence `say` leaves before and after the speech.
    private static func concatenate(
        _ fixtures: [SpokenFixture],
        pause: TimeInterval,
        trimmingEnds: Bool = false
    ) async throws -> URL {
        var samples: [Int16] = []
        for (index, fixture) in fixtures.enumerated() {
            let part = try await fixture.synthesize()
            defer { try? FileManager.default.removeItem(at: part) }

            let file = try AVAudioFile(forReading: part, commonFormat: .pcmFormatInt16, interleaved: true)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            samples += UnsafeBufferPointer(start: buffer.int16ChannelData![0], count: Int(buffer.frameLength))
            if index < fixtures.count - 1 || !trimmingEnds {
                samples += [Int16](repeating: 0, count: Int(pause * 16_000))
            }
        }

        if trimmingEnds {
            let isSpeech = { (sample: Int16) in abs(Int(sample)) >= 200 }
            let first = samples.firstIndex(where: isSpeech) ?? 0
            let last = samples.lastIndex(where: isSpeech) ?? samples.count - 1
            samples = Array(samples[first...last])
        }
        return try writeRecording(samples)
    }
}

private extension CharacterSet {
    /// Letters with accents, such as á and ñ, and the rest of Latin-1.
    static let latinLetters = CharacterSet(charactersIn: Unicode.Scalar(0xC0)!...Unicode.Scalar(0x24F)!)
}
