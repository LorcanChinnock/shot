import AVFoundation
import Foundation
import Testing
@testable import ShotCore

private let canvas = CGSize(width: 640, height: 360)

private func temp(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
}

/// A red recording whose top-left quarter, 160 × 90, is blue.
private func writeMarkedRecording(to url: URL) async throws {
    try await writeSolidVideo(to: url, color: .red, corner: .blue, size: canvas, seconds: 1)
}

extension MediaTests {
    @Test func aFrameCropExportsAtTheCroppedSizeWithNothingMoved() async throws {
        let source = temp("source.mp4"), output = temp("out.mp4")
        defer { [source, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeMarkedRecording(to: source)
        let crop = CGRect(x: 80, y: 45, width: 400, height: 226)
        let project = Project(source: source, duration: 1, canvasSize: canvas, hasAudio: false).setting(frameCrop: crop)
        try await ProjectExporter.export(project, to: output)

        let track = try #require(try await AVURLAsset(url: output).loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 400, height: 226))
        // Canvas point (120, 60) is in the blue quarter and (300, 200) isn't, wherever the crop puts them.
        #expect(try await pixel(in: output, at: 0.5, x: (120 - 80) / 400, y: (60 - 45) / 226.0).isNear(.blue), "the blue quarter stays where it was")
        #expect(try await pixel(in: output, at: 0.5, x: (300 - 80) / 400, y: (200 - 45) / 226.0).isNear(.red))
        #expect(try await pixel(in: output, at: 0.5, x: (200 - 80) / 400, y: (60 - 45) / 226.0).isNear(.red), "just right of the quarter")
    }

    @Test func aSquareFrameCropExportsASquareVideo() async throws {
        let source = temp("source.mp4"), output = temp("out.mp4")
        defer { [source, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeMarkedRecording(to: source)
        let project = Project(source: source, duration: 1, canvasSize: canvas, hasAudio: false).setting(frameCrop: CGRect(x: 140, y: 0, width: 360, height: 360))
        try await ProjectExporter.export(project, to: output)

        let track = try #require(try await AVURLAsset(url: output).loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 360, height: 360))
    }

    @Test func aGIFOfAFrameCroppedVideoIsTheCroppedSize() async throws {
        let source = temp("source.mp4"), gif = temp("out.gif")
        defer { [source, gif].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeMarkedRecording(to: source)
        let project = Project(source: source, duration: 1, canvasSize: canvas, hasAudio: false).setting(frameCrop: CGRect(x: 0, y: 0, width: 320, height: 200))
        let composition = try await CompositionBuilder.build(project)
        try await GIFExporter.export(composition: composition, to: gif, fps: 5, maxWidth: nil)

        let image = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(image.width == 320 && image.height == 200)
    }

    @Test func aClipCropMasksThePictureWhereItIs() async throws {
        let source = temp("source.mp4"), output = temp("out.mp4")
        defer { [source, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeMarkedRecording(to: source)
        let plain = Project(source: source, duration: 1, canvasSize: canvas, hasAudio: false)
        let id = plain.main.clips[0].id
        // Only the blue quarter is left.
        let project = try #require(plain.setting(crop: ImageCrop(left: 0, top: 0, right: 0.75, bottom: 0.75), of: id))
        try await ProjectExporter.export(project, to: output)

        let track = try #require(try await AVURLAsset(url: output).loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == canvas, "a clip crop leaves the frame alone")
        #expect(try await pixel(in: output, at: 0.5, x: 0.1, y: 0.1).isNear(.blue), "what's left stays where it was")
        #expect(try await pixel(in: output, at: 0.5, x: 0.6, y: 0.6).isNear(.black), "what's cropped off shows the background")
    }

    @Test func aClipIsCroppedBeforeItsTransform() async throws {
        let source = temp("source.mp4"), output = temp("out.mp4")
        defer { [source, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeMarkedRecording(to: source)
        let plain = Project(source: source, duration: 1, canvasSize: canvas, hasAudio: false)
        let id = plain.main.clips[0].id
        let cropped = try #require(plain.setting(crop: ImageCrop(left: 0, top: 0, right: 0.75, bottom: 0.75), of: id))
        // Turned half round about the whole picture's centre, the quarter that's left lands in the bottom right.
        let project = try #require(cropped.setting(transform: ClipTransform(rotation: .pi), of: id))
        try await ProjectExporter.export(project, to: output)

        #expect(try await pixel(in: output, at: 0.5, x: 0.875, y: 0.875).isNear(.blue))
        #expect(try await pixel(in: output, at: 0.5, x: 0.1, y: 0.1).isNear(.black))
        #expect(try await pixel(in: output, at: 0.5, x: 0.5, y: 0.5).isNear(.black))
    }

    @Test func aCroppedClipsBorderFollowsTheCroppedEdge() async throws {
        let source = temp("source.mp4"), output = temp("out.mp4")
        defer { [source, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeMarkedRecording(to: source)
        let plain = Project(source: source, duration: 1, canvasSize: canvas, hasAudio: false)
        let id = plain.main.clips[0].id
        let cropped = try #require(plain.setting(crop: ImageCrop(left: 0, top: 0, right: 0.75, bottom: 0.75), of: id))
        let project = try #require(cropped.setting(style: ObjectStyle(border: Border(kind: .solid, lineWidth: 12, color: RGBA(0, 1, 0))), of: id))
        try await ProjectExporter.export(project, to: output)

        // The quarter ends at x = 160, so a 12-pixel border runs from there to 172.
        let border = try await pixel(in: output, at: 0.5, x: 166 / 640.0, y: 40 / 360.0)
        #expect(border.g > 150 && border.r < 100 && border.b < 100, "the border is at the cropped edge")
        #expect(try await pixel(in: output, at: 0.5, x: 0.6, y: 0.6).isNear(.black))
    }
}

@Test func aProjectWithBothCropsRoundTripsAndOlderProjectsStillOpen() throws {
    var project = Project(source: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 2, canvasSize: canvas, hasAudio: true).setting(frameCrop: CGRect(x: 0, y: 30, width: 640, height: 330))
    project = try #require(project.setting(crop: ImageCrop(left: 0.1, top: 0, right: 0.2, bottom: 0.3), of: project.main.clips[0].id))
    let data = try JSONEncoder().encode(project)
    let decoded = try JSONDecoder().decode(Project.self, from: data)
    #expect(decoded == project)
    #expect(decoded.frameCrop == CGRect(x: 0, y: 30, width: 640, height: 330))
    #expect(decoded.main.clips[0].crop == ImageCrop(left: 0.1, top: 0, right: 0.2, bottom: 0.3))

    // A project saved before crops has neither key.
    let plain = Project(source: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 2, canvasSize: canvas, hasAudio: true)
    let old = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(plain))
    #expect(old.frameCrop == nil && old.main.clips[0].crop == nil)
    #expect(!String(decoding: try JSONEncoder().encode(plain), as: UTF8.self).contains("Crop"))
}

@Test func aCroppedVideoIsNoLongerOnlyATrim() throws {
    let plain = Project(source: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 2, canvasSize: canvas, hasAudio: false)
    #expect(plain.trimEdit != nil)
    #expect(plain.setting(frameCrop: CGRect(x: 0, y: 0, width: 320, height: 180)).trimEdit == nil)
    #expect(try #require(plain.setting(crop: ImageCrop(left: 0.5, top: 0, right: 0, bottom: 0), of: plain.main.clips[0].id)).trimEdit == nil)
    #expect(plain.setting(frameCrop: CGRect(origin: .zero, size: canvas)).trimEdit != nil, "a crop of everything is none")
}

@Test func theFrameCropSetsTheOutputAndLeavesTheCanvas() {
    let project = Project(source: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 2, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: false)
        .setting(frameCrop: CGRect(x: 160, y: 90, width: 1600, height: 900))
    #expect(project.canvasSize == CGSize(width: 1920, height: 1080))
    #expect(project.outputRect == CGRect(x: 160, y: 90, width: 1600, height: 900))
    #expect(ProjectExporter.estimatedSize(of: project) < ProjectExporter.estimatedSize(of: project.setting(frameCrop: nil)))
}

@Test func aCroppedClipsFrameIsThePartLeft() {
    var clip = Clip(source: URL(fileURLWithPath: "/tmp/a.mp4"), sourceDuration: 1, size: canvas)
    clip.crop = ImageCrop(left: 0.5, top: 0, right: 0, bottom: 0.5)
    #expect(LayerGeometry.frame(of: clip, canvas: canvas) == CGRect(x: 320, y: 0, width: 320, height: 180))
}
