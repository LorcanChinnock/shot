import Foundation
import Testing
@testable import ShotCore

private let recording = URL(fileURLWithPath: "/tmp/recording.mov")

private func project(duration: Double = 10, hasAudio: Bool = true) -> Project {
    Project(source: recording, duration: duration, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: hasAudio)
}

private func sections(_ track: Track) -> [Range<Double>] {
    track.clips.map { $0.sourceStart..<$0.sourceEnd }
}

@Test func openingARecordingMakesALinkedVideoAndAudioClip() throws {
    let project = project()
    #expect(project.tracks.map(\.kind) == [.video, .audio])
    #expect(project.duration == 10)
    let video = try #require(project.main.clips.first)
    let audio = try #require(project.tracks[1].clips.first)
    #expect(video.linkedID == audio.id && audio.linkedID == video.id)
    #expect(try #require(project.trimEdit).range.isFull(duration: 10))
}

@Test func aSilentRecordingHasNoAudioTrack() {
    #expect(project(hasAudio: false).tracks.map(\.kind) == [.video])
}

@Test func splittingCutsClipsOnEveryTrackAndRelinksTheHalves() throws {
    let split = try #require(project().splitting(at: 4))
    #expect(sections(split.main) == [0..<4, 4..<10])
    #expect(split.main.clips.map(\.start) == [0, 4])
    #expect(sections(split.tracks[1]) == [0..<4, 4..<10])
    for (video, audio) in zip(split.main.clips, split.tracks[1].clips) {
        #expect(video.linkedID == audio.id && audio.linkedID == video.id)
    }
    #expect(split.main.clips[0].id != split.main.clips[1].id)
}

@Test func splittingAtAnEdgeOrOutsideDoesNothing() {
    let project = project()
    #expect(project.splitting(at: 0) == nil)
    #expect(project.splitting(at: 10) == nil)
    #expect(project.splitting(at: 12) == nil)
}

@Test func splittingSkipsLockedTracks() throws {
    var project = project()
    project.tracks[1].isLocked = true
    let split = try #require(project.splitting(at: 5))
    #expect(split.main.clips.count == 2)
    #expect(split.tracks[1].clips.count == 1)
    #expect(split.main.clips[1].linkedID == nil)
}

@Test func deletingARangeClosesTheGapAndShiftsTheLinkedAudio() throws {
    let cut = try #require(project().deleting(range: 2..<5))
    #expect(sections(cut.main) == [0..<2, 5..<10])
    #expect(cut.main.clips.map(\.start) == [0, 2])
    #expect(sections(cut.tracks[1]) == [0..<2, 5..<10])
    #expect(cut.tracks[1].clips.map(\.start) == [0, 2])
    #expect(cut.duration == 7)
}

@Test func deletingFromTheStartOrEndLeavesOneClip() throws {
    let head = try #require(project().deleting(range: 0..<3))
    #expect(sections(head.main) == [3..<10] && head.main.clips[0].start == 0)
    let tail = try #require(project().deleting(range: 8..<10))
    #expect(sections(tail.main) == [0..<8])
}

@Test func deletingEverythingButASliverIsRefused() {
    #expect(project().deleting(range: 0..<10) == nil)
    #expect(project().deleting(range: 0..<9.95) == nil)
}

@Test func deletingNothingKeepsTheProject() {
    let project = project()
    #expect(project.deleting(range: 3..<3) == project)
}

@Test func deletingLeavesUnlinkedTracksAlone() throws {
    var project = project()
    let music = Clip(source: URL(fileURLWithPath: "/tmp/music.m4a"), sourceDuration: 20, start: 1)
    project.tracks.append(Track(kind: .audio, clips: [music]))
    let cut = try #require(project.deleting(range: 2..<5))
    #expect(cut.tracks[2].clips == [music])
    #expect(cut.duration == 21)
}

@Test func theProjectIsAsLongAsItsLastClipEnds() {
    var project = project()
    #expect(project.duration == 10)
    project.tracks.append(Track(kind: .audio, clips: [Clip(source: recording, sourceDuration: 8, start: 9)]))
    #expect(project.duration == 17)
}

@Test func anEmptyProjectHasNoLength() {
    #expect(Project(source: recording, duration: 0, canvasSize: .zero, hasAudio: false).duration == 0)
}

