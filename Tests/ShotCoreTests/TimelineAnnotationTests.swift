import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let recording = URL(fileURLWithPath: "/tmp/recording.mov")

private func project() -> Project {
    Project(source: recording, duration: 10, canvasSize: CGSize(width: 640, height: 360), hasAudio: true)
}

private func rect(_ x: CGFloat = 10) -> Annotation {
    Annotation(kind: .rect(CGRect(x: x, y: 10, width: 50, height: 30)), color: RGBA.presets[0], lineWidth: 4)
}

@Test func addingAnAnnotationMakesAnOverlayTrackForThreeSeconds() throws {
    let (annotated, id) = project().adding(annotation: rect(), at: 2)
    #expect(annotated.tracks.map(\.kind) == [.video, .audio, .overlay])
    let clip = try #require(annotated.annotationClip(id))
    #expect(clip.start == 2 && clip.duration == 3 && clip.end == 5)
    #expect(annotated.duration == 10)
    #expect(annotated.trimEdit == nil)
}

@Test func anAnnotationNearTheEndStopsWhereTheProjectDoes() throws {
    let (annotated, id) = project().adding(annotation: rect(), at: 9)
    #expect(annotated.annotationClip(id)?.duration == 1)
    let (late, lateID) = project().adding(annotation: rect(), at: 9.95)
    #expect(late.annotationClip(lateID)?.duration == TrimRange.minimumLength, "never shorter than the minimum")
}

@Test func annotationsThatDontOverlapShareALane() throws {
    let (first, _) = project().adding(annotation: rect(), at: 0)
    let (second, _) = first.adding(annotation: rect(), at: 3)
    #expect(second.tracks.filter { $0.kind == .overlay }.count == 1)
    #expect(second.tracks.last?.annotations.map(\.start) == [0, 3])
}

@Test func overlappingAnnotationsGetTheirOwnLanes() throws {
    let (first, _) = project().adding(annotation: rect(), at: 0)
    let (second, _) = first.adding(annotation: rect(), at: 1)
    #expect(second.tracks.filter { $0.kind == .overlay }.count == 2)
}

@Test func editingWhatAnAnnotationShowsKeepsItsPlace() throws {
    let (annotated, id) = project().adding(annotation: rect(), at: 2)
    let changed = try #require(annotated.setting(annotation: rect(99), ofClip: id))
    #expect(changed.annotationClip(id)?.annotation == rect(99) || changed.annotationClip(id)?.start == 2)
    #expect(changed.annotationClip(id)?.start == 2)
    #expect(annotated.setting(annotation: rect(), ofClip: UUID()) == nil)
}

@Test func deletingAnAnnotationDropsItsEmptyLane() throws {
    let (annotated, id) = project().adding(annotation: rect(), at: 2)
    let deleted = try #require(annotated.deleting(clip: id))
    #expect(deleted.tracks.map(\.kind) == [.video, .audio])
    #expect(deleted.trimEdit != nil)
}

@Test func movingAnAnnotationStaysInsideItsLaneAndSnaps() throws {
    var (annotated, a) = project().adding(annotation: rect(), at: 1)
    let b: UUID
    (annotated, b) = annotated.adding(annotation: rect(), at: 6)
    #expect(annotated.tracks.filter { $0.kind == .overlay }.count == 1)
    let moved = try #require(annotated.moving(clip: a, toStart: 5.5))
    #expect(moved.annotationClip(a)?.start == 3, "stops against the next annotation, which starts at 6")
    let early = try #require(annotated.moving(clip: a, toStart: -4))
    #expect(early.annotationClip(a)?.start == 0)
    let snapped = try #require(annotated.moving(clip: a, toStart: 1.95, snapWithin: 0.1, snapTo: [2]))
    #expect(snapped.annotationClip(a)?.start == 2)
    #expect(annotated.annotationClip(b)?.start == 6)
}

@Test func trimmingAnAnnotationChangesItsDurationWithinItsNeighbours() throws {
    var (annotated, a) = project().adding(annotation: rect(), at: 1)
    (annotated, _) = annotated.adding(annotation: rect(), at: 6)
    let longer = try #require(annotated.trimming(clip: a, .end, toTimeline: 9))
    #expect(longer.annotationClip(a)?.end == 6, "stops against the next one")
    let shorter = try #require(annotated.trimming(clip: a, .end, toTimeline: 2))
    #expect(shorter.annotationClip(a)?.duration == 1)
    let earlier = try #require(annotated.trimming(clip: a, .start, toTimeline: 0.5))
    #expect(earlier.annotationClip(a)?.start == 0.5 && earlier.annotationClip(a)?.end == 4)
    let tiny = try #require(annotated.trimming(clip: a, .start, toTimeline: 9))
    #expect(abs((tiny.annotationClip(a)?.duration ?? 0) - TrimRange.minimumLength) < 1e-9)
}

@Test func splittingCutsAnAnnotationInTwo() throws {
    let (annotated, id) = project().adding(annotation: rect(), at: 2)
    let split = try #require(annotated.splitting(at: 3.5))
    let clips = split.annotationClips.sorted { $0.start < $1.start }
    #expect(clips.map(\.start) == [2, 3.5] && clips.map(\.duration) == [1.5, 1.5])
    #expect(clips[0].id == id && clips[1].id != id)
    #expect(clips[0].annotation == clips[1].annotation)
}

@Test func annotationsMarkSnapPointsAndSegments() throws {
    let (annotated, id) = project().adding(annotation: rect(), at: 2)
    #expect(annotated.snapPoints() == [0, 2, 5, 10])
    #expect(annotated.snapPoints(excluding: [id]) == [0, 10])
    let segments = annotated.videoSegments()
    #expect(segments.map(\.range) == [0..<2, 2..<5, 5..<10])
    #expect(segments.map(\.annotations) == [[], [id], []])
}

@Test func annotationsAreLongerThanTheVideoExtendTheProject() throws {
    var (annotated, id) = project().adding(annotation: rect(), at: 8)
    annotated = try #require(annotated.trimming(clip: id, .end, toTimeline: 14))
    #expect(annotated.duration == 14)
    #expect(annotated.videoSegments().last?.clips.isEmpty == true)
}

@Test func counterNumbersContinueAcrossTheTimeline() {
    var annotated = project()
    for index in 0..<3 {
        let counter = Annotation(kind: .counter(annotated.nextCounterNumber, center: CGPoint(x: 10, y: 10)), color: RGBA.presets[0], lineWidth: 4)
        annotated = annotated.adding(annotation: counter, at: Double(index) * 3).project
    }
    #expect(annotated.nextCounterNumber == 4)
}

@Test func annotatedProjectsRoundTripThroughJSON() throws {
    let (annotated, _) = project().adding(annotation: rect(), at: 2)
    let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(annotated))
    #expect(decoded == annotated)
}
