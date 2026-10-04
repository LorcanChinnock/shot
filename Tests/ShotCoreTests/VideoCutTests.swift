import AVFoundation
import ImageIO
import Testing
@testable import ShotCore

// MARK: Cut list

@Test func noCutsKeepTheWholeTrim() {
    let range = TrimRange(start: 1, end: 9, duration: 10)
    #expect(CutList().isEmpty)
    #expect(CutList().kept(in: range) == [range])
    #expect(CutList().keptLength(in: range) == 8)
}

@Test func twoCutsLeaveThreeSections() {
    let range = TrimRange(duration: 10)
    let cuts = CutList([2..<3, 6..<7.5])
    #expect(cuts.kept(in: range) == [
        TrimRange(start: 0, end: 2, duration: 10),
        TrimRange(start: 3, end: 6, duration: 10),
        TrimRange(start: 7.5, end: 10, duration: 10),
    ])
    #expect(cuts.keptLength(in: range) == 7.5)
}

@Test func cutsOutsideTheTrimAreIgnoredAndOverlapsClipped() {
    let range = TrimRange(start: 2, end: 8, duration: 10)
    let cuts = CutList([0..<1, 1.5..<3, 7..<9.5])
    #expect(cuts.kept(in: range) == [TrimRange(start: 3, end: 7, duration: 10)])
    #expect(cuts.keptLength(in: range) == 4)
    // A cut reaching the in or out point leaves nothing before or after it.
    #expect(CutList([2..<4]).kept(in: range) == [TrimRange(start: 4, end: 8, duration: 10)])
    #expect(CutList([5..<8]).kept(in: range) == [TrimRange(start: 2, end: 5, duration: 10)])
}

@Test func addingSortsAndMergesOverlappingOrTouchingCuts() {
    var cuts = CutList()
    cuts = cuts.adding(6..<7)
    cuts = cuts.adding(2..<3)
    #expect(cuts.cuts == [2..<3, 6..<7])
    #expect(cuts.adding(2.5..<6.5).cuts == [2..<7])
    #expect(cuts.adding(3..<4).cuts == [2..<4, 6..<7])
    #expect(cuts.adding(1..<8).cuts == [1..<8])
    #expect(cuts.adding(4..<4) == cuts)
}

@Test func cuttingASelectionKeepsItInsideTheTrim() {
    let range = TrimRange(start: 2, end: 8, duration: 10)
    #expect(CutList().cutting(1..<3, from: range)?.cuts == [2..<3])
    #expect(CutList().cutting(4..<5, from: range)?.cuts == [4..<5])
    // A selection wholly outside the trim changes nothing.
    #expect(CutList().cutting(8.5..<9.5, from: range) == CutList())
}

@Test func cuttingRefusesToLeaveLessThanTheMinimum() {
    let range = TrimRange(start: 2, end: 8, duration: 10)
    #expect(CutList().cutting(0..<10, from: range) == nil)
    #expect(CutList([2..<5]).cutting(5..<7.95, from: range) == nil)
    #expect(CutList([2..<5]).cutting(5..<7.9, from: range)?.cuts == [2..<7.9])
}

@Test func trimMustLeaveSomethingBetweenTheCuts() {
    let cuts = CutList([2..<8])
    #expect(cuts.allows(TrimRange(start: 1, end: 9, duration: 10)))
    #expect(cuts.allows(TrimRange(start: 1.9, end: 8, duration: 10)))
    #expect(!cuts.allows(TrimRange(start: 2.5, end: 8, duration: 10)))
    #expect(!cuts.allows(TrimRange(start: 3, end: 7, duration: 10)))
}

@Test func cutContainingATime() {
    let cuts = CutList([2..<3, 6..<7])
    #expect(cuts.cut(containing: 2) == 2..<3)
    #expect(cuts.cut(containing: 6.5) == 6..<7)
    #expect(cuts.cut(containing: 3) == nil)
    #expect(cuts.cut(containing: 1) == nil)
}

@Test func playbackReachingACutFindsItEvenWhenItIsShort() {
    let cuts = CutList([2..<2.02, 6..<7])
    // The player reports a time at or just after the cut's start, or a hair before it.
    #expect(cuts.cut(reachedAt: 2.005) == 2..<2.02)
    #expect(cuts.cut(reachedAt: 5.99) == 6..<7)
    #expect(cuts.cut(reachedAt: 6.4) == 6..<7)
    // Already past it, or nowhere near one.
    #expect(cuts.cut(reachedAt: 2.03) == nil)
    #expect(cuts.cut(reachedAt: 4) == nil)
}

@Test func onlyCutsBeforeTheEndOfPlaybackAreSkipPoints() {
    let range = TrimRange(start: 1, end: 9, duration: 10)
    let cuts = CutList([0..<0.5, 3..<4, 7..<9.5])
    #expect(cuts.skipPoints(in: range) == [3])
}