@Test func aTrimmedAndCutProjectReducesToTheTrimAndCuts() throws {
    let headTrimmed = try #require(project().trimmingMain(.start, toSource: 1))
    let edited = try #require(headTrimmed.trimmingMain(.end, toSource: 9))
    let cut = try #require(edited.cutting(source: 3..<4))
    let edit = try #require(cut.trimEdit)
    #expect(edit.range == TrimRange(start: 1, end: 9, duration: 10))
    #expect(edit.cuts == CutList([3..<4]))
    #expect(edit.source == recording)
    #expect(cut.duration == 7)
}

@Test func aProjectWithAnImportIsNotATrimEdit() {
    var project = project()
    project.tracks.append(Track(kind: .audio, clips: [Clip(source: URL(fileURLWithPath: "/tmp/music.m4a"), sourceDuration: 5)]))
    #expect(project.trimEdit == nil)
}

@Test func aProjectWhoseAudioWasEditedOnItsOwnIsNotATrimEdit() throws {
    var project = try #require(project().splitting(at: 5))
    project.tracks[1].clips[1].sourceStart = 6
    #expect(project.trimEdit == nil)
}

@Test func draggingAHandleInTrimsAndOutRestoresFromTheOrigin() throws {
    let origin = project()
    let trimmed = try #require(origin.trimmingMain(.start, toSource: 4))
    #expect(sections(trimmed.main) == [4..<10])
    // Dragging from the same origin back past the start extends the clip to the start of the recording.
    let extended = try #require(origin.trimmingMain(.start, toSource: -3))
    #expect(extended == origin)
}

@Test func extendingATrimmedEdgeGrowsTheClipAndMovesLaterOnes() throws {
    let trimmed = try #require(project().trimmingMain(.start, toSource: 4))
    let extended = try #require(trimmed.trimmingMain(.start, toSource: 2))
    #expect(sections(extended.main) == [2..<10])
    #expect(sections(extended.tracks[1]) == [2..<10])
    #expect(extended.duration == 8)
    let shortEnd = try #require(project().trimmingMain(.end, toSource: 6))
    let longEnd = try #require(shortEnd.trimmingMain(.end, toSource: 20))
    #expect(sections(longEnd.main) == [0..<10], "the end stops at the end of the recording")
}

@Test func extendingAClipBeforeACutPushesTheRestLater() throws {
    var edited = try #require(project().trimmingMain(.start, toSource: 2))
    edited = try #require(edited.cutting(source: 5..<6))
    let extended = try #require(edited.trimmingMain(.start, toSource: 1))
    #expect(sections(extended.main) == [1..<5, 6..<10])
    #expect(extended.main.clips.map(\.start) == [0, 4])
    #expect(extended.tracks[1].clips.map(\.start) == [0, 4])
}

@Test func handlesStopWhereLessThanTheMinimumWouldBeLeft() throws {
    let cut = try #require(project().cutting(source: 0.5..<9.95))
    #expect(abs(cut.duration - 0.55) < 1e-9)
    // Clamped to leave 0.1 before the end, which the cut already leaves less than.
    #expect(cut.trimmingMain(.start, toSource: 9.9) == nil)
    #expect(cut.trimmingMain(.end, toSource: 0.2) != nil)
}

@Test func cuttingAnAlreadyCutOrOutsideSectionChangesNothing() throws {
    let cut = try #require(project().cutting(source: 3..<5))
    let again = try #require(cut.cutting(source: 3.5..<4.5))
    #expect(again == cut)
    let trimmed = try #require(project().trimmingMain(.start, toSource: 4))
    let outside = try #require(trimmed.cutting(source: 0..<3))
    #expect(outside == trimmed)
}

@Test func projectsRoundTripThroughJSON() throws {
    let edited = try #require(project().cutting(source: 2..<4))
    let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(edited))
    #expect(decoded == edited)
}

