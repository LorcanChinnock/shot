import AVFoundation
import Testing
@testable import ShotCore

extension MediaTests {
    @Test func concatenatesSegments() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("a.mp4"), b = folder.appendingPathComponent("b.mp4")
        try await writeSyntheticVideo(to: a, seconds: 1, fps: 30, width: 320, height: 240)
        try await writeSyntheticVideo(to: b, seconds: 2, fps: 30, width: 320, height: 240)
        let output = folder.appendingPathComponent("out.mp4")
        try await VideoConcatenator.concatenate([a, b], to: output)
        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(duration - 3) < 0.15)
        #expect(!FileManager.default.fileExists(atPath: a.path))

        let single = folder.appendingPathComponent("single.mp4")
        try await writeSyntheticVideo(to: a, seconds: 1, fps: 30, width: 320, height: 240)
        try await VideoConcatenator.concatenate([a], to: single)
        #expect(FileManager.default.fileExists(atPath: single.path))
    }

    @Test func mutingSilencesOnlyThoseStretchesOfAudio() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("a.mp4"), b = folder.appendingPathComponent("b.mp4")
        try await writeScreenRecording(to: a, seconds: 2, audio: true)
        try await writeScreenRecording(to: b, seconds: 2, audio: true)
        let output = folder.appendingPathComponent("out.mp4")
        try await VideoConcatenator.concatenate([a, b], to: output, muting: CutList([1.5..<2.5, 3.5..<10]))
        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 4) < 0.15)
        let levels = try await audioLevels(of: asset)
        for (second, loud) in [(0.5, true), (1.25, true), (2.0, false), (2.75, true), (3.75, false)] {
            let level = levels[Int(second * 4)] ?? 0
            #expect((level > 0.05) == loud, "RMS \(level) at \(second) s")
        }
    }

    @Test func joiningNoSegmentsSaysNothingWasRecorded() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        await #expect(throws: VideoConcatenator.ConcatError.noSegments) {
            try await VideoConcatenator.concatenate([], to: output)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}
