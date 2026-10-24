import Foundation
import Testing
@testable import OpenWhisperCore

@Test func transcribesWhisperKitAudioFixtureWhenEnabled() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["OPENWHISPER_RUN_WHISPERKIT_INTEGRATION"] == "1" else {
        return
    }

    guard let audioPath = environment["OPENWHISPER_TEST_AUDIO"], !audioPath.isEmpty else {
        Issue.record("Set OPENWHISPER_TEST_AUDIO to a local WAV fixture.")
        return
    }

    let configuration = WhisperConfiguration(
        executableURL: URL(fileURLWithPath: "/tmp/whisper-cli"),
        modelURL: URL(fileURLWithPath: "/tmp/whisper-model.bin"),
        language: "en",
        transcriptionEngine: .whisperKit,
        qualityProfile: .balanced,
        cleanupMode: .off,
        whisperKitModelDirectory: URL(
            fileURLWithPath: environment["OPENWHISPER_WHISPERKIT_MODEL_DIR"]
                ?? WhisperConfiguration.defaultWhisperKitModelDirectory.path
        )
    )
    let transcriber = WhisperKitTranscriber(configuration: configuration)
    let transcript = try await transcriber.transcribe(wavURL: URL(fileURLWithPath: audioPath))
        .lowercased()

    #expect(transcript.contains("openwhisper"))
    #expect(transcript.contains("local transcription"))
}

/// Whisper writes at most 224 tokens per 30-second window, and the vocabulary prompt counts against them.
/// Fast speech under a long prompt used to run out, and everything after that point was dropped.
@Test(arguments: [
    SpokenFixture(
        voice: "Samantha",
        rate: 230,
        text: """
        I want to explain how the new training run went, because there were a few surprises worth writing \
        down before I forget them. First, the learning rate warmup was too short, so the loss spiked during \
        the first thousand steps and we had to restart from the last checkpoint. Second, the data loader was \
        reading the same shard twice, which made the validation numbers look better than they really were. \
        Third, after fixing both problems, the model finally converged and the evaluation scores improved \
        across every benchmark we track. The last thing I want to mention is that the purple elephant \
        dashboard is finally working again.
        """,
        expectedPhrases: ["training run", "data loader", "purple elephant"]
    ),
    SpokenFixture(
        voice: "Eddy (Spanish (Spain))",
        rate: 220,
        text: """
        Quiero contarte cómo fue el nuevo entrenamiento, porque hubo varias sorpresas que vale la pena \
        apuntar antes de que se me olviden. Primero, el calentamiento de la tasa de aprendizaje era demasiado \
        corto, así que la pérdida se disparó durante los primeros mil pasos y tuvimos que reiniciar desde el \
        último punto de control. Segundo, el cargador de datos leía el mismo fragmento dos veces, lo que hacía \
        que las métricas de validación parecieran mejores de lo que realmente eran. Tercero, después de \
        arreglar los dos problemas, el modelo por fin convergió y las puntuaciones mejoraron en todas las \
        pruebas que seguimos. Lo último que quiero mencionar es que el panel del elefante morado por fin \
        vuelve a funcionar.
        """,
        expectedPhrases: ["entrenamiento", "cargador de datos", "parecieran mejores", "elefante morado"]
    ),
    SpokenFixture(
        voice: "Samantha",
        rate: 230,
        text: """
        I want to explain how the new training run went, because there were a few surprises worth writing \
        down before I forget them. First, the learning rate warmup was too short, so the loss spiked during \
        the first thousand steps and we had to restart from the last checkpoint. Second, the data loader was \
        reading the same shard twice, which made the validation numbers look better than they really were. \
        Third, after fixing both problems, the model finally converged and the evaluation scores improved \
        across every benchmark we track. Next week we will try a larger batch size, a cosine schedule with \
        a longer warmup, and a cleaner mix of code and math data. If the loss curve looks healthy after two \
        days, we will scale the run up to the full cluster and keep an eye on the gradient norm, which \
        tended to drift upward near the end of the previous attempt. Finally, remember that the orange \
        giraffe report is due on Friday.
        """,
        expectedPhrases: ["training run", "data loader", "batch size", "gradient norm", "orange giraffe"]
    )
])
func keepsTheEndOfFastDictationUnderALongVocabularyPrompt(fixture: SpokenFixture) async throws {
    try await expectTranscriptUnderALongVocabularyPrompt(of: fixture)
}

