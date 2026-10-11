import AVFoundation
import Testing
@testable import ShotCore

@Test func timeRangeUsesAFrameAccurateTimescale() {
    let range = TrimRange(start: 1.5, end: 4, duration: 10).timeRange
    #expect(range.start == CMTime(value: 900, timescale: 600))
    #expect(range.duration == CMTime(value: 1500, timescale: 600))
}

// MARK: Export

extension MediaTests {
    @Test func trimsWithoutReencoding() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        let output = folder.appendingPathComponent("out.mp4")
        try await writeSyntheticVideo(to: input, seconds: 3, fps: 30, width: 640, height: 360)

        let passthrough = try await VideoTrimmer.trim(input, range: TrimRange(start: 1, end: 2, duration: 3), to: output)

        #expect(passthrough)
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 1) < 0.1)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let (size, formats) = try await track.load(.naturalSize, .formatDescriptions)
        #expect(size == CGSize(width: 640, height: 360))
        #expect(formats.map(CMFormatDescriptionGetMediaSubType) == [kCMVideoCodecType_H264])
    }

    @Test func trimReplacesAnExistingOutput() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        let output = folder.appendingPathComponent("out.mp4")
        try await writeSyntheticVideo(to: input, seconds: 2, fps: 30, width: 320, height: 240)
        try Data("old".utf8).write(to: output)

        try await VideoTrimmer.trim(input, range: TrimRange(start: 0.5, end: 1.5, duration: 2), to: output)

        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(duration - 1) < 0.1)
    }

    @Test func trimRefusesAFileTypeItCantWrite() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        try await writeSyntheticVideo(to: input, seconds: 1, fps: 30, width: 320, height: 240)
        let output = folder.appendingPathComponent("out.gif")

        await #expect(throws: VideoTrimmer.TrimError.unsupportedFileType) {
            try await VideoTrimmer.trim(input, range: TrimRange(duration: 1), to: output, as: AVFileType("com.compuserve.gif"))
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func trimCantTellTheFileTypeOfAnInputWithNoExtension() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("recording")
        try await writeSyntheticVideo(to: input, seconds: 1, fps: 30, width: 320, height: 240)

        await #expect(throws: VideoTrimmer.TrimError.unsupportedFileType) {
            try await VideoTrimmer.trim(input, range: TrimRange(duration: 1), to: folder.appendingPathComponent("out"))
        }
    }
}
