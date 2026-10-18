import Foundation
import Testing
@testable import ShotCore

private let recording = URL(fileURLWithPath: "/tmp/recording.mov")
private let overlay = ImportedMedia(source: URL(fileURLWithPath: "/tmp/overlay.mov"), duration: 4, size: CGSize(width: 640, height: 360), hasAudio: true)
private let music = ImportedMedia(source: URL(fileURLWithPath: "/tmp/music.m4a"), duration: 30, size: nil, hasAudio: true)

private func project() -> Project {
    Project(source: recording, duration: 10, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: true)
}

@Test func importingVideoAddsAPictureTrackAboveAndASoundTrackAlongside() throws {
    let (imported, id) = try #require(project().importing(overlay, at: 3))
    #expect(imported.tracks.map(\.kind) == [.video, .audio, .video, .audio])
    let picture = try #require(imported.clip(id))
    #expect(picture.start == 3 && picture.length == 4 && picture.size == CGSize(width: 640, height: 360))
    let sound = try #require(imported.tracks[3].clips.first)
    #expect(picture.linkedID == sound.id && sound.linkedID == picture.id && sound.start == 3)
    #expect(imported.duration == 10)
}

@Test func importingPastTheEndExtendsTheProject() throws {
    let (imported, _) = try #require(project().importing(overlay, at: 8))
    #expect(imported.duration == 12)
}

@Test func importingSoundAloneMakesOneAudioTrackAndCanOutlastTheVideo() throws {
    let (imported, id) = try #require(project().importing(music, at: 0))
    #expect(imported.tracks.map(\.kind) == [.video, .audio, .audio])
    #expect(imported.clip(id)?.linkedID == nil)
    #expect(imported.duration == 30)
}

@Test func aSilentPictureHasNoSoundClip() throws {
    var silent = overlay
    silent.hasAudio = false
    let (imported, _) = try #require(project().importing(silent, at: 0))
    #expect(imported.tracks.map(\.kind) == [.video, .audio, .video])
}

@Test func importingNegativeStartClampsToZeroAndEmptyMediaIsRefused() throws {
    let (imported, id) = try #require(project().importing(overlay, at: -5))
    #expect(imported.clip(id)?.start == 0)
    var empty = overlay
    empty.duration = 0
    #expect(project().importing(empty, at: 0) == nil)
    #expect(project().importing(ImportedMedia(source: recording, duration: 3, size: nil, hasAudio: false), at: 0) == nil)
}

@Test func appendingGoesAfterTheMainTrackWithItsSoundAfterTheRecordings() throws {
    let (appended, id) = try #require(project().appending(overlay))
    #expect(appended.main.clips.map(\.start) == [0, 10])
    #expect(appended.tracks.count == 2, "the sound joins the recording's own audio track")
    #expect(appended.tracks[1].clips.map(\.start) == [0, 10])
    #expect(appended.clip(id)?.linkedID == appended.tracks[1].clips[1].id)
    #expect(appended.duration == 14)
    #expect(appended.trimEdit == nil)
}

@Test func appendingARecordingWithoutAudioToOneWithItLeavesTheAudioTrackShort() throws {
    var silent = overlay
    silent.hasAudio = false
    let (appended, _) = try #require(project().appending(silent))
    #expect(appended.tracks[1].clips.count == 1)
    #expect(appended.duration == 14)
}

@Test func soundAloneCantBeAppendedToTheMainTrack() {
    #expect(project().appending(music) == nil)
}

@Test func movingAClipMovesItsSoundToo() throws {
    let (imported, id) = try #require(project().importing(overlay, at: 1))
    let moved = try #require(imported.moving(clip: id, toStart: 5))
    #expect(moved.clip(id)?.start == 5)
    #expect(moved.tracks[3].clips[0].start == 5)
}

@Test func theMainTrackAndTheOriginalSoundStayPut() throws {
    let project = project()
    #expect(project.moving(clip: project.main.clips[0].id, toStart: 3) == nil)
    #expect(project.moving(clip: project.tracks[1].clips[0].id, toStart: 3) == nil, "it's linked to a main clip")
}

@Test func movingStopsAtZeroAndAtNeighbours() throws {
    var (imported, id) = try #require(project().importing(overlay, at: 6))
    imported.tracks[2].clips.append(Clip(source: recording, sourceDuration: 2, start: 1, size: .zero))
    // The second clip sits at 1...3 on the same track, so the first can't go below 3 or pass it.
    let left = try #require(imported.moving(clip: id, toStart: 0))
    #expect(left.clip(id)?.start == 3)
    let negative = try #require(imported.moving(clip: id, toStart: -10))
    #expect(negative.clip(id)?.start == 3)
}

@Test func movingSnapsItsStartOrEndToAnEdge() throws {
    let (imported, id) = try #require(project().importing(overlay, at: 1))
    // Its end, at start + 4, is within reach of the recording's end at 10.
    let snapped = try #require(imported.moving(clip: id, toStart: 5.95, snapWithin: 0.1)).clip(id)
    #expect(abs((snapped?.end ?? 0) - 10) < 1e-9)
    let free = try #require(imported.moving(clip: id, toStart: 2.4, snapWithin: 0.1)).clip(id)
    #expect(free?.start == 2.4)
    let toStart = try #require(imported.moving(clip: id, toStart: 0.05, snapWithin: 0.1)).clip(id)
    #expect(toStart?.start == 0)
}

