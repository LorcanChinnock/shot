import Foundation
import Testing
@testable import ShotCore

/// Samples 4 a second over `duration`, with the picture changing between `changes`' samples and still elsewhere.
private func sampled(_ duration: Double, changing changes: Range<Double>?) -> (differences: [Double], times: [Double]) {
    let times = stride(from: 0, through: duration, by: 0.25).map { $0 }
    let differences = times.enumerated().map { index, time in
        index > 0 && changes.map { $0.contains(time) } == true ? 0.05 : 0.001
    }
    return (differences, times)
}

/// Peaks 100 a second over `duration`, loud during `loud` and near silent elsewhere.
private func audio(_ duration: Double, loud: [Range<Double>]) -> [WaveformPeak] {
    (0 ..< Int(duration * 100)).map { index in
        let time = Double(index) / 100
        let level: Float = loud.contains { $0.contains(time) } ? 0.4 : 0.01
        return WaveformPeak(min: -level, max: level)
    }
}

@Test func aStillStartAndEndAreTrimmedWithPadding() throws {
    let (differences, times) = sampled(12, changing: 3 ..< 9)
    let range = try #require(IdleTrim.range(differences: differences, times: times, duration: 12))
    // The first change is between 2.75 and 3, the last at 8.75; 0.4 s of padding either side.
    #expect(abs(range.start - 2.35) < 0.001)
    #expect(abs(range.end - 9.15) < 0.001)
}

@Test func speechOverAStillScreenIsKept() throws {
    let (differences, times) = sampled(12, changing: 5 ..< 8)
    let range = try #require(IdleTrim.range(differences: differences, times: times, audio: audio(12, loud: [1.5 ..< 3, 9 ..< 10.5]), duration: 12))
    #expect(abs(range.start - 1.1) < 0.02)
    #expect(abs(range.end - 10.9) < 0.02)
}

@Test func aClickOrABreathIsntSpeech() {
    #expect(IdleTrim.speech(in: audio(5, loud: [1 ..< 1.05, 3 ..< 3.1])) == nil)
    let gappy = IdleTrim.speech(in: audio(5, loud: [1 ..< 1.2, 1.4 ..< 1.6]))
    #expect(gappy.map { abs($0.lowerBound - 1) < 0.02 && abs($0.upperBound - 1.6) < 0.02 } == true)
}

@Test func aRecordingWithNoIdleTimeKeepsItAll() throws {
    let (differences, times) = sampled(6, changing: 0 ..< 6)
    let range = try #require(IdleTrim.range(differences: differences, times: times, duration: 6))
    #expect(range.isFull(duration: 6))
}

@Test func anEndIsLeftAloneWhenTrimmingItWouldSaveLittle() throws {
    // The action runs to 0.25 s from the end, which with the padding saves nothing worth a trim.
    let (differences, times) = sampled(10, changing: 4 ..< 9.8)
    let range = try #require(IdleTrim.range(differences: differences, times: times, duration: 10))
    #expect(range.start > 3)
    #expect(range.end == 10)
}

@Test func anAllIdleRecordingHasNothingToKeep() {
    let (differences, times) = sampled(8, changing: nil)
    #expect(IdleTrim.range(differences: differences, times: times, audio: audio(8, loud: []), duration: 8) == nil)
    #expect(IdleTrim.range(differences: [], times: [], duration: 0) == nil)
}

@Test func aVideoWithAStillStartAndEndIsTrimmedToTheAction() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("idle.mp4")
    // Still grey for 2 s, changing from 2 s to 5 s, then still again until 7 s.
    try await writeSyntheticVideo(to: url, seconds: 7, fps: 10, width: 160, height: 90) { frame in
        frame < 20 ? 40 : frame < 50 ? 40 + (frame - 20) * 6 : 220
    }
    let sampled = try await KeyFrameExtractor.differences(in: url, duration: 7)
    let range = try #require(IdleTrim.range(differences: sampled.differences, times: sampled.actual, duration: 7))
    #expect(abs(range.start - 1.6) < 0.35)
    #expect(abs(range.end - 5.4) < 0.35)
}
