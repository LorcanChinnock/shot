import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
@testable import ShotCore

extension MediaTests {
    @Test func aGIFHasAFrameForEachOfThePlansTimesAndReportsItsProgress() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("in.mp4"), gif = folder.appendingPathComponent("out.gif")
        try await writeSyntheticVideo(to: video, seconds: 2, fps: 30, width: 1280, height: 720)
        let heard = Mutex<[Double]>([])

        let result = try await GIFExporter.export(videoURL: video, to: gif, fps: 10, maxWidth: 320) { value in
            heard.withLock { $0.append(value) }
        }

        #expect(result.frameCount == 20)
        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 20)
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(first.width == 320 && first.height == 180)
        #expect(heard.withLock { $0 } == (1...20).map { Double($0) / 20 })
    }

    @Test func aGIFOfADrawnProjectHasAFrameForEachOfThePlansTimes() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("in.mp4"), gif = folder.appendingPathComponent("out.gif")
        try await writeSyntheticVideo(to: video, seconds: 2, fps: 30, width: 640, height: 360)
        let project = Project(source: video, duration: 2, canvasSize: CGSize(width: 640, height: 360), hasAudio: false)
        let plan = VideoExportPlan.compositeGIF(project, fps: 10, maxWidth: nil, speed: 2)

        let outcome = try await plan.run(to: gif)
        #expect(outcome.frameCount == 10)
        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 10)
        #expect(try await plan.estimate() > 0)
    }

    @Test func readingFramesHandsThemOverInTheOrderAsked() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("in.mp4")
        try await writeSyntheticVideo(to: video, seconds: 2, fps: 30, width: 320, height: 240)
        let times = [1.5, 0.1, 1.0, 0.1, 0.5]

        var asked: [Double] = []
        try await AVVideoReader.readFrames(of: video, at: times, maxSize: CGSize(width: 160, height: 0), tolerance: 0) { frame in
            asked.append(frame.requestedTime)
            #expect((try? frame.decoded.get()) != nil)
        }
        #expect(asked == times)
    }
}
