import AVFoundation
import ImageIO
import Testing
@testable import ShotCore

// MARK: Options

@Test func exportOptionsDefaultsAndChoices() {
    let options = VideoExportOptions()
    #expect(options.format == .mp4)
    #expect(options.gifFrameRate == 15)
    #expect(options.gifWidth == 720)
    #expect(!options.muted)
    #expect(options.speed == 1)
    #expect(VideoExportOptions.gifFrameRates == [10, 15, 24])
    #expect(VideoExportOptions.gifWidths == [480, 720, 1080, VideoExportOptions.originalWidth])
    #expect(VideoExportOptions.speeds == [1, 1.5, 2])
    #expect(VideoExportFormat.gif.fileExtension == "gif")
    #expect(VideoExportFormat.mp4.fileExtension == "mp4")
}

@Test func originalWidthHasNoCap() {
    var options = VideoExportOptions()
    #expect(options.gifMaxWidth == 720)
    options.gifWidth = VideoExportOptions.originalWidth
    #expect(options.gifMaxWidth == nil)
}

@Test func gifSummaryDescribesTheFrameRateWidthAndLengthCap() {
    #expect(VideoExportOptions().gifSummary == "15 fps, up to 720 px wide, first 60 seconds.")
    let full = VideoExportOptions(gifFrameRate: 24, gifWidth: VideoExportOptions.originalWidth)
    #expect(full.gifSummary == "24 fps, full width, first 60 seconds.")
}

@Test func outputLengthFollowsSpeed() {
    var options = VideoExportOptions()
    let range = TrimRange(start: 2, end: 8, duration: 10)
    #expect(options.outputLength(of: range) == 6)
    options.speed = 1.5
    #expect(options.outputLength(of: range) == 4)
    options.speed = 2
    #expect(options.outputLength(of: range) == 3)
}

// MARK: GIF frame plan

@Test func gifPlanScalesDownButNeverUp() {
    let range = TrimRange(duration: 2)
    let source = CGSize(width: 1280, height: 720)
    #expect(GIFFramePlan(sourceSize: source, range: range, fps: 12, maxWidth: 720).size == CGSize(width: 720, height: 405))
    #expect(GIFFramePlan(sourceSize: source, range: range, fps: 12, maxWidth: 480).size == CGSize(width: 480, height: 270))
    #expect(GIFFramePlan(sourceSize: source, range: range, fps: 12, maxWidth: nil).size == source)
    #expect(GIFFramePlan(sourceSize: CGSize(width: 640, height: 360), range: range, fps: 12, maxWidth: 1080).size == CGSize(width: 640, height: 360))
}

@Test(arguments: [10, 12, 15, 24]) func gifFrameDelaysAddUpToTheRightLength(fps: Int) {
    let plan = GIFFramePlan(sourceSize: CGSize(width: 640, height: 360), range: TrimRange(duration: 10), fps: Double(fps), maxWidth: nil)
    let hundredths = (0..<plan.frameCount).map { plan.delay(ofFrame: $0) * 100 }
    #expect(hundredths.allSatisfy { abs($0 - $0.rounded()) < 1e-9 }, "whole hundredths, as a GIF stores them")
    #expect(abs(hundredths.reduce(0, +) - 1000) < 1e-6, "\(fps) fps plays for 10 s, not 10.5")
}

@Test func gifPlanSamplesTheRangeAtTheSpeed() {
    let range = TrimRange(start: 1, end: 3, duration: 4)
    let plan = GIFFramePlan(sourceSize: CGSize(width: 640, height: 360), range: range, fps: 10, maxWidth: nil, speed: 2)
    // 2 s at 2× plays for 1 s: 10 frames, each 0.1 s on screen and 0.2 s apart in the source.
    #expect(plan.frameCount == 10)
    #expect(plan.frameDelay == 0.1)
    #expect(!plan.truncated)
    #expect(plan.sourceTime(ofFrame: 0) == 1)
    #expect(abs(plan.sourceTime(ofFrame: 1) - 1.2) < 1e-9)
    #expect(abs(plan.sourceTime(ofFrame: 9) - 2.8) < 1e-9)

    let normal = GIFFramePlan(sourceSize: CGSize(width: 640, height: 360), range: range, fps: 24, maxWidth: nil)
    #expect(normal.frameCount == 48)
    #expect(abs(normal.sourceTime(ofFrame: 24) - 2) < 1e-9)
}

