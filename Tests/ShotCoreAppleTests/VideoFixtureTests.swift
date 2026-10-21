import AVFoundation
import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

// The clips in Tests/Fixtures/video, written here by AVFoundation as a Mac records, and what AVVideoReader reads from
// them. ShotCoreLinuxTests' FFmpegReaderTests reads them through ffprobe and ffmpeg and expects the same.
//
// - `timed.mp4`: 160 × 120 at 30 fps for 2 s, frame n gray level 4n, a sync frame every 15 frames, and a 440 Hz tone
//   for its first second.
// - `rotated.mp4`: 160 × 90 green with its top-left quarter red, turned a quarter, for 1 s, with no sound.
// - `tone.m4a`: a 440 Hz tone for 2 s, with no picture.
//
// Run with SHOT_WRITE_GOLDENS=1 to write them again.

private let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/video")

extension MediaTests {
    @Test func theVideoFixturesReadAsTheLinuxTestsExpect() async throws {
        if ProcessInfo.processInfo.environment["SHOT_WRITE_GOLDENS"] == "1" {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in ["timed.mp4", "rotated.mp4", "tone.m4a"] {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
            try await writeTimedRecording(to: folder.appendingPathComponent("timed.mp4"), seconds: 2, width: 160, height: 120, grayStep: 4, keyFrameInterval: 15)
            try await writeSolidVideo(to: folder.appendingPathComponent("rotated.mp4"), color: .green, corner: .red, size: CGSize(width: 160, height: 90), seconds: 1, rotated: true)
            try await writeScreenRecording(to: folder.appendingPathComponent("tone.m4a"), seconds: 2, audio: true, video: false)
        }
        let reader = AVVideoReader()
        let timed = folder.appendingPathComponent("timed.mp4")
        let info = try await reader.info(of: timed)
        #expect(abs(info.duration - 2) < 0.05 && info.size == CGSize(width: 160, height: 120) && info.hasAudio)
        let rates = try await reader.bitRates(of: timed)
        #expect(abs(rates.video - 12_500) < 2_500 && abs(rates.audio - 17_300) < 3_500, "\(rates)")
        // AVFoundation gives a sync frame's time on the track's own timeline, which here starts two frames late.
        let sync = try #require(try await reader.syncTimes(atOrBefore: [0.2, 0.7, 1.9], in: timed))
        #expect(zip(sync, [0, 0.5, 1.5]).allSatisfy { abs($0 - $1) < 0.1 }, "\(sync)")

        var frames: [(requested: Double, time: Double, gray: Int)] = []
        try await reader.readFrames(of: timed, at: [1, 0.1, 1], maxSize: .zero, tolerance: 0) { frame in
            let (time, image) = try frame.decoded.get()
            frames.append((frame.requestedTime, time, try grayLevel(of: image)))
        }
        // Frames 30 and 3, gray 120 and 12 as written, which AVFoundation reads as 131 and 10, and ffmpeg as written.
        #expect(frames.map(\.requested) == [1, 0.1, 1])
        #expect(zip(frames.map(\.time), [1, 0.1, 1]).allSatisfy { abs($0 - $1) < 0.001 })
        #expect(zip(frames.map(\.gray), [120, 12, 120]).allSatisfy { abs($0 - $1) <= 12 }, "\(frames)")

        let rotatedURL = folder.appendingPathComponent("rotated.mp4")
        let rotated = try await reader.info(of: rotatedURL)
        #expect(rotated.size == CGSize(width: 90, height: 160) && !rotated.hasAudio)
        var size: CGSize?
        try await reader.readFrames(of: rotatedURL, at: [0.5], maxSize: CGSize(width: 45, height: 0), tolerance: nil) { frame in
            let image = try frame.decoded.get().image
            size = CGSize(width: image.width, height: image.height)
        }
        #expect(size == CGSize(width: 45, height: 80))
        // Turned a quarter clockwise, the red corner is at the top right.
        #expect(try await pixel(in: rotatedURL, at: 0.5, x: 0.9, y: 0.1).isNear(.red))
        #expect(try await pixel(in: rotatedURL, at: 0.5, x: 0.1, y: 0.1).isNear(.green))

        var samples: [Float] = []
        try await reader.readMonoSamples(of: timed, sampleRate: 8000) { samples += $0 }
        #expect(abs(samples.count - 16_000) < 100)
        // The tone, at a quarter of full scale, then silence.
        #expect(abs(AudioLevel.rms(Array(samples[1600..<6400])) - 0.17) < 0.02 && AudioLevel.rms(Array(samples[9600..<14400])) < 0.01)
        let tone = try await reader.info(of: folder.appendingPathComponent("tone.m4a"))
        #expect(abs(tone.duration - 2) < 0.05 && tone.size == nil && tone.hasAudio)
    }
}