/// Whisper leaves out the start of a window that begins in the middle of a sentence, and it retried windows
/// of dictated numbers at random temperatures until their text came out short or in another language.
@Test(arguments: [
    SpokenFixture(
        voice: "Paulina",
        rate: 165,
        text: """
        Para esta, no valdría algo como... [[slnc 1800]] menos uno, cero, uno. [[slnc 1200]] Menos dos, cero, \
        dos. [[slnc 1200]] Menos uno, cero, uno. [[slnc 2500]] Porque así detectamos los bordes verticales, \
        ¿no? [[slnc 2000]] Y para los horizontales sería la traspuesta: menos uno, menos dos, menos uno. \
        Cero, cero, cero. Uno, dos, uno. [[slnc 2200]] ¿Eso es lo que nos piden en el ejercicio, o lo he \
        entendido mal?
        """,
        expectedPhrases: ["bordes verticales", "menos 1, menos 2, menos 1", "lo he entendido mal"]
    ),
    SpokenFixture(
        voice: "Paulina",
        rate: 175,
        text: """
        Invariante a desplazamientos de la imagen creo que no porque si por ejemplo movemos la imagen a la \
        izquierda la correlación también se va a mover a la izquierda. [[slnc 1300]] Variante a la rotación, \
        creo que tampoco, porque si rotamos la imagen entonces va a cambiar. [[slnc 1300]] Invariante a \
        cambios de iluminación en la imagen. [[slnc 1300]] Creo que tampoco porque por el ejemplo de antes si \
        multiplicamos todo por dos el resultado también se va a multiplicar por dos. [[slnc 1300]] \
        ¿Invariante a cambio de iluminación en el patrón? [[slnc 1300]] Creo que tampoco porque si. \
        [[slnc 1300]] Multiplicamos el patrón por 2, también va a multiplicarse por 2 el resultado. \
        [[slnc 1300]] De todas estas lo que más me suena es invariante a desplazamientos de la imagen, pero \
        creo que también se desplazaría el patrón.
        """,
        expectedPhrases: ["rotamos la imagen", "el resultado también se va a multiplicar", "desplazaría el patrón"]
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
        expectedPhrases: ["la de media sería", "dividido entre 9", "sobel", "0, 0, 0, 1, 2, 1"]
    )
])
func keepsEveryWindowOfADictationUnderALongVocabularyPrompt(fixture: SpokenFixture) async throws {
    try await expectTranscriptUnderALongVocabularyPrompt(of: fixture)
}

private func expectTranscriptUnderALongVocabularyPrompt(of fixture: SpokenFixture) async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["OPENWHISPER_RUN_WHISPERKIT_INTEGRATION"] == "1" else {
        return
    }

    let audioURL = try await fixture.synthesize()
    defer { try? FileManager.default.removeItem(at: audioURL) }

    let configuration = WhisperConfiguration(
        executableURL: URL(fileURLWithPath: "/tmp/whisper-cli"),
        modelURL: URL(fileURLWithPath: "/tmp/whisper-model.bin"),
        transcriptionEngine: .whisperKit,
        qualityProfile: .balanced,
        cleanupMode: .off,
        // About 107 tokens, which leaves a 30-second window about 111 for the transcript.
        initialPrompt: """
        DeepSeek, Kimi, Qwen, Claude Code, Anthropic, OpenAI, xAI, Grok, Grokex, Codex, GLM, AdamW, Muon, \
        RoPE, YaRN, mHC, MLA, MoE, RMSNorm, FineWeb, RunPod, Kaggle, H100, PyTorch, Andrej Karpathy, \
        Vercel, Next.js, GitHub, Paseo, OpenWhisper.
        """,
        whisperKitModelDirectory: URL(
            fileURLWithPath: environment["OPENWHISPER_WHISPERKIT_MODEL_DIR"]
                ?? WhisperConfiguration.defaultWhisperKitModelDirectory.path
        )
    )
    let transcript = try await WhisperKitTranscriber(configuration: configuration)
        .transcribe(wavURL: audioURL)
        .lowercased()

    for phrase in fixture.expectedPhrases {
        #expect(transcript.contains(phrase), "Missing \"\(phrase)\" in: \(transcript)")
    }
}

enum FixtureError: Error {
    case missingVoice(String)
}

struct SpokenFixture: Sendable, CustomTestStringConvertible {
    let voice: String
    let rate: Int
    let text: String
    let expectedPhrases: [String]

    var testDescription: String { "\(voice), ending \"\(expectedPhrases.last ?? "")\"" }

    /// Speaks the text with macOS text to speech into a 16 kHz mono WAV, like the ones AudioRecorder writes.
    ///
    /// `say` reads with the default voice when it does not find the one named, which turns Spanish into
    /// English gibberish. It does not find names with accents, such as Mónica, when they come from Swift.
    func synthesize() async throws -> URL {
        let voices = try await Shell.run(executableURL: URL(fileURLWithPath: "/usr/bin/say"), arguments: ["-v", "?"])
        guard voices.stdout.split(separator: "\n").contains(where: { $0.hasPrefix(voice + " ") }) else {
            throw FixtureError.missingVoice(voice)
        }

        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("openwhisper-test-\(UUID().uuidString)")
        let speechURL = base.appendingPathExtension("aiff")
        let wavURL = base.appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: speechURL) }

        _ = try await Shell.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/say"),
            arguments: ["-v", voice, "-r", String(rate), "-o", speechURL.path, text]
        )
        _ = try await Shell.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/afconvert"),
            arguments: ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", speechURL.path, wavURL.path]
        )
        return wavURL
    }
}
