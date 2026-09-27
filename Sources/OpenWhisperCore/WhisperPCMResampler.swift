import Foundation

/// Converts mono microphone samples into the 16 kHz, 16-bit PCM Whisper expects.
///
/// The source sample rate can change mid-recording: the built-in microphone runs at 48 kHz, while
/// AirPods connecting as the input switch it to their 24 kHz headset microphone.
public struct WhisperPCMResampler: Sendable {
    public static let outputSampleRate: Double = 16_000

    private var sourceSampleRate: Double = 0
    private var pendingInput: [Float] = []
    private var resamplePosition: Double = 0

    public init() {}

    public mutating func resample(_ samples: [Float], sourceSampleRate: Double) -> [Int16] {
        guard sourceSampleRate > 0 else { return [] }

        if sourceSampleRate != self.sourceSampleRate {
            // Interpolating between samples from different input devices would be meaningless.
            self.sourceSampleRate = sourceSampleRate
            pendingInput.removeAll(keepingCapacity: true)
            resamplePosition = 0
        }

        let resampleStep = sourceSampleRate / Self.outputSampleRate
        pendingInput.append(contentsOf: samples)

        var output: [Int16] = []
        output.reserveCapacity(Int(Double(pendingInput.count) / resampleStep) + 1)

        while resamplePosition + 1 < Double(pendingInput.count) {
            let lowerIndex = Int(resamplePosition)
            let fraction = Float(resamplePosition - Double(lowerIndex))
            let lower = pendingInput[lowerIndex]
            let upper = pendingInput[lowerIndex + 1]
            let sample = lower + ((upper - lower) * fraction)
            let clamped = max(-1, min(1, sample))
            output.append(Int16(clamped * Float(Int16.max)))
            resamplePosition += resampleStep
        }

        // When downsampling, the next read position can land past the end of the pending input.
        let removableSamples = min(Int(resamplePosition), pendingInput.count)
        if removableSamples > 0 {
            pendingInput.removeFirst(removableSamples)
            resamplePosition -= Double(removableSamples)
        }

        return output
    }
}