@Test func gifPlanCapsTheOutputLength() {
    let long = TrimRange(duration: 130)
    let plan = GIFFramePlan(sourceSize: CGSize(width: 640, height: 360), range: long, fps: 10, maxWidth: nil, speed: 2)
    // 130 s at 2× is 65 s, over the 60 s cap.
    #expect(plan.truncated)
    #expect(plan.frameCount == 600)
    let fits = GIFFramePlan(sourceSize: CGSize(width: 640, height: 360), range: TrimRange(duration: 110), fps: 10, maxWidth: nil, speed: 2)
    #expect(!fits.truncated)
    #expect(fits.frameCount == 550)
}

@Test func gifPlanAlwaysHasAFrame() {
    let plan = GIFFramePlan(sourceSize: CGSize(width: 640, height: 360), range: TrimRange(duration: 0.01), fps: 10, maxWidth: nil)
    #expect(plan.frameCount == 1)
}

@Test func gifEstimateSamplesSpreadAcrossTheRange() {
    let plan = GIFFramePlan(sourceSize: CGSize(width: 640, height: 360), range: TrimRange(duration: 10), fps: 10, maxWidth: nil)
    #expect(plan.sampleFrames(4) == [12, 37, 62, 87])
    #expect(plan.sampleFrames(500).count == 100)
    let single = GIFFramePlan(sourceSize: CGSize(width: 640, height: 360), range: TrimRange(duration: 0.01), fps: 10, maxWidth: nil)
    #expect(single.sampleFrames(4) == [0])
}

// MARK: Size estimates

@Test func mp4EstimateDropsMutedAudioAndSqueezesItWithSpeed() {
    // 2 Mbit/s video and 128 kbit/s audio for 10 s.
    let full = VideoTrimmer.estimatedBytes(videoBitRate: 2_000_000, audioBitRate: 128_000, length: 10, speed: 1, muted: false)
    #expect(full == 2_660_000)
    #expect(VideoTrimmer.estimatedBytes(videoBitRate: 2_000_000, audioBitRate: 128_000, length: 10, speed: 1, muted: true) == 2_500_000)
    // Every video frame is kept at any speed; the audio is retimed to the shorter length.
    #expect(VideoTrimmer.estimatedBytes(videoBitRate: 2_000_000, audioBitRate: 128_000, length: 10, speed: 2, muted: false) == 2_580_000)
}

@Test func gifEstimateScalesTheSampleToEveryFrame() {
    // One whole frame, then only what changes in each of the other 99.
    #expect(GIFExporter.extrapolate(wholeFrameBytes: 40_000, changeBytes: 1_000, totalFrames: 100) == 139_000)
    #expect(GIFExporter.extrapolate(wholeFrameBytes: 40_000, changeBytes: 1_000, totalFrames: 1) == 40_000)
}

// MARK: Rendering

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

extension MediaTests {
    @Test func gifExportUsesTheRangeFrameRateWidthAndSpeed() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("in.mp4")
        let gif = folder.appendingPathComponent("out.gif")
        try await writeSyntheticVideo(to: video, seconds: 4, fps: 30, width: 640, height: 360)

