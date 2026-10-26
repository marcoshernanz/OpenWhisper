import Foundation
import Testing
@testable import OpenWhisperCore

@Test func padsARecordingWithSilence() throws {
    let samples: [Int16] = [1, -1, 32_767, -32_768]
    let silence = [Int16](repeating: 0, count: 4_000)
    let padded = try #require(WAVFile.paddingWithSilence(0.25, around: wav(samples)))

    #expect(padded == wav(silence + samples + silence))
}

@Test func padsTheSamplesBetweenOtherChunks() throws {
    var listChunk = Data("LIST".utf8)
    listChunk.append(littleEndian: UInt32(3))
    listChunk.append(Data("abc".utf8) + Data([0]))
    let samples: [Int16] = [5, 6]
    let silence = [Int16](repeating: 0, count: 16)

    let padded = try #require(WAVFile.paddingWithSilence(0.001, around: wav(samples, extraChunk: listChunk)))

    #expect(padded == wav(silence + samples + silence, extraChunk: listChunk))
}

@Test func padsOnlyTheSamplesARecordingCutShortHolds() throws {
    var truncated = wav([1, 2, 3])
    truncated.removeLast(2)
    let silence = [Int16](repeating: 0, count: 16)

    let padded = try #require(WAVFile.paddingWithSilence(0.001, around: truncated))

    #expect(padded == wav(silence + [1, 2] + silence))
}

@Test func leavesFilesItCannotReadAlone() {
    var floatWAV = wav([1, 2])
    floatWAV[20] = 3

    #expect(WAVFile.paddingWithSilence(0.5, around: Data("not audio".utf8)) == nil)
    #expect(WAVFile.paddingWithSilence(0.5, around: floatWAV) == nil)
    #expect(WAVFile.paddingWithSilence(0.5, around: wav([1]).prefix(36)) == nil)
}
