import AVFoundation
import Testing
@testable import ShotCore

@Test func peaksTrackTheLoudestAndQuietestSamplesPerSlice() {
    // 1000 samples a second makes 10 samples a peak.
    let samples = (0..<30).map { Float($0 % 10 == 3 ? 0.5 : $0 % 10 == 7 ? -0.25 : 0.1) }
    let peaks = Waveform.peaks(of: samples, sampleRate: 1000)
    #expect(peaks == Array(repeating: WaveformPeak(min: -0.25, max: 0.5), count: 3))
}

@Test func aPartialLastSliceStillMakesAPeak() {
    #expect(Waveform.peaks(of: [Float](repeating: 0.2, count: 15), sampleRate: 1000).count == 2)
    #expect(Waveform.peaks(of: [Float](), sampleRate: 1000).isEmpty)
}

@Test func mergingPeaksKeepsTheExtremesOfEachSpan() {
    let peaks = [0.1, 0.9, 0.2, 0.3].map { WaveformPeak(min: -Float($0), max: Float($0)) }
    let waveform = Waveform(peaks: peaks, duration: 4)
    #expect(waveform.peaks(in: 0..<4, count: 2) == [WaveformPeak(min: -0.9, max: 0.9), WaveformPeak(min: -0.3, max: 0.3)])
    #expect(waveform.peaks(in: 1..<2, count: 1) == [WaveformPeak(min: -0.9, max: 0.9)])
    #expect(waveform.peaks(in: 0..<4, count: 4) == peaks)
    #expect(waveform.peaks(in: 2..<2, count: 3).isEmpty)
}

extension MediaTests {
    @Test func loadingARecordingReadsItsToneAsEvenPeaks() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeScreenRecording(to: url, seconds: 2, audio: true)
        let waveform = try #require(try await Waveform.load(url))
        #expect(abs(waveform.duration - 2) < 0.1)
        // 8000 / 32768 is about 0.24, and AAC lands within a few percent of it.
        let peaks = waveform.peaks(in: 0.2..<1.8, count: 8)
        #expect(peaks.allSatisfy { $0.max > 0.2 && $0.max < 0.3 && $0.min < -0.2 })
    }

    @Test func aRecordingWithoutAudioHasNoWaveform() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeScreenRecording(to: url, seconds: 1, audio: false)
        #expect(try await Waveform.load(url) == nil)
    }
}
