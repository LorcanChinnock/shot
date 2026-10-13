import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private func edit(_ input: URL, _ edit: VideoEdit, output: String? = nil, projects: ProjectStore? = nil) async throws(ShotCommandError) -> JSONValue {
    try await ShotCommands.run(.edit(ShotCommand.EditOptions(input: input.path, output: output, spec: .video(edit))), projects: projects)
}

private func path(_ result: JSONValue) throws -> URL {
    URL(fileURLWithPath: try #require(result["path"]?.string))
}

private func failure(_ input: URL, _ spec: VideoEdit, output: String? = nil) async -> ShotCommandError? {
    do {
        _ = try await edit(input, spec, output: output)
        return nil
    } catch {
        return error
    }
}

/// The gray level of the frame `url` shows at `seconds`, which for `writeTimedRecording` is its source frame number.
private func frameLevel(_ url: URL, at seconds: Double) async throws -> Int {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return try grayLevel(of: try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image)
}

@Test func marksOverARecordingWithoutSoundMakeItDrawn() {
    let url = URL(fileURLWithPath: "/tmp/rec.mp4")
    let arrow = Annotation(kind: .arrow(from: .zero, to: CGPoint(x: 5, y: 5)), color: RGBA.presets[0], lineWidth: 4)
    for hasAudio in [false, true] {
        let plain = Project(source: url, duration: 2, canvasSize: CGSize(width: 160, height: 120), hasAudio: hasAudio)
        #expect(plain.trimEdit != nil)
        // Cut from the file, the marks would be left out of what it writes.
        #expect(plain.adding(annotation: arrow, at: 0, duration: 1).project.trimEdit == nil)
    }
}

/// A video of one frame of noise, which compresses about in proportion to its pixels, as a detailed screen does and a
/// flat test pattern doesn't.
private func writeNoiseVideo(to url: URL, size: CGSize, seconds: Double) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &buffer)
    let pixels = try #require(buffer)
    CVPixelBufferLockBaseAddress(pixels, [])
    let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
    var generator = SystemRandomNumberGenerator()
    for offset in 0..<CVPixelBufferGetDataSize(pixels) {
        base[offset] = offset % 4 == 3 ? 255 : UInt8.random(in: 0...255, using: &generator)
    }
    CVPixelBufferUnlockBaseAddress(pixels, [])
    for frame in 0..<Int(seconds * 30) {
        try await waitUntilReady(input, of: writer)
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
    }
    input.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
}

extension MediaTests {
    @Test func keepMuteAndSpeedPlayOnlyThePartsKeptAndReopenAsTheTrim() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
        let video = folder.appendingPathComponent("rec.mp4")
        try await writeTimedRecording(to: video, seconds: 6)

        let result = try await edit(video, VideoEdit(keep: [[1, 2], [3, 4.5]], mute: true), projects: store)
        let output = try path(result)
        #expect(output.lastPathComponent == "rec (2).mp4")
        #expect(abs((result["duration"]?.number ?? 0) - 2.5) < 0.1)
        // Each frame is its own gray level: 0.5 s in plays source 1.5 s, and 1.5 s in plays source 3.5 s.
        #expect(abs(try await frameLevel(output, at: 0.5) - frameLevel(video, at: 1.5)) <= 3)
        #expect(abs(try await frameLevel(output, at: 1.5) - frameLevel(video, at: 3.5)) <= 3)
        #expect(try await AVURLAsset(url: output).loadTracks(withMediaType: .audio).isEmpty)

        // It reopens as the recording with its trim and cut live, and with its sound, as Export keeps it.
        let reopened = try #require(VersionWriter.project(of: output, in: store))
        #expect(reopened.original.resolvingSymlinksInPath() == video.resolvingSymlinksInPath())
        let trim = try #require(reopened.project.trimEdit)
        #expect(abs(trim.range.start - 1) < 0.01 && abs(trim.range.end - 4.5) < 0.01)
        #expect(trim.cuts.cuts.count == 1 && abs((trim.cuts.cuts.first?.lowerBound ?? 0) - 2) < 0.01)
        #expect(reopened.project.tracks.contains { $0.kind == .audio })
        #expect(store.entry(for: output)?.origin.action == "edit")

