import Foundation

public struct WhisperServerClient: Sendable {
    private let configuration: WhisperConfiguration
    private let serverProcess: WhisperServerProcess
    private let cleaner: TranscriptionOutputCleaner

    public init(
        configuration: WhisperConfiguration,
        serverProcess: WhisperServerProcess,
        cleaner: TranscriptionOutputCleaner = TranscriptionOutputCleaner()
    ) {
        self.configuration = configuration
        self.serverProcess = serverProcess
        self.cleaner = cleaner
    }

    public func warmUp() async throws {
        try await serverProcess.warmUp()
    }

    public func stop() async {
        await serverProcess.stop()
    }

    public func transcribe(wavURL: URL) async throws -> String {
        _ = try await serverProcess.ensureReady()

        let boundary = "OpenWhisper-\(UUID().uuidString)"
        var request = URLRequest(url: configuration.serverInferenceURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try multipartBody(
            boundary: boundary,
            wavURL: wavURL
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw TranscriptionError.serverUnavailable(message)
        }

        return cleaner.clean(String(data: data, encoding: .utf8) ?? "")
    }

    private func multipartBody(boundary: String, wavURL: URL) throws -> Data {
        var body = Data()

        appendField(name: "response_format", value: "text", boundary: boundary, to: &body)
        appendField(name: "temperature", value: "0.0", boundary: boundary, to: &body)
        appendField(name: "temperature_inc", value: "0.0", boundary: boundary, to: &body)
        appendField(name: "best_of", value: "1", boundary: boundary, to: &body)
        appendField(name: "beam_size", value: "1", boundary: boundary, to: &body)
        appendField(name: "audio_ctx", value: "\(configuration.audioContext)", boundary: boundary, to: &body)
        appendField(name: "no_timestamps", value: "true", boundary: boundary, to: &body)
        appendField(name: "language", value: configuration.language, boundary: boundary, to: &body)

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(try Data(contentsOf: wavURL))
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        return body
    }

    private func appendField(
        name: String,
        value: String,
        boundary: String,
        to body: inout Data
    ) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
