import Foundation
import Testing
@testable import ShotModel

// MARK: Trim range

@Test func fullRangeCoversTheWholeVideo() {
    let range = TrimRange(duration: 12)
    #expect(range.start == 0)
    #expect(range.end == 12)
    #expect(range.length == 12)
    #expect(range.isFull(duration: 12))
    #expect(!TrimRange(start: 0, end: 11, duration: 12).isFull(duration: 12))
}

@Test func initClampsToTheVideo() {
    let range = TrimRange(start: -3, end: 40, duration: 12)
    #expect(range == TrimRange(duration: 12))
    let crossed = TrimRange(start: 8, end: 2, duration: 12)
    #expect(crossed.start == 2)
    #expect(crossed.end == 8)
}

@Test func movingTheStartClampsToZeroAndKeepsTheMinimumLength() {
    let range = TrimRange(start: 2, end: 6, duration: 10)
    #expect(range.moving(.start, to: 3.5, duration: 10) == TrimRange(start: 3.5, end: 6, duration: 10))
    #expect(range.moving(.start, to: -1, duration: 10).start == 0)
    #expect(range.moving(.start, to: 9, duration: 10).start == 6 - TrimRange.minimumLength)
    #expect(range.moving(.start, to: 9, duration: 10).end == 6)
}

@Test func movingTheEndClampsToTheDurationAndKeepsTheMinimumLength() {
    let range = TrimRange(start: 2, end: 6, duration: 10)
    #expect(range.moving(.end, to: 7.25, duration: 10) == TrimRange(start: 2, end: 7.25, duration: 10))
    #expect(range.moving(.end, to: 30, duration: 10).end == 10)
    #expect(range.moving(.end, to: 0, duration: 10).end == 2 + TrimRange.minimumLength)
    #expect(range.moving(.end, to: 0, duration: 10).start == 2)
}

@Test func videoShorterThanTheMinimumCannotBeTrimmed() {
    let range = TrimRange(duration: 0.05)
    #expect(range.moving(.start, to: 0.03, duration: 0.05) == range)
    #expect(range.moving(.end, to: 0.01, duration: 0.05) == range)
}

@Test func playbackStartsAtTheInPointUnlessThePlayheadIsInsideTheRange() {
    let range = TrimRange(start: 2, end: 6, duration: 10)
    #expect(range.playbackStart(from: 3) == 3)
    #expect(range.playbackStart(from: 1) == 2)
    #expect(range.playbackStart(from: 6) == 2)
    // Playback can stop a hair short of the out point.
    #expect(range.playbackStart(from: 5.995) == 2)
    #expect(range.playbackStart(from: 8) == 2)
}

@Test func timecodes() {
    #expect(Timecode.string(0) == "0:00.00")
    #expect(Timecode.string(3.256) == "0:03.25")
    #expect(Timecode.string(75.5) == "1:15.50")
    #expect(Timecode.string(-2) == "0:00.00")
}

// MARK: Timeline geometry

private let timeline = TrimTimeline(duration: 10, minX: 20, width: 500)

@Test func timelineMapsTimeAndPosition() {
    #expect(timeline.x(for: 0) == 20)
    #expect(timeline.x(for: 10) == 520)
    #expect(timeline.x(for: 4) == 220)
    #expect(timeline.time(at: 220) == 4)
    #expect(timeline.time(at: 0) == 0)
    #expect(timeline.time(at: 900) == 10)
}

@Test func emptyTimelineDoesNotDivideByZero() {
    let empty = TrimTimeline(duration: 0, minX: 0, width: 0)
    #expect(empty.time(at: 50) == 0)
    #expect(empty.x(for: 3) == 0)
}

@Test func handleHitTesting() {
    let range = TrimRange(start: 2, end: 8, duration: 10)
    let inX = timeline.x(for: range.start), outX = timeline.x(for: range.end)
    let width = TrimTimeline.handleWidth, reach = TrimTimeline.slop
    // The start handle sits left of the in point and the end handle right of the out point.
    #expect(timeline.handle(at: inX - width / 2, range: range) == .start)
    #expect(timeline.handle(at: outX + width / 2, range: range) == .end)
    // A little either side of a handle still grabs it.
    #expect(timeline.handle(at: inX + reach, range: range) == .start)
    #expect(timeline.handle(at: inX - width - reach, range: range) == .start)
    #expect(timeline.handle(at: outX - reach, range: range) == .end)
    #expect(timeline.handle(at: outX + width + reach, range: range) == .end)
    // Past that reach, and between the handles, is neither.
    #expect(timeline.handle(at: inX + reach + 1, range: range) == nil)
    #expect(timeline.handle(at: inX - width - reach - 1, range: range) == nil)
    #expect(timeline.handle(at: outX + width + reach + 1, range: range) == nil)
    #expect(timeline.handle(at: (inX + outX) / 2, range: range) == nil)
}

@Test func touchingHandlesPickTheNearerSide() {
    let range = TrimRange(start: 5, end: 5.1, duration: 10)
    #expect(timeline.handle(at: timeline.x(for: 5) - 3, range: range) == .start)
    #expect(timeline.handle(at: timeline.x(for: 5.1) + 3, range: range) == .end)
}

@Test func thumbnailsFillTheStripAtTheirMidpoints() {
    #expect(TrimTimeline.thumbnailCount(width: 500, height: 50, aspectRatio: 16.0 / 9) == 6)
    #expect(TrimTimeline.thumbnailCount(width: 10, height: 50, aspectRatio: 2) == 1)
    #expect(TrimTimeline.thumbnailCount(width: 500, height: 0, aspectRatio: 2) == 1)
    #expect(timeline.thumbnailTimes(count: 4) == [1.25, 3.75, 6.25, 8.75])
}