        let fast = try await edit(video, VideoEdit(cut: [[0, 2]], speed: 2))
        #expect(abs((fast["duration"]?.number ?? 0) - 2) < 0.1)
    }

    @Test func cropAndTimedMarksAreDrawnAndReopenLive() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
        let video = folder.appendingPathComponent("rec.mp4")
        // Green, with its top-left quarter, 80 × 60, red.
        try await writeSolidVideo(to: video, color: .green, corner: .red, size: CGSize(width: 320, height: 240), seconds: 2)
        let box = CaptureMark(type: "rectangle", rect: [100, 70, 40, 30], fill: "#0000FF")
        let spec = VideoEdit(crop: [0, 0, 160, 120], marks: [VideoEdit.TimedMark(start: 0.5, end: 1.5, mark: box)])

        let result = try await edit(video, spec, projects: store)
        let output = try path(result)
        #expect(result["size"] == .object(["width": .number(160), "height": .number(120)]))
        #expect(try await pixel(in: output, at: 0.2, x: 0.1, y: 0.1).isNear(.red))
        #expect(try await pixel(in: output, at: 0.2, x: 0.9, y: 0.9).isNear(.green))
        // The box is drawn where it was in the recording's pixels, and only while it shows.
        #expect(try await pixel(in: output, at: 0.2, x: 0.75, y: 0.71).isNear(.green))
        #expect(try await pixel(in: output, at: 1.0, x: 0.75, y: 0.71).isNear(.blue))

        // Reopened, it's the same edit: the cropped canvas, the clip moved and scaled within it, and the mark.
        let reopened = try #require(VersionWriter.project(of: output, in: store)).project
        let media = try await MediaProbe.probe(video)
        let expected = try Project(source: video, duration: media.duration, canvasSize: try #require(media.size), hasAudio: media.hasAudio).applying(spec)
        #expect(reopened.canvasSize == CGSize(width: 160, height: 120))
        #expect(reopened.main.clips.map(\.transform) == expected.main.clips.map(\.transform))
        let mark = try #require(reopened.annotationClips.first)
        #expect(abs(mark.start - 0.5) < 0.01 && abs(mark.duration - 1) < 0.01)
        #expect(mark.annotation.kind == .shape(.rectangle, rect: CGRect(x: 100, y: 70, width: 40, height: 30)))
    }

    @Test func appendedVideosPlayAfterIt() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("a.mp4"), second = folder.appendingPathComponent("b.mp4")
        try await writeSolidVideo(to: first, color: .red, size: CGSize(width: 160, height: 120), seconds: 1)
        try await writeSolidVideo(to: second, color: .blue, size: CGSize(width: 160, height: 120), seconds: 1)

        let result = try await edit(first, VideoEdit(append: [second.path]))
        let output = try path(result)
        #expect(abs((result["duration"]?.number ?? 0) - 2) < 0.1)
        #expect(try await pixel(in: output, at: 0.5, x: 0.5, y: 0.5).isNear(.red))
        #expect(try await pixel(in: output, at: 1.5, x: 0.5, y: 0.5).isNear(.blue))
    }

    @Test func maxBytesStepsAGIFDownUntilItFits() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("rec.mp4")
        try await writeSyntheticVideo(to: video, seconds: 2, fps: 30, width: 640, height: 360)

        let full = try await edit(video, VideoEdit(format: .gif))
        let fullBytes = try #require(full["bytes"]?.number)
        #expect(full["fps"] == .number(12))
        #expect(full["size"]?["width"] == .number(640))

        let limit = max(VideoEdit.minimumBytes, Int(fullBytes / 3))
        let fitted = try await edit(video, VideoEdit(format: .gif, maxBytes: limit))
        #expect(try #require(fitted["bytes"]?.number) <= Double(limit))
        #expect((fitted["fps"]?.number ?? 12) < 12 || (fitted["size"]?["width"]?.number ?? 640) < 640)
    }

    @Test func maxBytesDrawsAnMP4SmallerUntilItFits() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("rec.mp4")
        try await writeNoiseVideo(to: video, size: CGSize(width: 1280, height: 800), seconds: 1)
        let whole = Int(try #require(video.resourceValues(forKeys: [.fileSizeKey]).fileSize))

        let limit = whole / 3
        #expect(limit > VideoEdit.minimumBytes)
        let fitted = try await edit(video, VideoEdit(mute: true, maxBytes: limit))
        #expect(try #require(fitted["bytes"]?.number) <= Double(limit))
        #expect((fitted["scale"]?.number ?? 1) < 1)
        #expect((fitted["size"]?["width"]?.number ?? 1280) < 1280)
    }

    @Test func whatTheEditorsExportCantDoIsRefusedNamingTheField() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("rec.mp4")
        try await writeSolidVideo(to: video, color: .green, size: CGSize(width: 160, height: 120), seconds: 2)
        let arrow = CaptureMark(type: "arrow", from: [10, 10], to: [50, 50])

        #expect(await failure(video, VideoEdit(speed: 2, marks: [VideoEdit.TimedMark(start: 0, end: 1, mark: arrow)]))?.message.hasPrefix("speed changes only a GIF") == true)
        #expect(await failure(video, VideoEdit(cut: [[3, 4]])) == .data("cut[0] starts at 3 s, past the end of the 2.00 s video"))
        #expect(await failure(video, VideoEdit(keep: [[0, 0.05]])) == .data("keep leaves less than 0.1 s of the video"))
        #expect(await failure(video, VideoEdit(marks: [VideoEdit.TimedMark(start: 5, end: 6, mark: arrow)])) == .data("marks[0].start is 5 s, past the end of the 2.00 s video"))
        let missing = folder.appendingPathComponent("gone.mp4").path
        #expect(await failure(video, VideoEdit(append: [missing])) == .noInput("append[0]: \(missing) doesn't exist"))
        let gif = folder.appendingPathComponent("out.gif").path
        #expect(await failure(video, VideoEdit(format: .mp4), output: gif) == .usage("edit", "-o \(gif) isn't a .mp4, the format the edit asks for"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["rec.mp4"])
    }

    @Test func anEditReadFromJSONIsAVideosForAVideo() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("rec.mp4")
        try await writeSolidVideo(to: video, color: .green, size: CGSize(width: 160, height: 120), seconds: 2)

        let result = try await ShotCommands.run(.edit(.init(input: video.path, spec: .json(#"{"cut": [[0, 1]], "mute": true}"#))))
        #expect(abs((result["duration"]?.number ?? 0) - 1) < 0.1)
        do {
            _ = try await ShotCommands.run(.edit(.init(input: video.path, spec: .json(#"{"pad": 4}"#))))
            Issue.record("an image's edit was made on a video")
        } catch {
            #expect(error.message.hasPrefix(#"unknown field "pad"; a video edit takes"#))
        }
    }
}
