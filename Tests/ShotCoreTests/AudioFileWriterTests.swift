import AVFoundation
import Testing
@testable import ShotCore

extension MediaTests {
    @Test func audioFileStartsAtTheGivenTime() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("mic.mov")
        let writer = AudioFileWriter(url: url)
        try await writeTone(to: writer, from: 1000, seconds: 0.5, amplitude: 0.5, frequency: 440)
        writer.start(at: CMTime(seconds: 1000.25, preferredTimescale: 48000))
        try await writeTone(to: writer, from: 1000.5, seconds: 1.5, amplitude: 0.5, frequency: 440)
        await writer.finish()
        await writer.finish()
        let asset = AVURLAsset(url: url)
        #expect(abs(try await asset.load(.duration).seconds - 1.75) < 0.05)
        let levels = try await audioLevels(of: asset)
        #expect((levels[0] ?? 1) < 0.01)
        #expect((levels[4] ?? 0) > 0.2)
    }

    @Test func mutingSilencesOnlyTheMicrophone() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var segments: [URL] = []
        var audio: [VideoConcatenator.SegmentAudio] = []
        for name in ["a", "b"] {
            let video = folder.appendingPathComponent("\(name).mp4")
            try await writeSyntheticVideo(to: video, seconds: 2, fps: 30, width: 320, height: 240)
            let files = VideoConcatenator.SegmentAudio(system: folder.appendingPathComponent("\(name)-system.mov"), microphone: folder.appendingPathComponent("\(name)-mic.mov"))
            for (url, amplitude, frequency) in [(files.system, Float(0.1), 440.0), (files.microphone, Float(0.5), 660.0)] {
                let writer = AudioFileWriter(url: url)
                writer.start(at: CMTime(seconds: 500, preferredTimescale: 48000))
                try await writeTone(to: writer, from: 500, seconds: 2, amplitude: amplitude, frequency: frequency)
                await writer.finish()
            }
            segments.append(video)
            audio.append(files)
        }
        let output = folder.appendingPathComponent("out.mp4")
        try await VideoConcatenator.concatenate(segments, audio: audio, to: output, muting: CutList([1.5..<2.5, 3.5..<10]))
        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 4) < 0.15)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        let levels = try await audioLevels(of: asset)
        for (second, microphone) in [(0.5, true), (1.25, true), (2.0, false), (2.75, true), (3.75, false)] {
            let level = levels[Int(second * 4)] ?? 0
            #expect(microphone ? level > 0.25 : (0.03...0.15).contains(level), "RMS \(level) at \(second) s")
        }
        #expect(!FileManager.default.fileExists(atPath: audio[0].microphone.path))
    }
}

/// Feeds a mono sine to `writer` in tenth-second buffers timed from `start` seconds.
private func writeTone(to writer: AudioFileWriter, from start: Double, seconds: Double, amplitude: Float, frequency: Double) async throws {
    let rate = 48000, chunk = 4800
    var pcm = AudioStreamBasicDescription(
        mSampleRate: Double(rate), mFormatID: kAudioFormatLinearPCM, mFormatFlags: kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0
    )
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &pcm, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
    let first = Int(start * Double(rate))
    for offset in stride(from: 0, to: Int(seconds * Double(rate)), by: chunk) {
        let samples = (0..<chunk).map { amplitude * Float(sin(Double(offset + $0) * 2 * .pi * frequency / Double(rate))) }
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: chunk * 4, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: chunk * 4, flags: 0, blockBufferOut: &block)
        let data = try #require(block)
        samples.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: data, offsetIntoDestination: 0, dataLength: chunk * 4) }
        var buffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: data, formatDescription: try #require(format), sampleCount: chunk, presentationTimeStamp: CMTime(value: CMTimeValue(first + offset), timescale: CMTimeScale(rate)), packetDescriptions: nil, sampleBufferOut: &buffer)
        writer.append(try #require(buffer))
        try await Task.sleep(for: .milliseconds(5))
    }
}
