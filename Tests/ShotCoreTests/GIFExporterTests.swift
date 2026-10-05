import AVFoundation
import ImageIO
import Testing
@testable import ShotCore

/// Tests that read, write or export video. They run one at a time: several at once each block a
/// thread in AVFoundation and, on a runner with few cores, can wait on each other forever.
@Suite(.serialized) struct MediaTests {}

/// Waits until `input` takes more data. A writer that stops writing never makes it ready again,
/// so that fails the test instead of waiting forever.
func waitUntilReady(_ input: AVAssetWriterInput, of writer: AVAssetWriter) async throws {
    while !input.isReadyForMoreMediaData {
        try #require(writer.status == .writing, "The writer stopped: \(String(describing: writer.error))")
        try await Task.sleep(for: .milliseconds(5))
    }
}

func writeSyntheticVideo(to url: URL, seconds: Int, fps: Int32, width: Int, height: Int) async throws {
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

extension MediaTests {
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

    @Test func concatenatesSegments() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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
}

/// RMS of the first audio track per quarter second, keyed by quarter.
private func audioLevels(of asset: AVAsset) async throws -> [Int: Float] {
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
