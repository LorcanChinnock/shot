import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
@testable import ShotCore
import ShotCoreApple

/// One `readFrames` call a `FakeFrames` was asked for.
private struct FrameRead: Equatable {
    var times: [Double]
    var maxSize: CGSize
    var tolerance: Double?
}

/// A flat gray picture of `size` that plays for `duration`, keeping the reads it's asked for. The frame at `failing`
/// doesn't decode.
private final class FakeFrames: VideoFrames {
    let duration: Double
    let size: CGSize?
    let failing: Int?
    let reads = Mutex<[FrameRead]>([])

    init(duration: Double, size: CGSize?, failing: Int? = nil) {
        self.duration = duration
        self.size = size
        self.failing = failing
    }

    func readFrames(at times: [Double], maxSize: CGSize, tolerance: Double?, _ body: (VideoFrame) throws -> Void) async throws {
        reads.withLock { $0.append(FrameRead(times: times, maxSize: maxSize, tolerance: tolerance)) }
        let image = try picture(maxSize)
        for (index, time) in times.enumerated() {
            let decoded: Result<(time: Double, image: PlatformImage), any Error> = index == failing ? .failure(CocoaError(.fileReadCorruptFile)) : .success((time, image))
            try body(VideoFrame(requestedTime: time, decoded: decoded))
        }
    }
}

/// A file, and any project, that's `frames`.
private struct FakeReader: VideoReader {
    let frames: FakeFrames

    func info(of url: URL) async throws -> ImportedMedia {
        ImportedMedia(source: url, duration: frames.duration, size: frames.size, hasAudio: false)
    }

    func bitRates(of url: URL) async throws -> (video: Double, audio: Double) {
        (0, 0)
    }

    func syncTimes(atOrBefore times: [Double], in url: URL) async throws -> [Double]? {
        nil
    }

    func readFrames(of url: URL, at times: [Double], maxSize: CGSize, tolerance: Double?, _ body: (VideoFrame) throws -> Void) async throws {
        try await frames.readFrames(at: times, maxSize: maxSize, tolerance: tolerance, body)
    }

    func frames(of project: Project, canvasType: any Canvas.Type) async throws -> any VideoFrames {
        frames
    }

    func readMonoSamples(of url: URL, sampleRate: Double, _ body: ([Float]) throws -> Void) async throws {}
}

private func picture(_ size: CGSize) throws -> CGImage {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let bitmap = CGImageAlphaInfo.premultipliedLast.rawValue
    let context = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: bitmap))
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(origin: .zero, size: size))
    return try #require(context.makeImage())
}

private let clip = URL(fileURLWithPath: "/nowhere/clip.mp4")

@Test func aGIFReadsAllItsFramesInOneCallAtThePlansTimes() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let gif = folder.appendingPathComponent("out.gif")
    let frames = FakeFrames(duration: 2, size: CGSize(width: 1280, height: 720))
    let heard = Mutex<[Double]>([])

    let result = try await GIFExporter.export(videoURL: clip, to: gif, fps: 10, maxWidth: 320, reader: FakeReader(frames: frames)) { value in
        heard.withLock { $0.append(value) }
    }

    let plan = GIFFramePlan(sourceSize: CGSize(width: 1280, height: 720), range: TrimRange(duration: 2), fps: 10, maxWidth: 320)
    let times = (0..<plan.frameCount).map(plan.sourceTime(ofFrame:))
    #expect(frames.reads.withLock { $0 } == [FrameRead(times: times, maxSize: CGSize(width: 320, height: 180), tolerance: 0.05)])
    #expect(result.frameCount == 20)
    let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
    #expect(CGImageSourceGetCount(source) == 20)
    #expect(heard.withLock { $0 } == (1...20).map { Double($0) / 20 })
}

@Test func aGIFOfMediaWithNoPictureSaysWhyBeforeReadingAnything() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let gif = folder.appendingPathComponent("out.gif")
    let frames = FakeFrames(duration: 2, size: nil)
    let reader = FakeReader(frames: frames)

    await #expect(throws: GIFExporter.ExportError.noVideoTrack) { try await GIFExporter.export(videoURL: clip, to: gif, reader: reader) }
    await #expect(throws: GIFExporter.ExportError.noVideoTrack) { try await GIFExporter.estimatedSize(of: clip, fps: 10, maxWidth: nil, reader: reader) }
    #expect(frames.reads.withLock { $0 }.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: gif.path))
}

@Test func aFrameThatWontDecodeFailsTheGIFAndLeavesNoFile() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let gif = folder.appendingPathComponent("out.gif")
    let frames = FakeFrames(duration: 2, size: CGSize(width: 320, height: 240), failing: 3)

    await #expect(throws: CocoaError.self) { try await GIFExporter.export(videoURL: clip, to: gif, reader: FakeReader(frames: frames)) }
    #expect(!FileManager.default.fileExists(atPath: gif.path))
}

@Test func aGIFOfADrawnProjectReadsTheProjectsFramesFromTheReader() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let gif = folder.appendingPathComponent("out.gif")
    let frames = FakeFrames(duration: 2, size: CGSize(width: 640, height: 360))
    let reader = FakeReader(frames: frames)
    let project = Project(source: clip, duration: 2, canvasSize: CGSize(width: 640, height: 360), hasAudio: false)
    let plan = VideoExportPlan.compositeGIF(project, fps: 10, maxWidth: nil, speed: 2)

    let outcome = try await plan.run(to: gif, canvasType: CGCanvas.self, reader: reader, assembler: AVVideoAssembler(), writer: AVVideoWriter())
    #expect(outcome.frameCount == 10)
    #expect(frames.reads.withLock { $0 }.map(\.times.count) == [10])

    frames.reads.withLock { $0 = [] }
    let estimate = try await plan.estimate(canvasType: CGCanvas.self, reader: reader)
    #expect(estimate > 0)
    // A pair of neighbouring frames at each place sampled.
    #expect(frames.reads.withLock { $0 }.map(\.times.count) == Array(repeating: 2, count: GIFExporter.estimateSamples))
}

extension MediaTests {
    @Test func readingFramesHandsThemOverInTheOrderAsked() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("in.mp4")
        try await writeSyntheticVideo(to: video, seconds: 2, fps: 30, width: 320, height: 240)
        let times = [1.5, 0.1, 1.0, 0.1, 0.5]

        var asked: [Double] = []
        try await AVVideoReader().readFrames(of: video, at: times, maxSize: CGSize(width: 160, height: 0), tolerance: 0) { frame in
            asked.append(frame.requestedTime)
            #expect((try? frame.decoded.get()) != nil)
        }
        #expect(asked == times)
    }
}
