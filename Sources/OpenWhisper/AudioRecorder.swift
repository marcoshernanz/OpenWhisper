@preconcurrency import AVFoundation
import Foundation
import OpenWhisperCore

@MainActor
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var engineConfigurationObserver: NSObjectProtocol?
    private var activeRecording: ActiveRecording?

    func start(levelHandler: (@Sendable (Float) -> Void)? = nil) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecordingError.microphonePermissionRequired
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openwhisper-\(UUID().uuidString).wav")
        let writer = try WhisperWavFileWriter(url: url)
        let tapBlock = Self.makeTapBlock(writer: writer, levelHandler: levelHandler)

        do {
            try startCapture(tapBlock: tapBlock)
        } catch {
            writer.cancel()
            throw error
        }

        activeRecording = ActiveRecording(url: url, writer: writer, tapBlock: tapBlock)
    }

    func stop() throws -> URL {
        stopCapture()

        guard let recording = activeRecording else {
            throw RecordingError.noRecording
        }

        activeRecording = nil
        try recording.writer.finish()
        return recording.url
    }

    /// Retries once on a new engine, because an engine that has not caught up with an input change
    /// (such as AirPods connecting) cannot install its tap.
    private func startCapture(tapBlock: @escaping AVAudioNodeTapBlock) throws {
        do {
            try startEngine(tapBlock: tapBlock)
        } catch {
            NSLog("OpenWhisper audio engine failed to start, retrying with a new engine: \(error.localizedDescription)")
            discardEngine()

            do {
                try startEngine(tapBlock: tapBlock)
            } catch {
                discardEngine()
                throw error
            }
        }
    }

    private func startEngine(tapBlock: @escaping AVAudioNodeTapBlock) throws {
        let engine = currentEngine()

        try ObjCException.catching {
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw RecordingError.inputUnavailable
            }

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format, block: tapBlock)
            engine.prepare()
            try engine.start()
        }
    }

    private func stopCapture() {
        guard let engine else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func currentEngine() -> AVAudioEngine {
        if let engine, Self.inputFormatMatchesHardware(engine.inputNode) {
            return engine
        }

        discardEngine()

        let engine = AVAudioEngine()
        let engineID = ObjectIdentifier(engine)
        engineConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.engineConfigurationChanged(engineID: engineID)
            }
        }
        self.engine = engine
        return engine
    }

    private func discardEngine() {
        stopCapture()

        if let engineConfigurationObserver {
            NotificationCenter.default.removeObserver(engineConfigurationObserver)
        }
        engineConfigurationObserver = nil
        engine = nil
    }

    /// AVAudioEngine stops itself when the input device changes, for example when AirPods connect and
    /// become the default input, and then keeps reporting the previous device's format. Replace it,
    /// and keep recording on the new input if dictation is in progress.
    private func engineConfigurationChanged(engineID: ObjectIdentifier) {
        guard let engine, ObjectIdentifier(engine) == engineID else { return }

        discardEngine()

        guard let activeRecording else { return }

        do {
            try startCapture(tapBlock: activeRecording.tapBlock)
            NSLog("OpenWhisper resumed recording after an audio input change.")
        } catch {
            NSLog("OpenWhisper could not resume recording after an audio input change: \(error.localizedDescription)")
        }
    }

    private static func inputFormatMatchesHardware(_ inputNode: AVAudioInputNode) -> Bool {
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        let tapFormat = inputNode.outputFormat(forBus: 0)

        return hardwareFormat.sampleRate == tapFormat.sampleRate
            && hardwareFormat.channelCount == tapFormat.channelCount
    }

    private nonisolated static func makeTapBlock(
        writer: WhisperWavFileWriter,
        levelHandler: (@Sendable (Float) -> Void)?
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            writer.append(buffer)

            if let levelHandler {
                levelHandler(normalizedLevel(from: buffer))
            }
        }
    }

    private nonisolated static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let channelCount = min(Int(buffer.format.channelCount), 2)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return 0 }

        var sum: Float = 0
        var sampleCount = 0
        let sampleStride = max(1, frameCount / 512)

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var frame = 0
            while frame < frameCount {
                let sample = samples[frame]
                sum += sample * sample
                sampleCount += 1
                frame += sampleStride
            }
        }

        guard sampleCount > 0 else { return 0 }

        let rms = sqrt(sum / Float(sampleCount))
        let decibels = 20 * log10(max(rms, 0.000_01))
        let normalized = (decibels + 52) / 44
        return min(1, max(0, normalized))
    }
}

