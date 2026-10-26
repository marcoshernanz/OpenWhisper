import Foundation

/// A recording as AudioRecorder writes it: a 44-byte header and 16 kHz mono 16-bit samples.
func writeRecording(_ samples: [Int16]) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("openwhisper-test-\(UUID().uuidString).wav")
    try wav(samples).write(to: url)
    return url
}

func wav(_ samples: [Int16], extraChunk: Data = Data()) -> Data {
    let data = pcm(samples)
    var wav = Data("RIFF".utf8)
    wav.append(littleEndian: UInt32(4 + 24 + extraChunk.count + 8 + data.count))
    wav.append(Data("WAVEfmt ".utf8))
    wav.append(littleEndian: UInt32(16))
    wav.append(littleEndian: UInt16(1))
    wav.append(littleEndian: UInt16(1))
    wav.append(littleEndian: UInt32(16_000))
    wav.append(littleEndian: UInt32(32_000))
    wav.append(littleEndian: UInt16(2))
    wav.append(littleEndian: UInt16(16))
    wav.append(extraChunk)
    wav.append(Data("data".utf8))
    wav.append(littleEndian: UInt32(data.count))
    wav.append(data)
    return wav
}

func pcm(_ samples: [Int16]) -> Data {
    var data = Data()
    for sample in samples {
        data.append(littleEndian: UInt16(bitPattern: sample))
    }
    return data
}

extension Data {
    mutating func append<Integer: FixedWidthInteger>(littleEndian value: Integer) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

/// Answers each request with the next reply, and keeps the requests with their bodies. Each service's tests
/// have their own subclass, because suites run at the same time.
class HTTPStub: URLProtocol, @unchecked Sendable {
    enum Reply {
        case status(Int, String)
        case failure(URLError.Code)

        /// What Deepgram sends back.
        static func transcript(_ text: String) -> Reply {
            let alternative = ["transcript": text, "confidence": 0.9] as [String: Any]
            let response = ["results": ["channels": [["alternatives": [alternative]]]]]
            let body = try! JSONSerialization.data(withJSONObject: response)
            return .status(200, String(data: body, encoding: .utf8)!)
        }

        /// What OpenAI sends back.
        static func text(_ text: String) -> Reply {
            let response = ["text": text, "languages": [["code": "en"]]] as [String: Any]
            let body = try! JSONSerialization.data(withJSONObject: response)
            return .status(200, String(data: body, encoding: .utf8)!)
        }
    }

    final class Exchange: @unchecked Sendable {
        private let lock = NSLock()
        private var pendingReplies: [Reply] = []
        private var receivedRequests: [(URLRequest, Data)] = []

        var requests: [(URLRequest, Data)] {
            lock.withLock { receivedRequests }
        }

        func reset(replies: [Reply]) {
            lock.withLock {
                pendingReplies = replies
                receivedRequests = []
            }
        }

        func reply(to request: URLRequest, body: Data) -> Reply {
            lock.withLock {
                receivedRequests.append((request, body))
                return pendingReplies.isEmpty ? Reply.status(500, "no reply") : pendingReplies.removeFirst()
            }
        }
    }

    class var exchange: Exchange {
        fatalError("Use a subclass of HTTPStub")
    }

    static var requests: [(URLRequest, Data)] {
        exchange.requests
    }

    static func reset(replies: [Reply]) {
        exchange.reset(replies: replies)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()

        switch type(of: self).exchange.reply(to: request, body: body) {
        case .status(let statusCode, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [self]
        return URLSession(configuration: configuration)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class DeepgramStub: HTTPStub, @unchecked Sendable {
    private static let deepgramExchange = Exchange()

    override class var exchange: Exchange { deepgramExchange }
}

final class OpenAIStub: HTTPStub, @unchecked Sendable {
    private static let openAIExchange = Exchange()

    override class var exchange: Exchange { openAIExchange }
}
