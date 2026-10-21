import Foundation
import Testing
@testable import ShotCore

private func layoutProject() throws -> Project {
    let base = Project(source: URL(fileURLWithPath: "/tmp/a.mov"), duration: 10, canvasSize: CGSize(width: 640, height: 360), hasAudio: true)
    let picture = ImportedMedia(source: URL(fileURLWithPath: "/tmp/b.mov"), duration: 2, size: CGSize(width: 64, height: 36), hasAudio: true)
    let first = try #require(base.importing(picture, at: 0)).project
    return try #require(first.importing(picture, at: 4)).project
}

@Test func lanesStackPicturesAboveTheMainTrackAndSoundBelow() throws {
    let project = try layoutProject()
    // Tracks: 0 main, 1 its sound, 2 picture, 3 sound, 4 picture, 5 sound.
    let layout = LaneLayout(project, top: 22)
    #expect(layout.lanes.map(\.track) == [4, 2, 0, 1, 3, 5])
    #expect(layout.lanes.map(\.y) == [22, 66, 110, 170, 214, 258])
    #expect(layout.height == 298)
}

@Test func aLoneRecordingHasTheMainLaneAndItsSound() {
    let project = Project(source: URL(fileURLWithPath: "/tmp/a.mov"), duration: 10, canvasSize: CGSize(width: 640, height: 360), hasAudio: true)
    let layout = LaneLayout(project, top: 22)
    #expect(layout.lanes.map(\.track) == [0, 1])
    #expect(layout.height == 122)
}

@Test func lanesAreFoundByPositionAndTrack() throws {
    let layout = LaneLayout(try layoutProject(), top: 22)
    #expect(layout.lane(at: 100)?.track == 2)
    #expect(layout.lane(at: 65) == nil, "the gap between lanes")
    #expect(layout.lane(at: 5) == nil, "the ruler")
    #expect(layout.lane(ofTrack: 0)?.y == 110)
    #expect(layout.lane(ofTrack: 9) == nil)
}

@Test func aNewAnnotationLaneSitsAboveEverything() throws {
    let base = try layoutProject()
    let annotated = base.adding(annotation: Annotation(kind: .line(from: .zero, to: CGPoint(x: 5, y: 5)), color: RGBA.presets[0], lineWidth: 2), at: 1).project
    let layout = LaneLayout(annotated, top: 22)
    #expect(layout.lanes.first?.track == 6)
    #expect(layout.lanes.first?.height == 28)
    #expect(layout.lanes.map(\.track) == [6, 4, 2, 0, 1, 3, 5])
    #expect(layout.lanes[1].y == 54)
}

@Test func lanesScrollRatherThanSqueezeThePreview() throws {
    let layout = LaneLayout(try layoutProject(), top: 22)
    #expect(layout.visibleHeight(available: 1000, minimum: 78) == layout.height, "room to spare")
    #expect(layout.visibleHeight(available: 150, minimum: 78) == 150)
    #expect(layout.visibleHeight(available: 20, minimum: 78) == 78, "the ruler and the main lane stay in view")
}

@Test func aClipsNameStartsPastTheLaneSwitchesOverIt() {
    // Lock and hide: 4 in, two 20 pt buttons 3 apart.
    #expect(LaneLayout.controlsWidth(count: 2) == 47)
    #expect(LaneLayout.controlsWidth(count: 1) == 24)
    #expect(LaneLayout.controlsWidth(count: 0) == 0)
    #expect(LaneLayout.labelInset(clipX: 0, controlsEnd: 47) == 47, "a clip at 0:00")
    #expect(LaneLayout.labelInset(clipX: 30, controlsEnd: 47) == 17)
    #expect(LaneLayout.labelInset(clipX: 60, controlsEnd: 47) == 0, "clear of the switches")
    #expect(LaneLayout.labelInset(clipX: 0, controlsEnd: 0) == 0, "no switches showing")
    #expect(LaneLayout.labelInset(clipX: -100, controlsEnd: 47) == 147, "scrolled past its start")
}

@Test func trimmedEndsShowTheWholeRecordingAroundWhatsKept() throws {
    let full = Project(source: URL(fileURLWithPath: "/tmp/recording.mov"), duration: 10, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: true)
    #expect(full.trimmedLead == 0 && full.trimmedEnds(ofTrack: 0).isEmpty)
    let trimmed = try #require(full.trimmingMain(.start, toSource: 2)?.trimmingMain(.end, toSource: 9))
    #expect(trimmed.trimmedLead == 2)
    let ends = trimmed.trimmedEnds(ofTrack: 0)
    #expect(ends.map(\.start) == [-2, 7] && ends.map(\.sourceStart) == [0, 9] && ends.map(\.sourceEnd) == [2, 10])
    #expect(trimmed.trimmedEnds(ofTrack: 1).map(\.start) == [-2, 7])
}

@Test func aCutInsideTheMainTrackIsMarkedNotDrawn() throws {
    let full = Project(source: URL(fileURLWithPath: "/tmp/recording.mov"), duration: 10, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: false)
    let cut = try #require(full.deleting(range: 3..<5))
    #expect(cut.mainCuts == [3])
    #expect(cut.trimmedEnds(ofTrack: 0).isEmpty)
    let split = try #require(full.splitting(at: 4))
    #expect(split.mainCuts.isEmpty)
}

@Test func anImportedClipShowsWhatWasTrimmedOffBothEnds() throws {
    let music = ImportedMedia(source: URL(fileURLWithPath: "/tmp/music.m4a"), duration: 30, size: nil, hasAudio: true)
    let base = Project(source: URL(fileURLWithPath: "/tmp/recording.mov"), duration: 10, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: false)
    let (imported, id) = try #require(base.importing(music, at: 4))
    let trimmed = try #require(imported.trimming(clip: id, .start, toTimeline: 6)?.trimming(clip: id, .end, toTimeline: 20))
    // 2 s off the front and 14 s off the back, drawn either side of the 6–20 s it plays.
    #expect(trimmed.trimmedEnds(ofTrack: 1).map(\.start) == [4, 20] && trimmed.trimmedEnds(ofTrack: 1).map(\.length) == [2, 14])
}
