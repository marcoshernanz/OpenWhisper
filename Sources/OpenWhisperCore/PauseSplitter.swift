import Foundation

/// Cuts a recording into consecutive parts in pauses between words instead of in the middle of one.
public enum PauseSplitter {
    /// Ends each part in the longest pause within the second half of the longest allowed part, which is
    /// usually the end of a sentence.
    ///
    /// Whisper leaves out the start of a part that begins in the middle of a sentence, as if it belonged to
    /// the text before the part, which is where the vocabulary prompt goes. Cutting at the quietest moment
    /// near an even split often cut a sentence in two and lost the rest of it.
    public static func split(
        _ samples: ArraySlice<Float>,
        maxPartLength: Int,
        sampleRate: Int
    ) -> [ArraySlice<Float>] {
        guard samples.count > maxPartLength, maxPartLength > 0 else { return [samples] }

        let pauses = Pauses(in: samples, sampleRate: sampleRate)
        var parts: [ArraySlice<Float>] = []
        var partStart = samples.startIndex

        while samples.endIndex - partStart > maxPartLength {
            let cut = pauses.bestCut(in: (partStart + maxPartLength / 2)...(partStart + maxPartLength))
            parts.append(samples[partStart..<cut])
            partStart = cut
        }

        parts.append(samples[partStart...])
        return parts
    }

    /// Each cut moves to the longest pause within an eighth of a part of where an even split would put it,
    /// so every part is between three quarters and five quarters of the even length.
    public static func split(
        _ samples: ArraySlice<Float>,
        into partCount: Int,
        sampleRate: Int
    ) -> [ArraySlice<Float>] {
        guard partCount > 1, samples.count >= partCount else { return [samples] }

        let pauses = Pauses(in: samples, sampleRate: sampleRate)
        let tolerance = samples.count / partCount / 8
        var parts: [ArraySlice<Float>] = []
        var partStart = samples.startIndex

        for boundary in 1..<partCount {
            let evenCut = samples.startIndex + boundary * samples.count / partCount
            let cut = pauses.bestCut(in: (evenCut - tolerance)...(evenCut + tolerance), preferring: evenCut)
            parts.append(samples[partStart..<cut])
            partStart = cut
        }

        parts.append(samples[partStart...])
        return parts
    }
}

/// The quiet stretches of a recording, measured in 20 ms frames.
private struct Pauses {
    private let startIndex: Int
    private let endIndex: Int
    private let frameLength: Int
    private let energies: [Float]
    private let isQuiet: [Bool]

    init(in samples: ArraySlice<Float>, sampleRate: Int) {
        startIndex = samples.startIndex
        endIndex = samples.endIndex
        let frameLength = max(1, sampleRate / 50)
        let energies = stride(from: samples.startIndex, to: samples.endIndex, by: frameLength).map { frameStart in
            let frame = samples[frameStart..<min(frameStart + frameLength, samples.endIndex)]
            return frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count)
        }
        self.frameLength = frameLength
        self.energies = energies

        // Background noise differs between rooms and microphones, so quiet is measured against this
        // recording: within the lowest third of the way, in decibels, from its background to its speech.
        // Speech without pauses long enough to set the background has only digital silence as quiet.
        let sorted = energies.sorted()
        let background = max(Self.silence, sorted[sorted.count / 10])
        let speech = sorted[sorted.count * 9 / 10]
        let threshold = speech >= background * Self.speechOverBackground
            ? background * pow(speech / background, 1.0 / 3)
            : 0
        isQuiet = energies.map { $0 <= threshold }
    }

    /// The middle of the longest pause within `range`, counting only the part of it inside the range. Of the
    /// pauses at least three quarters as long as the longest, the one closest to `preferredCut` wins, or
    /// without one the latest, which keeps parts long. Without any pause, it is the quietest moment.
    func bestCut(in range: ClosedRange<Int>, preferring preferredCut: Int? = nil) -> Int {
        let range = max(startIndex + 1, range.lowerBound)...min(endIndex - 1, range.upperBound)
        let firstFrame = (range.lowerBound - startIndex + frameLength - 1) / frameLength
        let lastFrame = (range.upperBound - startIndex) / frameLength
        guard firstFrame < lastFrame else { return range.lowerBound }

        var runs: [Range<Int>] = []
        var runStart: Int?
        for frame in firstFrame...lastFrame {
            if isQuiet[frame], runStart == nil {
                runStart = frame
            } else if !isQuiet[frame], let start = runStart {
                runs.append(start..<frame)
                runStart = nil
            }
        }
        if let start = runStart {
            runs.append(start..<(lastFrame + 1))
        }

        guard let longest = runs.map(\.count).max() else {
            return quietestCut(firstFrame: firstFrame, lastFrame: lastFrame, preferring: preferredCut)
        }

        let candidates = runs.filter { $0.count * 4 >= longest * 3 }
        let chosen: Range<Int>
        if let preferredCut {
            chosen = candidates.min { abs(center(of: $0) - preferredCut) < abs(center(of: $1) - preferredCut) }!
        } else {
            chosen = candidates.last!
        }
        return min(max(center(of: chosen), range.lowerBound), range.upperBound)
    }

    /// The middle of the frame whose surroundings are quietest, preferring the one closest to `preferredCut`.
    /// Scoring a frame together with its neighbors favors a short pause over a stop inside a word.
    private func quietestCut(firstFrame: Int, lastFrame: Int, preferring preferredCut: Int?) -> Int {
        let preferredCut = preferredCut ?? frameCenter(lastFrame)
        let score = { (frame: Int) in
            energies[max(0, frame - 2)...min(energies.count - 1, frame + 2)].reduce(0, +)
        }
        let quietest = (firstFrame...lastFrame).min { lhs, rhs in
            let lhsScore = score(lhs)
            let rhsScore = score(rhs)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return abs(frameCenter(lhs) - preferredCut) < abs(frameCenter(rhs) - preferredCut)
        }!
        return min(frameCenter(quietest), endIndex - 1)
    }

    private func center(of run: Range<Int>) -> Int {
        startIndex + (run.lowerBound + run.upperBound) * frameLength / 2
    }

    private func frameCenter(_ frame: Int) -> Int {
        startIndex + frame * frameLength + frameLength / 2
    }

    /// The background of digital silence, which keeps the threshold above zero.
    private static let silence: Float = 1e-10
    /// Speech is at least 10 dB louder than the pauses between it.
    private static let speechOverBackground: Float = 10
}