@Test func outputTimeMapsBackToTheSource() {
    let range = TrimRange(start: 1, end: 10, duration: 10)
    let cuts = CutList([2..<3, 6..<7.5])
    // Kept: 1–2, 3–6, 7.5–10.
    #expect(cuts.sourceTime(at: 0, in: range) == 1)
    #expect(cuts.sourceTime(at: 0.5, in: range) == 1.5)
    #expect(cuts.sourceTime(at: 1, in: range) == 3)
    #expect(cuts.sourceTime(at: 3.5, in: range) == 5.5)
    #expect(cuts.sourceTime(at: 4, in: range) == 7.5)
    #expect(cuts.sourceTime(at: 5, in: range) == 8.5)
    #expect(cuts.sourceTime(at: 99, in: range) == 10)
    #expect(CutList().sourceTime(at: 2, in: range) == 3)
}

@Test func playbackSkipsCutsAndStopsAtTheLastSection() {
    let range = TrimRange(start: 1, end: 9, duration: 10)
    let cuts = CutList([3..<4, 7..<9])
    #expect(cuts.playbackEnd(in: range) == 7)
    #expect(CutList().playbackEnd(in: range) == 9)
    #expect(cuts.playbackStart(from: 2, in: range) == 2)
    // Inside a cut, play from where it ends.
    #expect(cuts.playbackStart(from: 3.5, in: range) == 4)
    // Outside the trim, or at the end of the last section, start over.
    #expect(cuts.playbackStart(from: 0.5, in: range) == 1)
    #expect(cuts.playbackStart(from: 7, in: range) == 1)
    #expect(cuts.playbackStart(from: 8, in: range) == 1)
    #expect(cuts.playbackStart(from: 6.995, in: range) == 1)
}

@Test func cutsShortenTheSizeEstimateAndOutputLength() async throws {
    let range = TrimRange(start: 2, end: 8, duration: 10)
    let cuts = CutList([3..<4, 5..<6])
    var options = VideoExportOptions()
    #expect(options.outputLength(of: range, cuts: cuts) == 4)
    options.speed = 2
    #expect(options.outputLength(of: range, cuts: cuts) == 2)
    let plan = GIFFramePlan(sourceSize: CGSize(width: 640, height: 360), range: range, cuts: cuts, fps: 10, maxWidth: nil, speed: 2)
    // 4 s kept at 2× plays for 2 s.
    #expect(plan.frameCount == 20)
    // Kept: 2–3, 4–5, 6–8. Frame i is 0.2 × i s into the kept time.
    #expect(plan.sourceTime(ofFrame: 0) == 2)
    #expect(abs(plan.sourceTime(ofFrame: 4) - 2.8) < 1e-9)
    #expect(abs(plan.sourceTime(ofFrame: 7) - 4.4) < 1e-9)
    #expect(abs(plan.sourceTime(ofFrame: 15) - 7) < 1e-9)
}

// MARK: Export

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

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

        await #expect(throws: VideoTrimmer.TrimError.self) {
            try await VideoTrimmer.trim(input, range: TrimRange(duration: 1), cuts: CutList([0..<1]), to: folder.appendingPathComponent("out.mp4"))
        }
    }
}

// MARK: Helpers

/// Source seconds 0–1, 2–3 and 4–5 have the tone; the rest is silent.
private func hasTone(atSource time: Double) -> Bool {
    Int(time) % 2 == 0
}

/// A 320 × 240, 30 fps video whose frame `n` is gray level `n`, with a 440 Hz tone during even seconds.
private func writeTimedRecording(to url: URL, seconds: Int) async throws {
    let width = 320, height = 240, fps = 30, sampleRate = 44100
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    video.expectsMediaDataInRealTime = true
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(video)
    let sound = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
    ])
    sound.expectsMediaDataInRealTime = true
    writer.add(sound)
    var pcm = AudioStreamBasicDescription(
        mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM, mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
    )
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &pcm, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
    let audioFormat = try #require(format)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let chunk = sampleRate / fps
    for frame in 0..<(fps * seconds) {
        let loud = hasTone(atSource: Double(frame) / Double(fps))
        let samples = (0..<chunk).map { loud ? Int16(8000 * sin(Double(frame * chunk + $0) * 2 * .pi * 440 / Double(sampleRate))) : 0 }
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: chunk * 2, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: chunk * 2, flags: 0, blockBufferOut: &block)
        let data = try #require(block)
        samples.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: data, offsetIntoDestination: 0, dataLength: chunk * 2) }
        var audioBuffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: data, formatDescription: audioFormat, sampleCount: chunk, presentationTimeStamp: CMTime(value: CMTimeValue(frame * chunk), timescale: CMTimeScale(sampleRate)), packetDescriptions: nil, sampleBufferOut: &audioBuffer)
        try await waitUntilReady(sound, of: writer)
        sound.append(try #require(audioBuffer))

        try await waitUntilReady(video, of: writer)
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame), CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
    }
    video.markAsFinished()
    sound.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
}

/// The gray level of the frame shown at `time`; neighbouring source frames differ by about one level.
private func grayLevel(in asset: AVAsset, at time: Double) async throws -> Int {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return try await grayLevel(of: generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image)
}

private func grayLevel(of image: CGImage) throws -> Int {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return Int(pixel[1])
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
