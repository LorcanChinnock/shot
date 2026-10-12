import Foundation
import Testing
@testable import ShotModel

private typealias KeyFrame = RecordingMark.KeyFrame

@Test func eachMarkAsksForTheFrameAtItsTimeInOrder() {
    let marks = [RecordingMark(time: 4, label: "saw the error"), RecordingMark(time: 1.5, label: "tapped Login")]
    #expect(RecordingMark.frames(for: marks, duration: 10, limit: 12) == [KeyFrame(time: 1.5, labels: ["tapped Login"]), KeyFrame(time: 4, labels: ["saw the error"])])
}

@Test func marksCloseTogetherShareAFrame() {
    let marks = [RecordingMark(time: 2, label: "a"), RecordingMark(time: 2.1, label: "b"), RecordingMark(time: 2.5, label: "c")]
    #expect(RecordingMark.frames(for: marks, duration: 10, limit: 12) == [KeyFrame(time: 2, labels: ["a", "b"]), KeyFrame(time: 2.5, labels: ["c"])])
}

@Test func aMarkPastTheEndShowsTheLastFrame() {
    // A mark made as the recording stopped can be a moment past the saved video's end.
    let marks = [RecordingMark(time: 10.3, label: "done"), RecordingMark(time: -1, label: "early"), RecordingMark(time: .nan, label: "bad")]
    #expect(RecordingMark.frames(for: marks, duration: 10, limit: 12) == [KeyFrame(time: 0, labels: ["early"]), KeyFrame(time: 9.95, labels: ["done"])])
}

@Test func marksLeaveRoomForTheFirstAndLastFrames() {
    let marks = (0 ..< 20).map { RecordingMark(time: Double($0), label: "\($0)") }
    let frames = RecordingMark.frames(for: marks, duration: 30, limit: 12)
    #expect(frames.count == 10)
    #expect(frames.last == KeyFrame(time: 9, labels: ["9"]))
    #expect(RecordingMark.changeCount(8, marked: 0, limit: 12) == 8)
    #expect(RecordingMark.changeCount(8, marked: 3, limit: 12) == 8)
    #expect(RecordingMark.changeCount(8, marked: 6, limit: 12) == 6)
    #expect(RecordingMark.changeCount(8, marked: 10, limit: 12) == 2)
}

@Test func aChangeAtAMarkIsShownOnceWithItsLabel() {
    let marked = [KeyFrame(time: 3, labels: ["tapped Login"])]
    let merged = RecordingMark.merge(changes: [0, 3.1, 5, 9.95], marked: marked)
    #expect(merged == [KeyFrame(time: 0), KeyFrame(time: 3, labels: ["tapped Login"]), KeyFrame(time: 5), KeyFrame(time: 9.95)])
    #expect(RecordingMark.merge(changes: [0, 9.95], marked: []) == [KeyFrame(time: 0), KeyFrame(time: 9.95)])
}

@Test func marksRoundTripAsJSON() throws {
    let marks = [RecordingMark(time: 1.25, label: "tapped Login")]
    let data = try JSONEncoder().encode(marks)
    #expect(try JSONDecoder().decode([RecordingMark].self, from: data) == marks)
}
