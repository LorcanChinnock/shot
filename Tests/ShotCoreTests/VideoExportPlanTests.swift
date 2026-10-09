import AVFoundation
import Foundation
import Testing
@testable import ShotCore

private let source = URL(fileURLWithPath: "/tmp/recording.mov")

private func recording(audio: Bool = true) -> Project {
    Project(source: source, duration: 10, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: audio)
}

/// More than a trim: muting the recording's sound track means it has to be drawn.
private func drawn() -> Project {
    var project = recording()
    let audio = project.tracks.firstIndex { $0.kind == .audio }!
    project.tracks[audio].isMuted = true
    return project
}

@Test func aTrimExportsFromTheRecordingInTheChosenFormat() {
    let project = recording()
    #expect(project.trimEdit != nil)
    let mp4 = VideoExportPlan(project: project, options: VideoExportOptions(format: .mp4, muted: true, speed: 2))
    #expect(mp4 == .trimmed(source: source, range: TrimRange(duration: 10), cuts: CutList(), speed: 2, muted: true, fileType: .mp4))
    let gif = VideoExportPlan(project: project, options: VideoExportOptions(format: .gif, gifFrameRate: 10, gifWidth: VideoExportOptions.originalWidth, speed: 1.5))
    #expect(gif == .trimmedGIF(source: source, range: TrimRange(duration: 10), cuts: CutList(), fps: 10, maxWidth: nil, speed: 1.5))
}

@Test func anEditThatHasToBeDrawnExportsTheProject() {
    let project = drawn()
    #expect(project.trimEdit == nil)
    let mp4 = VideoExportPlan(project: project, options: VideoExportOptions(format: .mp4, speed: 2))
    #expect(mp4 == .composite(project, fileType: .mp4))
    let gif = VideoExportPlan(project: project, options: VideoExportOptions(format: .gif, gifFrameRate: 24, gifWidth: 480, speed: 2))
    #expect(gif == .compositeGIF(project, fps: 24, maxWidth: 480, speed: 2))
}

@Test func mutingADrawnExportMutesEverySoundTrack() {
    var project = drawn()
    project.tracks[0].isHidden = true
    guard case let .composite(exported, _) = VideoExportPlan(project: project, options: VideoExportOptions(format: .mp4, muted: true)) else {
        Issue.record("expected a drawn export")
        return
    }
    let soundTracks = exported.tracks.filter { $0.kind == .audio }
    #expect(!soundTracks.isEmpty && soundTracks.allSatisfy { $0.isMuted })
    #expect(exported.tracks[0].isHidden)
}

@Test func aCopyKeepsTheRecordingsSpeedSoundAndFormat() {
    #expect(VideoExportPlan.copy(of: recording(), as: .mov) == .trimmed(source: source, range: TrimRange(duration: 10), cuts: CutList(), speed: 1, muted: false, fileType: nil))
    let edited = drawn()
    #expect(VideoExportPlan.copy(of: edited, as: .mov) == .composite(edited, fileType: .mov))
}

@Test func aDrawnMP4IsEstimatedFromTheCanvasAndSound() async throws {
    // A typical H.264 rate for 1920 × 1080 at 30 fps, and 128 kb/s of AAC when there's sound, over 10 seconds.
    let video = 1920.0 * 1080 * 30 * 0.07
    let silent = drawn()
    #expect(ProjectExporter.estimatedSize(of: silent) == Int((video * 10 / 8).rounded()))
    #expect(try await VideoExportPlan.composite(silent, fileType: .mp4).estimate() == ProjectExporter.estimatedSize(of: silent))

    var sound = recording()
    sound.tracks[0].isHidden = true
    #expect(ProjectExporter.estimatedSize(of: sound) == Int(((video + 128_000) * 10 / 8).rounded()))
}
