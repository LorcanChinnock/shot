import AVFoundation
import ImageIO
import Testing
@testable import ShotCore

private func writeSyntheticVideo(to url: URL, seconds: Int, fps: Int32, width: Int, height: Int) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<(Int(fps) * seconds) {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(5))
        }
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

@Test func exportsTwoSecondVideoAtTwelveFPS() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let video = folder.appendingPathComponent("in.mp4")
    let gif = folder.appendingPathComponent("out.gif")
    try await writeSyntheticVideo(to: video, seconds: 2, fps: 30, width: 1280, height: 720)

    let result = try await GIFExporter.export(videoURL: video, to: gif)

    let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
    let frames = CGImageSourceGetCount(source)
    #expect(abs(frames - 24) <= 1)
    #expect(result.frameCount == frames)
    #expect(!result.truncated)
    let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(first.width == 720)
    #expect(first.height == 405)
}