/// The project and the `TrimRange`/`CutList` model it replaced must keep the same sections after any run of edits.
/// Handle drags that pass over a cut, and cuts that reach the range's edge, are left out: trimming a clip away deletes the cut, where `CutList` kept it
/// to come back if the handle was dragged out again.
@Test func projectEditsMatchTheTrimRangeAndCutListModel() throws {
    var generator = SeededGenerator(seed: 7)
    for _ in 0..<300 {
        var edited = project(duration: 20)
        var range = TrimRange(duration: 20)
        var cuts = CutList()
        var log: [String] = []
        for _ in 0..<8 {
            let a = Double.random(in: 0...20, using: &generator).rounded(toPlaces: 2)
            let b = Double.random(in: 0...20, using: &generator).rounded(toPlaces: 2)
            switch Int.random(in: 0..<3, using: &generator) {
            case 0:
                // Handle drags start from the current state, as a new drag does.
                let moved = range.moving(.start, to: a, duration: 20)
                if cuts.allows(moved), !crosses(cuts, moved), let next = edited.trimmingMain(.start, toSource: a) {
                    range = moved
                    edited = next
                    log.append("start \(a)")
                }
            case 1:
                let moved = range.moving(.end, to: a, duration: 20)
                if cuts.allows(moved), !crosses(cuts, moved), let next = edited.trimmingMain(.end, toSource: a) {
                    range = moved
                    edited = next
                    log.append("end \(a)")
                }
            default:
                let selection = min(a, b)..<max(a, b)
                // A cut reaching an edge of the range is a trim, so it's left out like a drag across a cut.
                guard a != b, selection.lowerBound > range.start, selection.upperBound < range.end else { continue }
                if let next = cuts.cutting(selection, from: range), let project = edited.cutting(source: selection) {
                    cuts = next
                    edited = project
                    log.append("cut \(selection)")
                }
            }
            let edit = try #require(edited.trimEdit)
            let actual = edit.cuts.kept(in: edit.range).flatMap { [$0.start, $0.end] }
            let expected = cuts.kept(in: range).flatMap { [$0.start, $0.end] }
            #expect(actual.count == expected.count && zip(actual, expected).allSatisfy { abs($0 - $1) < 1e-6 }, "after \(range) \(cuts): \(actual) vs \(expected) \(log)")
        }
    }
}

private func crosses(_ cuts: CutList, _ range: TrimRange) -> Bool {
    cuts.cuts.contains { $0.lowerBound < range.start || $0.upperBound > range.end }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Test func deletingAMainClipClosesTheGap() throws {
    let split = try #require(project().splitting(at: 4))
    let middle = try #require(split.main.clips.last)
    let cut = try #require(split.deleting(clip: split.main.clips[0].id))
    #expect(cut.main.clips.map(\.id) == [middle.id])
    #expect(cut.main.clips[0].start == 0 && cut.duration == 6)
    #expect(cut.tracks[1].clips.count == 1)
}

@Test func onlyMainClipsCanBeDeletedByID() throws {
    let project = project()
    #expect(project.deleting(clip: project.tracks[1].clips[0].id) == nil)
    #expect(project.deleting(clip: project.main.clips[0].id) == nil, "the only clip can't go")
    #expect(project.deleting(clip: UUID()) == nil)
}

@Test func mainClipAtTimeIsHalfOpenExceptAtTheEnd() throws {
    let split = try #require(project().splitting(at: 4))
    #expect(split.mainClip(at: 3.99)?.id == split.main.clips[0].id)
    #expect(split.mainClip(at: 4)?.id == split.main.clips[1].id)
    #expect(split.mainClip(at: 10)?.id == split.main.clips[1].id)
    #expect(split.mainClip(at: 11) == nil)
}

@Test func snapPointsAreEveryClipEdgeAcrossTracks() throws {
    var split = try #require(project().splitting(at: 4))
    split.tracks.append(Track(kind: .audio, clips: [Clip(source: recording, sourceDuration: 3, start: 12)]))
    #expect(split.snapPoints() == [0, 4, 10, 12, 15])
    #expect(split.snapPoints(excluding: [split.tracks[2].clips[0].id]) == [0, 4, 10])
}

@Test func timelineTimeMapsBackToTheRecordingAcrossACut() throws {
    let cut = try #require(project().cutting(source: 2..<5))
    #expect(cut.sourceTime(atTimeline: 1) == 1)
    #expect(cut.sourceTime(atTimeline: 2) == 5)
    #expect(cut.sourceTime(atTimeline: 4) == 7)
    #expect(cut.sourceTime(atTimeline: 99) == 10)
    #expect(cut.timelinePosition(ofSource: cut.sourceTime(atTimeline: 4)) == 4)
}
