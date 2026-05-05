import AVFoundation
import Foundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    func start(levelHandler: ((Float) -> Void)? = nil) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecordingError.microphonePermissionRequired
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openwhisper-\(UUID().uuidString).caf")

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        audioFile = file
        recordingURL = url

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            do {
                try file.write(from: buffer)
            } catch {
                NSLog("OpenWhisper audio write failed: \(error.localizedDescription)")
            }

            if let levelHandler {
                levelHandler(Self.normalizedLevel(from: buffer))
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() throws -> URL {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil

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

enum RecordingError: Error, LocalizedError {
    case microphonePermissionRequired
    case noRecording

    var errorDescription: String? {
        switch self {
        case .microphonePermissionRequired:
            return "Microphone permission is required before recording."
        case .noRecording:
            return "No recording is available."
        }
    }
}
