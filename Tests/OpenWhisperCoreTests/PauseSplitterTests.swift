import Testing
@testable import OpenWhisperCore

private let sampleRate = 16_000

/// A 200 Hz square wave standing in for speech, with silence over the given seconds. Every 100 ms frame
/// of it has exactly the same energy.
private func speech(seconds: Double, silences: [ClosedRange<Double>] = []) -> [Float] {
    var samples = (0..<Int(seconds * Double(sampleRate))).map { index -> Float in
        index % 80 < 40 ? 0.5 : -0.5
    }
    for silence in silences {
        let start = Int((silence.lowerBound * Double(sampleRate)).rounded(.up))
        let end = min(samples.count - 1, Int(silence.upperBound * Double(sampleRate)))
        samples.replaceSubrange(start...end, with: repeatElement(0, count: end - start + 1))
    }
    return samples
}

@Test func cutsInThePauseNearestTheMiddle() {
    let samples = speech(seconds: 10, silences: [4.6...5.1])

    let parts = PauseSplitter.split(samples[...], into: 2, sampleRate: sampleRate)

    #expect(parts.count == 2)
    let cutSeconds = Double(parts[1].startIndex) / Double(sampleRate)
    #expect((4.6...5.1).contains(cutSeconds))
}

@Test func ignoresPausesTooFarFromTheEvenCut() {
    let samples = speech(seconds: 10, silences: [3...3.8])

    let parts = PauseSplitter.split(samples[...], into: 2, sampleRate: sampleRate)

    #expect(abs(parts[1].startIndex - samples.count / 2) <= sampleRate / 10)
}

@Test func partsCoverTheWholeRecordingInOrder() {
    let samples = speech(seconds: 61, silences: [14...14.4, 31...31.2, 47...47.5])

    let parts = PauseSplitter.split(samples[...], into: 4, sampleRate: sampleRate)

    #expect(parts.count == 4)
    #expect(parts.first?.startIndex == samples.startIndex)
    #expect(parts.last?.endIndex == samples.endIndex)
    for (part, next) in zip(parts, parts.dropFirst()) {
        #expect(part.endIndex == next.startIndex)
    }
    for part in parts {
        #expect(part.count >= samples.count / 4 * 3 / 4)
    }
}

@Test func keepsEveryPartWithinTheLongestAllowed() {
    let maxPartLength = 18 * sampleRate
    // Pauses right where they pull each cut as far as it can go.
    let samples = speech(seconds: 600, silences: stride(from: 13.0, to: 600, by: 14.6).map { $0...($0 + 0.3) })

    let parts = PauseSplitter.split(samples[...], maxPartLength: maxPartLength, sampleRate: sampleRate)

    #expect(parts.count > 1)
    #expect(parts.allSatisfy { $0.count <= maxPartLength })
    #expect(parts.map(\.count).reduce(0, +) == samples.count)
}

@Test func leavesARecordingThatFitsWhole() {
    let samples = speech(seconds: 17)

    let parts = PauseSplitter.split(samples[...], maxPartLength: 18 * sampleRate, sampleRate: sampleRate)

    #expect(parts.count == 1)
}

@Test func splitsASliceOfALongerRecording() {
    let samples = speech(seconds: 30, silences: [19.8...20.3])
    let span = samples[(10 * sampleRate)..<(30 * sampleRate)]

    let parts = PauseSplitter.split(span, into: 2, sampleRate: sampleRate)

    #expect(parts.first?.startIndex == span.startIndex)
    #expect(parts.last?.endIndex == span.endIndex)
    let cutSeconds = Double(parts[1].startIndex) / Double(sampleRate)
    #expect((19.8...20.3).contains(cutSeconds))
}

@Test func leavesARecordingWholeWhenOnePartIsAsked() {
    let samples = speech(seconds: 5)

    let parts = PauseSplitter.split(samples[...], into: 1, sampleRate: sampleRate)

    #expect(parts == [samples[...]])
}
