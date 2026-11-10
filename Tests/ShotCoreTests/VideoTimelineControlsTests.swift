import Foundation
import Testing
@testable import ShotCore

private let timelineSource = URL(fileURLWithPath: "/tmp/recording.mov")

private func timelineRecording() -> Project {
    Project(source: timelineSource, duration: 10, canvasSize: CGSize(width: 1280, height: 720), hasAudio: true)
}

@Test func videoWellCentresTheVideoInsideItsInsets() {
    // A 16:9 video in a wide well is limited by the height left after 20 pt above and below.
    let wide = VideoWell.videoRect(showing: CGSize(width: 1280, height: 720), in: CGSize(width: 1000, height: 400))
    #expect(wide.height == 360)
    #expect(wide.width == 640)
    #expect(wide.midX == 500 && wide.midY == 200)
    // A tall video in a narrow well is limited by the width left after the drawing tools' room either side.
    let tall = VideoWell.videoRect(showing: CGSize(width: 720, height: 1280), in: CGSize(width: 400, height: 2000))
    #expect(tall.width == 400 - VideoWell.sideInset * 2)
    #expect(tall.minX == VideoWell.sideInset)
    #expect(tall.midY == 1000)
}

@Test func videoWellKeepsTheDrawToolsClearOfTheVideo() {
    // The column floats 16 pt in and is 4 + 32 + 4 wide.
    let rect = VideoWell.videoRect(showing: CGSize(width: 1280, height: 720), in: CGSize(width: 880, height: 2000))
    #expect(rect.minX >= 16 + 40)
}

@Test func videoWellFitsTheVideoAboveTheCropBar() {
    let well = CGSize(width: 1000, height: 400)
    // The bar covers the bottom 60 pt, so the video fits between 20 pt above and 60 + 8 pt below.
    let rect = VideoWell.videoRect(showing: CGSize(width: 1280, height: 720), in: well, bottomClearance: 60)
    #expect(rect.minY == VideoWell.verticalInset)
    #expect(abs(rect.maxY - (400 - 68)) < 0.001)
    #expect(rect.midX == 500)
    // A bar lower than the inset leaves the video where it was.
    let low = VideoWell.videoRect(showing: CGSize(width: 1280, height: 720), in: well, bottomClearance: 4)
    #expect(low == VideoWell.videoRect(showing: CGSize(width: 1280, height: 720), in: well))
}

@Test func videoWellHasNothingToShowWhenEmpty() {
    #expect(VideoWell.videoRect(showing: .zero, in: CGSize(width: 500, height: 300)).isEmpty)
    #expect(VideoWell.videoRect(showing: CGSize(width: 16, height: 9), in: CGSize(width: 100, height: 30)).isEmpty, "shorter than the insets")
}

@Test func laneNamesSayWhatEachLaneHolds() {
    let recording = timelineRecording()
    #expect(recording.laneName(ofTrack: 0) == .video)
    #expect(recording.laneName(ofTrack: 1) == .sound, "the recording's own sound")
    let arrow = Annotation(kind: .line(from: .zero, to: CGPoint(x: 5, y: 5)), color: RGBA.presets[0], lineWidth: 2)
    let text = Annotation(kind: .text("Best day", origin: .zero, fontSize: 24), color: RGBA.presets[0], lineWidth: 2)
    let drawn = recording.adding(annotation: arrow, at: 1).project
    let drawnTrack = drawn.tracks.count - 1
    #expect(drawn.laneName(ofTrack: drawnTrack) == .draw)
    let written = recording.adding(annotation: text, at: 1).project
    #expect(written.laneName(ofTrack: written.tracks.count - 1) == .text)
}

@Test func cutMarksGiveEachCutsLength() throws {
    let recording = timelineRecording()
    #expect(recording.mainCutMarks.isEmpty)
    let cut = try #require(recording.deleting(range: 2..<3.2))
    let marks = cut.mainCutMarks
    #expect(marks.count == 1)
    #expect(abs(marks[0].time - 2) < 0.0001)
    #expect(abs(marks[0].length - 1.2) < 0.0001)
    #expect(marks.map(\.time) == cut.mainCuts)
}

@Test func aSplitIsNotACut() throws {
    let split = try #require(timelineRecording().splitting(at: 4))
    #expect(split.main.clips.count == 2)
    #expect(split.mainCutMarks.isEmpty)
}

@Test func zoomSliderRunsEvenlyFromTheWholeProjectToTheClosest() {
    #expect(TimelineZoom.sliderPosition(for: TimelineZoom.range.lowerBound) == 0)
    #expect(TimelineZoom.sliderPosition(for: TimelineZoom.range.upperBound) == 1)
    #expect(abs(TimelineZoom.sliderPosition(for: 8) - 0.5) < 0.0001, "8× is halfway between 1× and 64×")
    #expect(TimelineZoom.sliderPosition(for: 0.2) == 0, "clamped")
    for zoom in [1.0, 1.5, 3, 20, 64] {
        #expect(abs(TimelineZoom.zoom(atSliderPosition: TimelineZoom.sliderPosition(for: zoom)) - zoom) < 0.0001)
    }
    #expect(TimelineZoom.zoom(atSliderPosition: 2) == TimelineZoom.range.upperBound)
}
