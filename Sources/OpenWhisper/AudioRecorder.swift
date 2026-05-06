@preconcurrency import AVFoundation
import Foundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var wavWriter: WhisperWavFileWriter?
    private var recordingURL: URL?

    func start(levelHandler: ((Float) -> Void)? = nil) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecordingError.microphonePermissionRequired
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openwhisper-\(UUID().uuidString).wav")
        let writer = try WhisperWavFileWriter(
            url: url,
            sourceSampleRate: format.sampleRate
        )

        wavWriter = writer
        recordingURL = url

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            writer.append(buffer)

            if let levelHandler {
                levelHandler(Self.normalizedLevel(from: buffer))
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            writer.cancel()
            wavWriter = nil
            recordingURL = nil
            throw error
        }
    }

    func stop() throws -> URL {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try wavWriter?.finish()
        wavWriter = nil

        guard let url = recordingURL else {
            throw RecordingError.noRecording
        }

        recordingURL = nil
        return url
    }

    private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Float {
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

private final class WhisperWavFileWriter: @unchecked Sendable {
    private static let outputSampleRate: Double = 16_000

    private let url: URL
    private let fileHandle: FileHandle
    private let writeQueue = DispatchQueue(label: "dev.openwhisper.wav-writer")
    private let sourceSampleRate: Double
    private let resampleStep: Double
    private var pendingInput: [Float] = []
    private var resamplePosition: Double = 0
    private var dataByteCount: UInt32 = 0
    private var isClosed = false

    init(url: URL, sourceSampleRate: Double) throws {
        self.url = url
        self.sourceSampleRate = sourceSampleRate
        self.resampleStep = sourceSampleRate / Self.outputSampleRate

        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: url)
        try fileHandle.write(contentsOf: Self.header(dataByteCount: 0))
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let pcm = makePCMData(from: buffer), !pcm.isEmpty else { return }

        writeQueue.async { [fileHandle] in
            guard !self.isClosed else { return }

            do {
                try fileHandle.write(contentsOf: pcm)
                self.dataByteCount += UInt32(pcm.count)
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

    private func makePCMData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData else {
            NSLog("OpenWhisper received unsupported microphone sample format.")
            return nil
        }

        let channelCount = min(Int(buffer.format.channelCount), 2)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return nil }

        pendingInput.reserveCapacity(pendingInput.count + frameCount)

        for frame in 0..<frameCount {
            var sample: Float = 0

            for channel in 0..<channelCount {
                sample += channelData[channel][frame]
            }

            pendingInput.append(sample / Float(channelCount))
        }

        return resampledPCMData()
    }

    private func resampledPCMData() -> Data {
        var data = Data()
        let expectedOutputFrames = Int(Double(pendingInput.count) / resampleStep) + 1
        data.reserveCapacity(expectedOutputFrames * 2)

        while resamplePosition + 1 < Double(pendingInput.count) {
            let lowerIndex = Int(resamplePosition)
            let fraction = Float(resamplePosition - Double(lowerIndex))
            let lower = pendingInput[lowerIndex]
            let upper = pendingInput[lowerIndex + 1]
            let sample = lower + ((upper - lower) * fraction)
            let clamped = max(-1, min(1, sample))
            let intSample = Int16(clamped * Float(Int16.max))
            data.appendLittleEndian(intSample)
            resamplePosition += resampleStep
        }

        let removableSamples = Int(resamplePosition)
        if removableSamples > 0 {
            pendingInput.removeFirst(removableSamples)
            resamplePosition -= Double(removableSamples)
        }

        return data
    }

    private static func header(dataByteCount: UInt32) -> Data {
        var data = Data()
        let riffByteCount = 36 + dataByteCount

        data.appendASCII("RIFF")
        data.appendLittleEndian(riffByteCount)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(Self.outputSampleRate))
        data.appendLittleEndian(UInt32(Self.outputSampleRate * 2))
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

    mutating func appendLittleEndian(_ value: Int16) {
        var littleEndian = value.littleEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &littleEndian) { Array($0) })
    }
}

enum RecordingError: Error, LocalizedError {
    case microphonePermissionRequired
    case noRecording
    case unsupportedAudioFormat

    var errorDescription: String? {
        switch self {
        case .microphonePermissionRequired:
            return "Microphone permission is required before recording."
        case .noRecording:
            return "No recording is available."
        case .unsupportedAudioFormat:
            return "The microphone audio format could not be converted for local transcription."
        }
    }
}
