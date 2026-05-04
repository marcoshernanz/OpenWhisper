import AVFoundation
import Foundation

@MainActor
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    func start() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecordingError.microphonePermissionRequired
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openwhisper-\(UUID().uuidString).caf")

        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        recordingURL = url

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let audioFile = self?.audioFile else { return }
            do {
                try audioFile.write(from: buffer)
            } catch {
                NSLog("OpenWhisper audio write failed: \(error.localizedDescription)")
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
