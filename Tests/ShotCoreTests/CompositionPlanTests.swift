import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let recording = URL(fileURLWithPath: "/tmp/recording.mov")
private let canvas = CGSize(width: 1920, height: 1080)

private func project() -> Project {
    Project(source: recording, duration: 10, canvasSize: canvas, hasAudio: true)
}

private func overlay(duration: Double = 4, size: CGSize = CGSize(width: 640, height: 360)) -> ImportedMedia {
    ImportedMedia(source: URL(fileURLWithPath: "/tmp/overlay.mov"), duration: duration, size: size, hasAudio: false)
}

@Test func aLoneRecordingIsOneSegment() {
    let project = project()
    #expect(project.videoSegments() == [VideoSegment(range: 0..<10, clips: [project.main.clips[0].id])])
}

@Test func anOverlaySplitsTheTimelineIntoBeforeDuringAfter() throws {
    let (imported, id) = try #require(project().importing(overlay(), at: 3))
    let main = imported.main.clips[0].id
    #expect(imported.videoSegments() == [
        VideoSegment(range: 0..<3, clips: [main]),
        VideoSegment(range: 3..<7, clips: [main, id]),
        VideoSegment(range: 7..<10, clips: [main]),
    ])
}

@Test func anOverlayPastTheEndLeavesAGapOfBackground() throws {
    let (imported, id) = try #require(project().importing(overlay(), at: 12))
    let segments = imported.videoSegments()
    #expect(segments.map(\.range) == [0..<10, 10..<12, 12..<16])
    #expect(segments[1].clips.isEmpty)
    #expect(segments[2].clips == [id])
}

@Test func laterTracksDrawOnTop() throws {
    let (first, a) = try #require(project().importing(overlay(), at: 0))
    let (second, b) = try #require(first.importing(overlay(), at: 0))
    #expect(second.videoSegments()[0].clips == [second.main.clips[0].id, a, b])
}

@Test func hiddenTracksDontDraw() throws {
    var (imported, _) = try #require(project().importing(overlay(), at: 3))
    imported.tracks[2].isHidden = true
    #expect(imported.videoSegments().count == 1)
}

@Test func soundAloneDoesntSplitTheVideo() throws {
    let music = ImportedMedia(source: URL(fileURLWithPath: "/tmp/m.m4a"), duration: 30, size: nil, hasAudio: true)
    let (imported, _) = try #require(project().importing(music, at: 0))
    #expect(imported.videoSegments().count == 2, "the picture runs out at 10 and the rest is background")
    #expect(imported.videoSegments()[1].clips.isEmpty)
}

@Test func fittedAtRestFillsTheCanvasWidthOfAWideClip() {
    let clip = Clip(source: recording, sourceDuration: 1, size: CGSize(width: 640, height: 360))
    #expect(LayerGeometry.frame(of: clip, canvas: canvas) == CGRect(x: 0, y: 0, width: 1920, height: 1080))
}

@Test func aTallClipIsFittedByHeightAndCentred() {
    let clip = Clip(source: recording, sourceDuration: 1, size: CGSize(width: 360, height: 640))
    let frame = LayerGeometry.frame(of: clip, canvas: canvas)
    #expect(abs(frame.height - 1080) < 1e-9 && abs(frame.width - 607.5) < 1e-9)
    #expect(abs(frame.midX - 960) < 1e-9 && abs(frame.midY - 540) < 1e-9)
}

@Test func scaleAndOffsetMoveTheFrame() {
    var clip = Clip(source: recording, sourceDuration: 1, size: CGSize(width: 640, height: 360))
    clip.transform = ClipTransform(offset: CGSize(width: 100, height: -50), scale: 0.5)
    let frame = LayerGeometry.frame(of: clip, canvas: canvas)
    #expect(abs(frame.width - 960) < 1e-9 && abs(frame.height - 540) < 1e-9)
    #expect(abs(frame.midX - 1060) < 1e-9 && abs(frame.midY - 490) < 1e-9)
}

@Test func aQuarterTurnSwapsTheFrameSides() {
    var clip = Clip(source: recording, sourceDuration: 1, size: CGSize(width: 640, height: 360))
    clip.transform = ClipTransform(scale: 0.5, rotation: .pi / 2)
    let frame = LayerGeometry.frame(of: clip, canvas: canvas)
    #expect(abs(frame.width - 540) < 1e-6 && abs(frame.height - 960) < 1e-6)
    #expect(abs(frame.midX - 960) < 1e-6 && abs(frame.midY - 540) < 1e-6)
}

@Test func aClipWithNoPictureHasNoGeometry() {
    #expect(LayerGeometry.transform(for: Clip(source: recording, sourceDuration: 1), canvas: canvas) == .identity)
}

@Test func theImageTransformPutsTheTopLeftOfTheSourceAtTheTopLeftOfItsFrame() {
    // A 100 × 50 source, shown at half scale in the top left of a 200 × 100 canvas: in y-up terms the
    // source's top-left corner is (0, 50) and should land at (0, 100) of the canvas.
    let geometry = CGAffineTransform(scaleX: 0.5, y: 0.5)
    let matrix = LayerGeometry.imageTransform(orientation: .identity, geometry: geometry, sourceHeight: 50, canvasHeight: 100)
    let topLeft = CGPoint(x: 0, y: 50).applying(matrix)
    let bottomRight = CGPoint(x: 100, y: 0).applying(matrix)
    #expect(abs(topLeft.x) < 1e-9 && abs(topLeft.y - 100) < 1e-9)
    #expect(abs(bottomRight.x - 50) < 1e-9 && abs(bottomRight.y - 75) < 1e-9)
}
