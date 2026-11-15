import Foundation
import Testing
@testable import ShotCore

private let recording = URL(fileURLWithPath: "/tmp/recording.mov")

/// A 10-second recording cut into clips at 0–4 and 4–10, with an annotation at 2–5.
private func project() -> (project: Project, first: UUID, second: UUID, note: UUID) {
    var project = Project(source: recording, duration: 10, canvasSize: CGSize(width: 640, height: 360), hasAudio: false)
    let first = Clip(source: recording, sourceDuration: 10, sourceStart: 0, sourceEnd: 4, start: 0)
    let second = Clip(source: recording, sourceDuration: 10, sourceStart: 4, sourceEnd: 10, start: 4)
    project.tracks[0].clips = [first, second]
    let rect = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 10, y: 10, width: 50, height: 30)), color: RGBA.presets[0], lineWidth: 4)
    let (annotated, note) = project.adding(annotation: rect, at: 2)
    return (annotated, first.id, second.id, note)
}

@Test func optionArrowsStepThroughALanesClipsFromTheSelection() {
    let (project, first, second, _) = project()
    #expect(TimelineNavigation.step(forward: true, onTrack: 0, in: project, selected: first, playhead: 0) == .init(id: second, start: 4))
    #expect(TimelineNavigation.step(forward: true, onTrack: 0, in: project, selected: second, playhead: 4) == nil)
    #expect(TimelineNavigation.step(forward: false, onTrack: 0, in: project, selected: second, playhead: 9) == .init(id: first, start: 0))
}

@Test func withNothingSelectedOptionArrowsStepFromThePlayhead() {
    let (project, first, second, _) = project()
    #expect(TimelineNavigation.step(forward: true, onTrack: 0, in: project, selected: nil, playhead: 2) == .init(id: second, start: 4))
    // Inside a clip, ⌥← goes to that clip's start, then to the one before.
    #expect(TimelineNavigation.step(forward: false, onTrack: 0, in: project, selected: nil, playhead: 6) == .init(id: second, start: 4))
    #expect(TimelineNavigation.step(forward: false, onTrack: 0, in: project, selected: nil, playhead: 4) == .init(id: first, start: 0))
    #expect(TimelineNavigation.step(forward: false, onTrack: 0, in: project, selected: nil, playhead: 0) == nil)
}

@Test func optionUpAndDownFollowTheLanesAsDrawn() {
    let (project, _, _, _) = project()
    let overlay = project.tracks.firstIndex { $0.kind == .overlay }!
    #expect(TimelineNavigation.lane(down: false, from: 0, in: project) == overlay)
    #expect(TimelineNavigation.lane(down: true, from: overlay, in: project) == 0)
    #expect(TimelineNavigation.lane(down: false, from: overlay, in: project) == nil)
    #expect(TimelineNavigation.lane(down: true, from: 0, in: project) == nil)
}

@Test func movingToALaneSelectsWhatsUnderThePlayhead() {
    let (project, _, _, note) = project()
    let overlay = project.tracks.firstIndex { $0.kind == .overlay }!
    #expect(TimelineNavigation.item(onTrack: overlay, at: 3, in: project) == .init(id: note, start: 2))
    #expect(TimelineNavigation.item(onTrack: overlay, at: 6, in: project) == nil)
}

@Test func iAndOMarkTheEndsOfARange() {
    #expect(TimelineNavigation.marking(true, at: 2, current: nil, duration: 10) == 2..<10)
    #expect(TimelineNavigation.marking(false, at: 6, current: 2..<10, duration: 10) == 2..<6)
    #expect(TimelineNavigation.marking(false, at: 6, current: nil, duration: 10) == 0..<6)
    #expect(TimelineNavigation.marking(true, at: 3, current: 2..<6, duration: 10) == 3..<6)
}

@Test func markingPastTheOtherEndResetsIt() {
    #expect(TimelineNavigation.marking(true, at: 7, current: 2..<6, duration: 10) == 7..<10)
    #expect(TimelineNavigation.marking(false, at: 1, current: 2..<6, duration: 10) == 0..<1)
    #expect(TimelineNavigation.marking(true, at: 10, current: nil, duration: 10) == nil)
}
