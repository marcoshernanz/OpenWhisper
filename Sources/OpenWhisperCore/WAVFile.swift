import Foundation

/// The 16 kHz mono 16-bit WAV files that AudioRecorder writes.
public enum WAVFile {
    static let bytesPerSecond = Int(WhisperPCMResampler.outputSampleRate) * 2

    public static func header(dataByteCount: UInt32) -> Data {
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

    static func silence(_ seconds: TimeInterval) -> Data {
        let samples = Data(count: Int(seconds * Double(bytesPerSecond)))
        return header(dataByteCount: UInt32(samples.count)) + samples
    }

    /// The same recording with `seconds` of silence before and after it, or nil when it is not a 16-bit PCM
    /// WAV file.
    static func paddingWithSilence(_ seconds: TimeInterval, around wav: Data) -> Data? {
        let wav = Data(wav)
        guard wav.count >= 12,
              wav[0..<4] == Data("RIFF".utf8),
              wav[8..<12] == Data("WAVE".utf8)
        else {
            return nil
        }

        var format: (channels: Int, sampleRate: Int, bitsPerSample: Int)?
        var offset = 12

        while offset + 8 <= wav.count {
            let chunkID = wav[offset..<(offset + 4)]
            let chunkSize = Int(wav.littleEndianUInt32(at: offset + 4))
            let bodyStart = offset + 8

            if chunkID == Data("fmt ".utf8), bodyStart + 16 <= wav.count {
                guard wav.littleEndianUInt16(at: bodyStart) == 1 else { return nil }
                format = (
                    Int(wav.littleEndianUInt16(at: bodyStart + 2)),
                    Int(wav.littleEndianUInt32(at: bodyStart + 4)),
                    Int(wav.littleEndianUInt16(at: bodyStart + 14))
                )
            } else if chunkID == Data("data".utf8), let format, format.bitsPerSample == 16 {
                let silence = Data(count: Int(seconds * Double(format.sampleRate)) * format.channels * 2)
                // A recording cut short says it holds more than it does.
                let samplesEnd = min(bodyStart + chunkSize, wav.count)

                var padded = Data(wav[0..<bodyStart])
                padded.append(silence)
                padded.append(wav[bodyStart..<samplesEnd])
                padded.append(silence)
                padded.append(wav[samplesEnd...])
                padded.setLittleEndianUInt32(UInt32(samplesEnd - bodyStart + 2 * silence.count), at: offset + 4)
                padded.setLittleEndianUInt32(UInt32(padded.count - 8), at: 4)
                return padded
            }

            // Chunks are padded to an even length.
            offset = bodyStart + chunkSize + chunkSize % 2
        }

        return nil
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

    func littleEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func littleEndianUInt32(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[offset + $1]) << (8 * $1) }
    }

    mutating func setLittleEndianUInt32(_ value: UInt32, at offset: Int) {
        for byte in 0..<4 {
            self[offset + byte] = UInt8(truncatingIfNeeded: value >> (8 * byte))
        }
    }
}
