import Foundation
import Testing
@testable import ShotCore

private func edit(duration: Double, options: VideoExportOptions = VideoExportOptions()) -> VideoEdit {
    VideoEdit(project: Project(source: URL(fileURLWithPath: "/tmp/recording.mov"), duration: duration, canvasSize: CGSize(width: 640, height: 360), hasAudio: true), options: options)
}

@Test func aFreshVideoHistoryHasNothingToUndoOrRedo() {
    let history = VideoEditHistory()
    #expect(!history.canUndo)
    #expect(!history.canRedo)
}

@Test func aChangeIsAStepUndoRestoresAndRedoReturnsTo() {
    var history = VideoEditHistory()
    history.recordChange(from: edit(duration: 10))
    #expect(history.canUndo)
    #expect(history.undo(from: edit(duration: 8))?.project.duration == 10)
    #expect(history.canRedo)
    #expect(history.redo(from: edit(duration: 10))?.project.duration == 8)
}

@Test func undoAndRedoWithNothingToStepToReturnNil() {
    var history = VideoEditHistory()
    #expect(history.undo(from: edit(duration: 10)) == nil)
    #expect(history.redo(from: edit(duration: 10)) == nil)
}

@Test func changesWithTheSameKeyInARowAreOneStep() {
    var history = VideoEditHistory()
    history.recordChange(from: edit(duration: 10), coalescing: "colour")
    history.recordChange(from: edit(duration: 9), coalescing: "colour")
    history.recordChange(from: edit(duration: 8), coalescing: "colour")
    #expect(history.undo(from: edit(duration: 7))?.project.duration == 10)
    #expect(!history.canUndo)
}

@Test func aDifferentVideoKeyOrNoKeyStartsANewStep() {
    var history = VideoEditHistory()
    history.recordChange(from: edit(duration: 10), coalescing: "a")
    history.recordChange(from: edit(duration: 9), coalescing: "b")
    history.recordChange(from: edit(duration: 8))
    history.recordChange(from: edit(duration: 7))
    _ = history.undo(from: edit(duration: 6))
    _ = history.undo(from: edit(duration: 7))
    _ = history.undo(from: edit(duration: 8))
    #expect(history.undo(from: edit(duration: 9))?.project.duration == 10)
    #expect(!history.canUndo)
}

@Test func stoppingCoalescingMakesTheNextChangeItsOwnStep() {
    var history = VideoEditHistory()
    history.recordChange(from: edit(duration: 10), coalescing: "colour")
    history.stopCoalescing()
    history.recordChange(from: edit(duration: 9), coalescing: "colour")
    _ = history.undo(from: edit(duration: 8))
    #expect(history.canUndo)
}

@Test func aChangeThatIsNotRecordingJoinsTheLastStep() {
    var history = VideoEditHistory()
    history.recordChange(from: edit(duration: 10))
    history.recordChange(from: edit(duration: 9), recording: false)
    #expect(history.undo(from: edit(duration: 8))?.project.duration == 10)
    #expect(!history.canUndo)
}

@Test func recordingAStepEndsCoalescing() {
    var history = VideoEditHistory()
    history.recordChange(from: edit(duration: 10), coalescing: "colour")
    history.record(edit(duration: 9))
    history.recordChange(from: edit(duration: 8), coalescing: "colour")
    _ = history.undo(from: edit(duration: 7))
    #expect(history.canUndo)
}

@Test func aNewChangeClearsWhatCouldBeRedone() {
    var history = VideoEditHistory()
    history.recordChange(from: edit(duration: 10))
    _ = history.undo(from: edit(duration: 9))
    history.recordChange(from: edit(duration: 10))
    #expect(!history.canRedo)
}

@Test func exportOptionsAreRestoredWithTheProject() {
    var history = VideoEditHistory()
    let before = edit(duration: 10, options: VideoExportOptions(format: .mp4))
    history.record(before)
    #expect(history.undo(from: edit(duration: 10, options: VideoExportOptions(format: .gif)))?.options.format == .mp4)
}

@Test func resettingForgetsEveryStep() {
    var history = VideoEditHistory()
    history.recordChange(from: edit(duration: 10))
    _ = history.undo(from: edit(duration: 9))
    history.reset()
    #expect(!history.canUndo)
    #expect(!history.canRedo)
}