@Test func trimmingTheStartMovesTheStartAndTheSourceTogether() throws {
    let (imported, id) = try #require(project().importing(overlay, at: 2))
    let trimmed = try #require(imported.trimming(clip: id, .start, toTimeline: 3))
    let clip = try #require(trimmed.clip(id))
    #expect(clip.start == 3 && clip.sourceStart == 1 && clip.end == 6)
    let sound = trimmed.tracks[3].clips[0]
    #expect(sound.start == 3 && sound.sourceStart == 1 && sound.end == 6)
}

@Test func trimmingCantGoPastTheSourceOrTheMinimumLength() throws {
    let (imported, id) = try #require(project().importing(overlay, at: 2))
    #expect(imported.trimming(clip: id, .start, toTimeline: -5)?.clip(id)?.start == 2, "already at the start of the source")
    #expect(imported.trimming(clip: id, .end, toTimeline: 99)?.clip(id)?.end == 6, "already at the end of the source")
    let tiny = try #require(imported.trimming(clip: id, .end, toTimeline: 2.01))
    #expect(abs((tiny.clip(id)?.length ?? 0) - TrimRange.minimumLength) < 1e-9)
}

@Test func trimmedEdgesCanBeDraggedBackOut() throws {
    let (imported, id) = try #require(project().importing(overlay, at: 2))
    let short = try #require(imported.trimming(clip: id, .end, toTimeline: 4))
    let long = try #require(short.trimming(clip: id, .end, toTimeline: 5.5))
    #expect(long.clip(id)?.end == 5.5)
}

@Test func trimmingStopsAtANeighbour() throws {
    var (imported, id) = try #require(project().importing(overlay, at: 2))
    imported.tracks[2].clips.append(Clip(source: recording, sourceDuration: 5, start: 7, size: .zero))
    let trimmed = try #require(imported.trimming(clip: id, .end, toTimeline: 6))
    #expect(trimmed.clip(id)?.end == 6)
    let shortened = try #require(imported.trimming(clip: id, .end, toTimeline: 3))
    let grown = try #require(shortened.trimming(clip: id, .end, toTimeline: 20))
    #expect(grown.clip(id)?.end == 6, "the source ends there")
}

@Test func mainClipsCantBeTrimmedThisWay() {
    let project = project()
    #expect(project.trimming(clip: project.main.clips[0].id, .end, toTimeline: 5) == nil)
}

@Test func deletingAnImportRemovesItsSoundAndTheEmptyTracks() throws {
    let (imported, id) = try #require(project().importing(overlay, at: 2))
    let deleted = try #require(imported.deleting(clip: id))
    #expect(deleted.tracks.map(\.kind) == [.video, .audio])
    #expect(deleted.trimEdit != nil)
}

@Test func deletingAnImportsSoundRemovesItsPictureToo() throws {
    let (imported, _) = try #require(project().importing(overlay, at: 2))
    let deleted = try #require(imported.deleting(clip: imported.tracks[3].clips[0].id))
    #expect(deleted.tracks.map(\.kind) == [.video, .audio])
}

@Test func theRecordingsOwnSoundCantBeDeleted() {
    let project = project()
    #expect(project.deleting(clip: project.tracks[1].clips[0].id) == nil)
}

@Test func changingATransformOrVolumeMakesItNoLongerATrimEdit() throws {
    let project = project()
    let id = project.main.clips[0].id
    #expect(project.trimEdit != nil)
    let moved = try #require(project.setting(transform: ClipTransform(scale: 0.5), of: id))
    #expect(moved.trimEdit == nil)
    let quiet = try #require(project.setting(volume: 0.5, of: project.tracks[1].clips[0].id))
    #expect(quiet.trimEdit == nil)
    #expect(project.setting(volume: 9, of: id)?.clip(id)?.volume == 2)
    #expect(project.setting(transform: .identity, of: UUID()) == nil)
}

@Test func movingAndTrimmingSnapToExtraPointsLikeThePlayhead() throws {
    let (imported, id) = try #require(project().importing(overlay, at: 1))
    let moved = try #require(imported.moving(clip: id, toStart: 2.95, snapWithin: 0.1, snapTo: [3]))
    #expect(moved.clip(id)?.start == 3)
    let trimmed = try #require(imported.trimming(clip: id, .end, toTimeline: 4.05, snapWithin: 0.1, snapTo: [4]))
    #expect(trimmed.clip(id)?.end == 4)
    let free = try #require(imported.trimming(clip: id, .end, toTimeline: 4.5, snapWithin: 0.1, snapTo: [4]))
    #expect(free.clip(id)?.end == 4.5)
}

@Test func mainTrimHandlesStayWithinTheEdgeClipWhenSeveralFilesAreJoined() throws {
    let (appended, _) = try #require(project().appending(overlay))
    // Main track: recording 0..<10 then the overlay's 4 s at 10..<14.
    let start = try #require(appended.trimmingMain(.start, toSource: 3))
    #expect(start.main.clips.map(\.start) == [0, 7] && start.main.clips[0].sourceStart == 3)
    // 9 would be past the first clip's end in the second file's time, which has nothing to do with it.
    let far = try #require(appended.trimmingMain(.start, toSource: 11))
    #expect(far.main.clips.count == 1, "the first clip is gone, no further")
    let end = try #require(appended.trimmingMain(.end, toSource: 2))
    #expect(end.main.clips.count == 2 && abs(end.main.clips[1].length - 2) < 1e-9)
}