        let result = try await GIFExporter.export(videoURL: video, to: gif, range: TrimRange(start: 1, end: 3, duration: 4), fps: 10, maxWidth: 480, speed: 2)

        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 10)
        #expect(result.frameCount == 10)
        #expect(!result.truncated)
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(first.width == 480)
        #expect(first.height == 270)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let gifProperties = try #require(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        #expect(abs((gifProperties[kCGImagePropertyGIFDelayTime] as? Double ?? 0) - 0.1) < 0.005)
        // Each source frame has its own gray level, so the frames show which source times were used:
        // output frame i comes from 1 s + i × 0.2 s.
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let third = try #require(CGImageSourceCreateImageAtIndex(source, 2, nil))
        let levels = try [grayLevel(of: first), grayLevel(of: third)]
        let expected = try await [
            grayLevel(of: generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image),
            grayLevel(of: generator.image(at: CMTime(seconds: 1.4, preferredTimescale: 600)).image),
        ]
        // Within a frame either way (4 levels apart), as the exporter allows half an output frame of slack.
        #expect(abs(levels[0] - expected[0]) <= 6)
        #expect(abs(levels[1] - expected[1]) <= 6)
    }

    @Test func gifExportKeepsTheOriginalWidth() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("in.mp4")
        let gif = folder.appendingPathComponent("out.gif")
        try await writeSyntheticVideo(to: video, seconds: 1, fps: 30, width: 640, height: 360)

        let result = try await GIFExporter.export(videoURL: video, to: gif, fps: 24, maxWidth: nil)

        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(abs(CGImageSourceGetCount(source) - 24) <= 1)
        #expect(result.frameCount == CGImageSourceGetCount(source))
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(first.width == 640)
        #expect(first.height == 360)
    }

    @Test func mp4ExportCanDropTheAudio() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        try await writeScreenRecording(to: input, seconds: 3, audio: true)
        let kept = folder.appendingPathComponent("kept.mp4")
        let muted = folder.appendingPathComponent("muted.mp4")

        let range = TrimRange(start: 0.5, end: 2.5, duration: 3)
        try await VideoTrimmer.trim(input, range: range, to: kept)
        let passthrough = try await VideoTrimmer.trim(input, range: range, muted: true, to: muted)

        #expect(passthrough)
        #expect(try await AVURLAsset(url: kept).loadTracks(withMediaType: .audio).count == 1)
        let mutedAsset = AVURLAsset(url: muted)
        #expect(try await mutedAsset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try await mutedAsset.loadTracks(withMediaType: .video).count == 1)
        #expect(abs(try await mutedAsset.load(.duration).seconds - 2) < 0.1)
    }

    @Test func mp4ExportSpeedsUpVideoAndAudio() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        try await writeScreenRecording(to: input, seconds: 4, audio: true)
        let output = folder.appendingPathComponent("fast.mp4")

        let passthrough = try await VideoTrimmer.trim(input, range: TrimRange(start: 1, end: 4, duration: 4), speed: 1.5, to: output)

        #expect(passthrough)
        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 2) < 0.1)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let (size, formats) = try await video.load(.naturalSize, .formatDescriptions)
        #expect(size == CGSize(width: 640, height: 400))
        // The frames are copied, not re-encoded, and none are dropped.
        #expect(formats.map(CMFormatDescriptionGetMediaSubType) == [kCMVideoCodecType_H264])
        // 3 s at 30 fps; passthrough may keep one frame at the cut.
        let frames = try sampleCount(of: video, in: asset)
        #expect((90...91).contains(frames))
        // Both tracks are really retimed rather than stretched by an edit list that most players ignore.
        let audio = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        for track in [video, audio] {
            let segments = try await track.load(.segments)
            #expect(segments.allSatisfy { abs($0.timeMapping.source.duration.seconds - $0.timeMapping.target.duration.seconds) < 0.001 })
        }
        #expect(abs(try await audio.load(.timeRange).duration.seconds - 2) < 0.1)
    }

    @Test func mutedSpeedUpRetimesTheFrames() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        try await writeScreenRecording(to: input, seconds: 2, audio: false)
        let output = folder.appendingPathComponent("fast.mp4")

        try await VideoTrimmer.trim(input, range: TrimRange(duration: 2), speed: 2, to: output)

        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 1) < 0.1)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let segments = try await video.load(.segments)
        #expect(segments.allSatisfy { abs($0.timeMapping.source.duration.seconds - $0.timeMapping.target.duration.seconds) < 0.001 })
        let frames = try sampleCount(of: video, in: asset)
        #expect((60...61).contains(frames))
    }

    @Test func mp4ExportCanChangeTheFileType() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mov")
        try await writeSyntheticVideo(to: folder.appendingPathComponent("tmp.mp4"), seconds: 1, fps: 30, width: 320, height: 240)
        try FileManager.default.moveItem(at: folder.appendingPathComponent("tmp.mp4"), to: input)
        let output = folder.appendingPathComponent("out.mp4")

        try await VideoTrimmer.trim(input, range: TrimRange(duration: 1), to: output, as: .mp4)

        #expect(abs(try await AVURLAsset(url: output).load(.duration).seconds - 1) < 0.1)
    }

    // "Within roughly 25% of the actual size for typical screen recordings."
    @Test(arguments: [(VideoExportFormat.mp4, 1.0, false), (.mp4, 2.0, false), (.mp4, 1.5, true), (.gif, 1.0, false), (.gif, 2.0, false)])
    func sizeEstimateIsWithinAQuarterOfTheResult(format: VideoExportFormat, speed: Double, muted: Bool) async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        try await writeScreenRecording(to: input, seconds: 6, audio: true)
        let output = folder.appendingPathComponent("out.\(format.fileExtension)")
        let range = TrimRange(start: 1, end: 5.5, duration: 6)

        let estimate: Int
        switch format {
        case .mp4:
            estimate = try await VideoTrimmer.estimatedSize(of: input, range: range, speed: speed, muted: muted)
            try await VideoTrimmer.trim(input, range: range, speed: speed, muted: muted, to: output)
        case .gif:
            estimate = try await GIFExporter.estimatedSize(of: input, range: range, fps: 15, maxWidth: 480, speed: speed)
            try await GIFExporter.export(videoURL: input, to: output, range: range, fps: 15, maxWidth: 480, speed: speed)
        }

        let actual = try #require(try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int)
        #expect(abs(Double(estimate) / Double(actual) - 1) <= 0.25, "estimate \(estimate) vs actual \(actual)")
    }
}

