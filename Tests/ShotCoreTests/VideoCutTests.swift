import AVFoundation
import ImageIO
import Testing
@testable import ShotCore

// MARK: Export

/// Kept: 0–1 s (tone), 2–3.5 s (tone, then silence from 3), 4.5–6 s (tone to 5, then silence).
private let twoCutRange = TrimRange(duration: 6)
private let twoCuts = CutList([1..<2, 3.5..<4.5])

extension MediaTests {
    @Test func twoCutsExportWithMatchingVideoAndAudio() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        let output = folder.appendingPathComponent("out.mp4")
        try await writeTimedRecording(to: input, seconds: 6)

        try await VideoTrimmer.trim(input, range: twoCutRange, cuts: twoCuts, to: output)

        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 4) < 0.1)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let audio = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        #expect(abs(try await video.load(.timeRange).duration.seconds - 4) < 0.1)
        #expect(abs(try await audio.load(.timeRange).duration.seconds - 4) < 0.1)
        // Each output time shows the source frame it maps to, and plays the sound from that same moment.
        for (outputTime, sourceTime) in [(0.5, 0.5), (1.25, 2.25), (2.25, 3.25), (2.75, 4.75), (3.75, 5.75)] {
            let (shown, expected) = try await (grayLevel(in: asset, at: outputTime), grayLevel(in: AVURLAsset(url: input), at: sourceTime))
            #expect(abs(shown - expected) <= 4, "video at \(outputTime) s: level \(shown), source \(expected)")
            #expect(try await isLoud(asset, at: outputTime) == hasTone(atSource: sourceTime), "audio at \(outputTime) s")
        }
    }

    @Test func cutsComposeWithSpeedAndMute() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        try await writeTimedRecording(to: input, seconds: 6)
        let fast = folder.appendingPathComponent("fast.mp4")
        let muted = folder.appendingPathComponent("muted.mp4")

        try await VideoTrimmer.trim(input, range: twoCutRange, cuts: twoCuts, speed: 2, to: fast)
        try await VideoTrimmer.trim(input, range: twoCutRange, cuts: twoCuts, speed: 1.5, muted: true, to: muted)

        let fastAsset = AVURLAsset(url: fast)
        #expect(abs(try await fastAsset.load(.duration).seconds - 2) < 0.1)
        let fastAudio = try #require(try await fastAsset.loadTracks(withMediaType: .audio).first)
        #expect(abs(try await fastAudio.load(.timeRange).duration.seconds - 2) < 0.1)
        for (outputTime, sourceTime) in [(0.25, 0.5), (0.625, 2.25), (1.375, 4.75), (1.875, 5.75)] {
            let (shown, expected) = try await (grayLevel(in: fastAsset, at: outputTime), grayLevel(in: AVURLAsset(url: input), at: sourceTime))
            #expect(abs(shown - expected) <= 4, "video at \(outputTime) s: level \(shown), source \(expected)")
            #expect(try await isLoud(fastAsset, at: outputTime) == hasTone(atSource: sourceTime), "audio at \(outputTime) s")
        }

        let mutedAsset = AVURLAsset(url: muted)
        #expect(try await mutedAsset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(abs(try await mutedAsset.load(.duration).seconds - 4 / 1.5) < 0.1)
        let (shown, expected) = try await (grayLevel(in: mutedAsset, at: 1.5), grayLevel(in: AVURLAsset(url: input), at: 3.25))
        #expect(abs(shown - expected) <= 4, "level \(shown), source \(expected)")
    }

    @Test func gifExportSkipsTheCuts() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        let gif = folder.appendingPathComponent("out.gif")
        try await writeTimedRecording(to: input, seconds: 6)

        let result = try await GIFExporter.export(videoURL: input, to: gif, range: twoCutRange, cuts: twoCuts, fps: 10, maxWidth: nil, speed: 2)

        // 4 s kept at 2× is 2 s: 20 frames, frame i from output time i × 0.2 s.
        #expect(result.frameCount == 20)
        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 20)
        for (frame, sourceTime) in [(2, 0.4), (6, 2.2), (14, 4.8)] {
            let image = try #require(CGImageSourceCreateImageAtIndex(source, frame, nil))
            let (shown, expected) = try await (grayLevel(of: image), grayLevel(in: AVURLAsset(url: input), at: sourceTime))
            #expect(abs(shown - expected) <= 4, "frame \(frame): level \(shown), source \(expected)")
        }
    }
}

@Test func passthroughCopiesFromTheSyncFrameBeforeEachSection() {
    let kept = [TrimRange(start: 2, end: 3, duration: 10), TrimRange(start: 5, end: 6, duration: 10)]
    #expect(VideoTrimmer.copiedLength(of: kept, syncTimes: [1.5, 5]) == 2.5)
    #expect(VideoTrimmer.estimatedBytes(videoBitRate: 800, audioBitRate: 80, videoLength: 2.5, length: 2, speed: 1, muted: false) == 270)
}

extension MediaTests {
    // GIF estimates sample frames from the plan, whose cut handling is covered above.
    @Test(arguments: [1.0, 2.0])
    func mp4SizeEstimateWithCutsIsWithinAQuarterOfTheResult(speed: Double) async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        try await writeScreenRecording(to: input, seconds: 6, audio: true)
        let output = folder.appendingPathComponent("out.mp4")
        let range = TrimRange(start: 0.5, end: 6, duration: 6)
        let cuts = CutList([1.5..<2.5, 4..<5])

        let estimate = try await VideoTrimmer.estimatedSize(of: input, range: range, cuts: cuts, speed: speed)
        try await VideoTrimmer.trim(input, range: range, cuts: cuts, speed: speed, to: output)

        let actual = try #require(try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int)
        #expect(abs(Double(estimate) / Double(actual) - 1) <= 0.25, "estimate \(estimate) vs actual \(actual)")
    }

    @Test func exportRefusesToWriteNothing() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        try await writeSyntheticVideo(to: input, seconds: 1, fps: 30, width: 320, height: 240)

        await #expect(throws: VideoTrimmer.TrimError.nothingLeft) {
            try await VideoTrimmer.trim(input, range: TrimRange(duration: 1), cuts: CutList([0..<1]), to: folder.appendingPathComponent("out.mp4"))
        }
    }
}

// MARK: Helpers

/// The gray level of the frame shown at `time`; neighbouring source frames differ by about one level.
private func grayLevel(in asset: AVAsset, at time: Double) async throws -> Int {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return try await grayLevel(of: generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image)
}

/// Whether the audio in the 0.1 s around `time` carries the tone rather than silence.
private func isLoud(_ asset: AVAsset, at time: Double) async throws -> Bool {
    let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = CMTimeRange(start: CMTime(seconds: time - 0.05, preferredTimescale: 600), duration: CMTime(seconds: 0.1, preferredTimescale: 600))
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
    ])
    reader.add(output)
    reader.startReading()
    var peak = 0
    while let buffer = output.copyNextSampleBuffer() {
        guard let data = CMSampleBufferGetDataBuffer(buffer) else {
            continue
        }
        let length = CMBlockBufferGetDataLength(data)
        var samples = [Int16](repeating: 0, count: length / 2)
        samples.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
        peak = max(peak, samples.map { abs(Int($0)) }.max() ?? 0)
    }
    return peak > 2000
}
