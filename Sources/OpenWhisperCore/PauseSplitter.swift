import Foundation

/// Cuts a recording into consecutive parts at its quietest moments, so that each cut falls in a pause
/// between words instead of in the middle of one.
public enum PauseSplitter {
    /// Splits into as few parts as keep every part at most `maxPartLength` samples long.
    public static func split(
        _ samples: ArraySlice<Float>,
        maxPartLength: Int,
        sampleRate: Int
    ) -> [ArraySlice<Float>] {
        guard samples.count > maxPartLength, maxPartLength > 0 else { return [samples] }

        // Moving the cuts can make a part up to a quarter longer than an even split.
        let partCount = (samples.count * 5 / 4 + maxPartLength - 1) / maxPartLength
        return split(samples, into: partCount, sampleRate: sampleRate)
    }

    /// Each cut moves to the quietest point within an eighth of a part of where an even split would put it,
    /// so every part is between three quarters and five quarters of the even length.
    public static func split(
        _ samples: ArraySlice<Float>,
        into partCount: Int,
        sampleRate: Int
    ) -> [ArraySlice<Float>] {
        guard partCount > 1, samples.count >= partCount else { return [samples] }

        let frameLength = max(1, sampleRate / 10)
        let energies = frameEnergies(of: samples, frameLength: frameLength)
        let partLength = samples.count / partCount

        var parts: [ArraySlice<Float>] = []
        var partStart = samples.startIndex

        for boundary in 1..<partCount {
            let evenCut = boundary * samples.count / partCount
            let cut = samples.startIndex + quietestPoint(
                near: evenCut,
                within: partLength / 8,
                energies: energies,
                frameLength: frameLength
            )
            parts.append(samples[partStart..<cut])
            partStart = cut
        }

        parts.append(samples[partStart...])
        return parts
    }

    /// Mean square of each 100 ms frame.
    private static func frameEnergies(of samples: ArraySlice<Float>, frameLength: Int) -> [Float] {
        stride(from: samples.startIndex, to: samples.endIndex, by: frameLength).map { frameStart in
            let frame = samples[frameStart..<min(frameStart + frameLength, samples.endIndex)]
            return frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count)
        }
    }

    /// The middle of the frame whose surroundings are quietest, preferring the one closest to `offset`.
    /// Scoring a frame together with its neighbors favors a real pause over a short stop inside a word.
    private static func quietestPoint(
        near offset: Int,
        within tolerance: Int,
        energies: [Float],
        frameLength: Int
    ) -> Int {
        let candidates = energies.indices.filter { abs(frameCenter($0, frameLength) - offset) <= tolerance }

        let quietestFrame = candidates.min { lhs, rhs in
            let lhsScore = pauseScore(of: lhs, energies: energies)
            let rhsScore = pauseScore(of: rhs, energies: energies)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return abs(frameCenter(lhs, frameLength) - offset) < abs(frameCenter(rhs, frameLength) - offset)
        }

        return quietestFrame.map { frameCenter($0, frameLength) } ?? offset
    }

    private static func pauseScore(of frame: Int, energies: [Float]) -> Float {
        energies[max(0, frame - 1)...min(energies.count - 1, frame + 1)].reduce(0, +)
    }

    private static func frameCenter(_ frame: Int, _ frameLength: Int) -> Int {
        frame * frameLength + frameLength / 2
    }
}