// MARK: Helpers

private func grayLevel(of image: CGImage) throws -> Int {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return Int(pixel[1])
}

private func sampleCount(of track: AVAssetTrack, in asset: AVAsset) throws -> Int {
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    reader.startReading()
    var count = 0
    while let buffer = output.copyNextSampleBuffer() {
        count += CMSampleBufferGetNumSamples(buffer)
    }
    return count
}

/// A 640 × 400, 30 fps stand-in for a screen recording: a static window with lines of text,
/// a line being typed, and a moving pointer, plus an optional 440 Hz tone.
func writeScreenRecording(to url: URL, seconds: Int, audio: Bool) async throws {
    let width = 640, height = 400, fps = 30, sampleRate = 44100
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    // Both inputs are fed from one loop, so neither may wait for the other to catch up.
    video.expectsMediaDataInRealTime = true
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(video)
    let sound = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
    ])
    sound.expectsMediaDataInRealTime = true
    if audio {
        writer.add(sound)
    }
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
        if audio {
            let samples = (0..<chunk).map { Int16(8000 * sin(Double(frame * chunk + $0) * 2 * .pi * 440 / Double(sampleRate))) }
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: chunk * 2, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: chunk * 2, flags: 0, blockBufferOut: &block)
            let data = try #require(block)
            samples.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: data, offsetIntoDestination: 0, dataLength: chunk * 2) }
            var buffer: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: data, formatDescription: audioFormat, sampleCount: chunk, presentationTimeStamp: CMTime(value: CMTimeValue(frame * chunk), timescale: CMTimeScale(sampleRate)), packetDescriptions: nil, sampleBufferOut: &buffer)
            try await waitUntilReady(sound, of: writer)
            sound.append(try #require(buffer))
        }
        try await waitUntilReady(video, of: writer)
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        let context = try #require(CGContext(
            data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        drawScreen(in: context, width: width, height: height, frame: frame)
        CVPixelBufferUnlockBaseAddress(pixels, [])
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
    }
    video.markAsFinished()
    if audio {
        sound.markAsFinished()
    }
    await writer.finishWriting()
    #expect(writer.status == .completed)
}

private func drawScreen(in context: CGContext, width: Int, height: Int, frame: Int) {
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let window = CGRect(x: 40, y: 30, width: width - 80, height: height - 60)
    context.setFillColor(CGColor(gray: 0.97, alpha: 1))
    context.fill(window)
    context.setFillColor(CGColor(gray: 0.85, alpha: 1))
    context.fill(CGRect(x: window.minX, y: window.maxY - 24, width: window.width, height: 24))
    context.setFillColor(CGColor(gray: 0.2, alpha: 1))
    // Static "text": rows of words with fixed, varied widths.
    for row in 0..<14 {
        var x = window.minX + 16
        for word in 0..<9 {
            let wordWidth = CGFloat(12 + (row * 7 + word * 13) % 38)
            context.fill(CGRect(x: x, y: window.maxY - 44 - CGFloat(row) * 20, width: wordWidth, height: 8))
            x += wordWidth + 7
        }
    }
    // A line being typed, one character every other frame.
    context.setFillColor(CGColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: window.minX + 16, y: window.minY + 20, width: min(window.width - 32, CGFloat(frame / 2) * 6), height: 8))
    // The pointer moves across the window.
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    let t = CGFloat(frame) / 30
    context.fill(CGRect(x: window.minX + 40 + t * 70, y: window.midY + 60 * sin(t), width: 10, height: 14))
}
