import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let recording = URL(fileURLWithPath: "/tmp/summary-recording.mov")

private func recordingProject() -> Project {
    Project(source: recording, duration: 10, canvasSize: CGSize(width: 640, height: 360), hasAudio: true)
}

private func arrow() -> Annotation {
    Annotation(kind: .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 60)), color: RGBA.presets[0], lineWidth: 4)
}

@Test func summaryOfAnUneditedRecordingIsEmpty() {
    #expect(VideoEditSummary(project: recordingProject(), recording: recording).parts.isEmpty)
}

@Test func summaryCountsCutsAndAnnotationsInTheBoardsOrder() throws {
    let cut = try #require(recordingProject().deleting(range: 4.0..<5.2))
    let once = cut.adding(annotation: arrow(), at: 1).project
    let twice = once.adding(annotation: arrow(), at: 2).project
    #expect(VideoEditSummary(project: twice, recording: recording).parts == [.cuts(1), .annotations(2)])
}

@Test func summaryCallsATrimmedEndTrimmedRatherThanACut() throws {
    let trimmed = try #require(recordingProject().trimmingMain(.start, toSource: 1.5))
    #expect(VideoEditSummary(project: trimmed, recording: recording).parts == [.trimmed])
    let both = try #require(trimmed.deleting(range: 3.0..<4.0))
    #expect(VideoEditSummary(project: both, recording: recording).parts == [.trimmed, .cuts(1)])
}

@Test func summaryCountsAnAddedVideoOnceWithItsSound() throws {
    let video = ImportedMedia(source: URL(fileURLWithPath: "/tmp/summary-added.mov"), duration: 3, size: CGSize(width: 320, height: 180), hasAudio: true)
    let sound = ImportedMedia(source: URL(fileURLWithPath: "/tmp/summary-voice.m4a"), duration: 3, size: nil, hasAudio: true)
    let withVideo = try #require(recordingProject().importing(video, at: 1)).project
    #expect(VideoEditSummary(project: withVideo, recording: recording).parts == [.addedClips(1)])
    let withSound = try #require(withVideo.importing(sound, at: 2)).project
    #expect(VideoEditSummary(project: withSound, recording: recording).parts == [.addedClips(2)])
}

@Test func summaryNotesACroppedFrameLast() throws {
    var cropped = try #require(recordingProject().deleting(range: 2.0..<3.0))
    cropped.frameCrop = CGRect(x: 0, y: 0, width: 320, height: 180)
    #expect(VideoEditSummary(project: cropped, recording: recording).parts == [.cuts(1), .cropped])
}

@Test func summaryLeavesAnEditItCantNameToEditedAlone() throws {
    var moved = recordingProject()
    moved.tracks[0].clips[0].transform.offset = CGSize(width: 20, height: 0)
    #expect(VideoEditSummary(project: moved, recording: recording).parts.isEmpty)
}
