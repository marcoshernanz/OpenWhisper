import Testing
@testable import OpenWhisperCore

@Test func resamplesBuiltInMicrophoneAudioToWhisperRate() {
    var resampler = WhisperPCMResampler()

    let output = resampler.resample([Float](repeating: 0.5, count: 4_800), sourceSampleRate: 48_000)

    #expect(output.count == 1_600)
    #expect(output.allSatisfy { $0 == Int16(0.5 * Float(Int16.max)) })
}

@Test func keepsResamplingWhenBuffersDoNotAlignWithTheStep() {
    var resampler = WhisperPCMResampler()
    var outputCount = 0

    for _ in 0..<10 {
        outputCount += resampler.resample(
            [Float](repeating: 0.25, count: 4_096),
            sourceSampleRate: 48_000
        ).count
    }

    #expect(abs(outputCount - 40_960 / 3) <= 1)
}

@Test func followsInputSampleRateChangesMidRecording() {
    var resampler = WhisperPCMResampler()

    let builtInMicrophone = resampler.resample(
        [Float](repeating: 0.1, count: 48_000),
        sourceSampleRate: 48_000
    )
    let airPodsMicrophone = resampler.resample(
        [Float](repeating: -0.1, count: 24_000),
        sourceSampleRate: 24_000
    )

    #expect(abs(builtInMicrophone.count - 16_000) <= 1)
    #expect(abs(airPodsMicrophone.count - 16_000) <= 1)
    #expect(airPodsMicrophone.allSatisfy { $0 < 0 })
}

@Test func ignoresAudioWithoutASampleRate() {
    var resampler = WhisperPCMResampler()

    #expect(resampler.resample([0.1, 0.2, 0.3], sourceSampleRate: 0).isEmpty)
}