private struct ActiveRecording {
    let url: URL
    let writer: WhisperWavFileWriter
    let tapBlock: AVAudioNodeTapBlock
}

private final class WhisperWavFileWriter: @unchecked Sendable {
    private let url: URL
    private let fileHandle: FileHandle
    private let writeQueue = DispatchQueue(label: "dev.openwhisper.wav-writer")
    private var resampler = WhisperPCMResampler()
    private var dataByteCount: UInt32 = 0
    private var isClosed = false

    init(url: URL) throws {
        self.url = url

        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: url)
        try fileHandle.write(contentsOf: Self.header(dataByteCount: 0))
    }

    /// Called on the audio tap thread. Resampling happens on `writeQueue`, so the tap of an engine
    /// rebuilt after an input change never races the previous engine's tap.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let samples = Self.monoSamples(from: buffer) else { return }
        let sampleRate = buffer.format.sampleRate

        writeQueue.async { [fileHandle] in
            guard !self.isClosed else { return }

            let pcm = self.resampler.resample(samples, sourceSampleRate: sampleRate)
            guard !pcm.isEmpty else { return }

            do {
                let data = pcm.map(\.littleEndian).withUnsafeBufferPointer { Data(buffer: $0) }
                try fileHandle.write(contentsOf: data)
                self.dataByteCount += UInt32(data.count)
            } catch {
                NSLog("OpenWhisper audio write failed: \(error.localizedDescription)")
            }
        }
    }

    func finish() throws {
        var finishError: Error?

        writeQueue.sync {
            guard !isClosed else { return }

            do {
                try fileHandle.seek(toOffset: 0)
                try fileHandle.write(contentsOf: Self.header(dataByteCount: dataByteCount))
                try fileHandle.close()
                isClosed = true
            } catch {
                finishError = error
            }
        }

        if let finishError {
            throw finishError
        }
    }

    func cancel() {
        writeQueue.sync {
            guard !isClosed else { return }

            try? fileHandle.close()
            isClosed = true
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else {
            NSLog("OpenWhisper received unsupported microphone sample format.")
            return nil
        }

        let channelCount = min(Int(buffer.format.channelCount), 2)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return nil }

        var samples = [Float](repeating: 0, count: frameCount)

        for frame in 0..<frameCount {
            var sample: Float = 0

            for channel in 0..<channelCount {
                sample += channelData[channel][frame]
            }

            samples[frame] = sample / Float(channelCount)
        }

        return samples
    }

    private static func header(dataByteCount: UInt32) -> Data {
        let outputSampleRate = WhisperPCMResampler.outputSampleRate
        var data = Data()
        let riffByteCount = 36 + dataByteCount

        data.appendASCII("RIFF")
        data.appendLittleEndian(riffByteCount)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(outputSampleRate))
        data.appendLittleEndian(UInt32(outputSampleRate * 2))
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(dataByteCount)

        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &littleEndian) { Array($0) })
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &littleEndian) { Array($0) })
    }
}

enum RecordingError: Error, LocalizedError {
    case microphonePermissionRequired
    case noRecording
    case inputUnavailable
    case unsupportedAudioFormat

    var errorDescription: String? {
        switch self {
        case .microphonePermissionRequired:
            return "Microphone permission is required before recording."
        case .noRecording:
            return "No recording is available."
        case .inputUnavailable:
            return "No microphone input is available right now. If headphones just connected or disconnected, try again in a moment."
        case .unsupportedAudioFormat:
            return "The microphone audio format could not be converted for local transcription."
        }
    }
}
