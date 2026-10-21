import AVFoundation
import CoreGraphics
import Testing
@testable import ShotCore

// Synthetic videos and the helpers that read them back, shared by the tests that export or composite.

/// Tests that read, write or export video. They run one at a time within a suite: several at once each block a
/// thread in AVFoundation and, on a runner with few cores, can wait on each other forever, and they run out of
/// hardware codec sessions (`Cannot Decode`). Two suites run side by side, so at most two block at once and a
/// 3-core runner keeps a thread free. Keep their serial times about even; `CompositionTests` alone is about 10 s.
@Suite(.serialized) struct MediaTests {}
/// The second half of the media tests: composition, GIF export, and the commands and agent tools that export.
@Suite(.serialized) struct CompositingMediaTests {}

/// A new, empty folder in the temporary directory; the caller removes it.
func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// A preferences store of its own for one test. It lives in a temporary folder, not ~/Library/Preferences, because
/// removing a domain there still leaves cfprefsd to write an empty plist for it a moment later. `remove()` deletes both.
struct TestDefaults {
    let name: String
    let store: UserDefaults
    private let folder: URL

    init() throws {
        folder = try temporaryFolder()
        name = folder.appendingPathComponent("defaults").path
        store = try #require(UserDefaults(suiteName: name))
    }

    func remove() {
        store.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: folder)
    }
}

// MARK: Images

/// The pixel at (`x`, `y`) points from the top left of an 8-bit RGBA bitmap, as fractions; `scale` is pixels per point.
func pixel(_ image: CGImage, _ x: CGFloat, _ y: CGFloat, scale: CGFloat = 1) throws -> [CGFloat] {
    let data = try #require(image.dataProvider?.data as Data?)
    let offset = Int(y * scale) * image.bytesPerRow + Int(x * scale) * 4
    return data[offset..<offset + 4].map { CGFloat($0) / 255 }
}

/// The bytes of the pixel at (`x`, `y`) from the top left of an 8-bit RGBA bitmap.
func pixelBytes(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
    let data = try #require(image.dataProvider?.data as Data?)
    let offset = y * image.bytesPerRow + x * 4
    return Array(data[offset..<offset + 4])
}

/// The green level of `image` scaled to one pixel; a frame of `writeSyntheticVideo` or `writeTimedRecording` is one gray.
func grayLevel(of image: CGImage) throws -> Int {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return Int(pixel[1])
}

// MARK: Videos

/// Waits until `input` takes more data. A writer that stops writing never makes it ready again,
/// so that fails the test instead of waiting forever.
func waitUntilReady(_ input: AVAssetWriterInput, of writer: AVAssetWriter) async throws {
    while !input.isReadyForMoreMediaData {
        try #require(writer.status == .writing, "The writer stopped: \(String(describing: writer.error))")
        try await Task.sleep(for: .milliseconds(5))
    }
}

func writeSyntheticVideo(to url: URL, seconds: Int, fps: Int32, width: Int, height: Int, codec: AVVideoCodecType = .h264) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<(Int(fps) * seconds) {
        try await waitUntilReady(input, of: writer)
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 4 % 255), CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
    }
    input.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
}

struct Color {
    var r: UInt8, g: UInt8, b: UInt8
    static let red = Color(r: 255, g: 0, b: 0)
    /// Mid-tone, since a primary at the edge of the gamut shifts the most through a video encode and decode.
    static let green = Color(r: 60, g: 200, b: 90)
    static let blue = Color(r: 0, g: 0, b: 255)
    static let black = Color(r: 0, g: 0, b: 0)

    func isNear(_ other: Color, tolerance: Int = 60) -> Bool {
        abs(Int(r) - Int(other.r)) <= tolerance && abs(Int(g) - Int(other.g)) <= tolerance && abs(Int(b) - Int(other.b)) <= tolerance
    }
}

/// A video of one flat colour, optionally with a corner marked in a second colour so orientation shows.
func writeSolidVideo(to url: URL, color: Color, corner: Color? = nil, size: CGSize, seconds: Double, rotated: Bool = false) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)])
    if rotated {
        input.transform = CGAffineTransform(rotationAngle: .pi / 2)
    }
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    // Every frame is the same, so it's filled once: per pixel per frame is slow in a debug build.
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &buffer)
    let pixels = try #require(buffer)
    CVPixelBufferLockBaseAddress(pixels, [])
    let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(pixels)
    for y in 0..<Int(size.height) {
        for x in 0..<Int(size.width) {
            let marked = corner != nil && x < Int(size.width) / 4 && y < Int(size.height) / 4
            let c = marked ? corner! : color
            let p = base + y * stride + x * 4
            p[0] = c.b; p[1] = c.g; p[2] = c.r; p[3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(pixels, [])
    for frame in 0..<Int(seconds * 30) {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(2))
        }
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
    }
    input.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
}

/// The colour at (`x`, `y`), as fractions of the frame from the top left, of the frame shown at `seconds`.
func pixel(in url: URL, at seconds: Double, x: Double, y: Double) async throws -> Color {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Draw so the wanted pixel falls on the one pixel of the context.
    let width = Double(image.width), height = Double(image.height)
    context.draw(image, in: CGRect(x: -x * width, y: -(1 - y) * height, width: width, height: height))
    return Color(r: bytes[0], g: bytes[1], b: bytes[2])
}

/// Source seconds 0–1, 2–3 and 4–5 of `writeTimedRecording` have the tone; the rest is silent.
func hasTone(atSource time: Double) -> Bool {
    Int(time) % 2 == 0
}

/// A 320 × 240, 30 fps video whose frame `n` is gray level `n` times `grayStep`, with a 440 Hz tone during even seconds,
/// and a sync frame at least every `keyFrameInterval` frames when that's given.
func writeTimedRecording(to url: URL, seconds: Int, width: Int = 320, height: Int = 240, grayStep: Int = 1, keyFrameInterval: Int? = nil) async throws {
    let fps = 30, sampleRate = 44100
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    var settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height]
    if let keyFrameInterval {
        settings[AVVideoCompressionPropertiesKey] = [AVVideoMaxKeyFrameIntervalKey: keyFrameInterval]
    }
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
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
        memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * grayStep), CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
    }
    video.markAsFinished()
    sound.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
}

/// A 640 × 400, 30 fps stand-in for a screen recording: a static window with lines of text,
/// a line being typed, and a moving pointer, plus an optional 440 Hz tone. Without `video` it's the tone alone.
func writeScreenRecording(to url: URL, seconds: Int, audio: Bool, video hasVideo: Bool = true) async throws {
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
    if hasVideo {
        writer.add(video)
    }
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
        guard hasVideo else {
            continue
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
    if hasVideo {
        video.markAsFinished()
    }
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

// MARK: Audio

/// RMS of the first audio track per quarter second, keyed by quarter.
func audioLevels(of asset: AVAsset) async throws -> [Int: Float] {
    let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
    ])
    reader.add(output)
    reader.startReading()
    var samples: [Int: [Float]] = [:]
    while let buffer = output.copyNextSampleBuffer(), let data = buffer.dataBuffer {
        let start = buffer.presentationTimeStamp.seconds
        let rate = Double(buffer.formatDescription?.audioStreamBasicDescription?.mSampleRate ?? 44100)
        var floats = [Float](repeating: 0, count: CMBlockBufferGetDataLength(data) / 4)
        CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: floats.count * 4, destination: &floats)
        for (index, sample) in floats.enumerated() {
            samples[Int((start + Double(index) / rate) * 4), default: []].append(sample)
        }
    }
    return samples.mapValues { AudioLevel.rms($0) }
}
