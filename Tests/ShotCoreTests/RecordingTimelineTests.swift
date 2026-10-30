import Foundation
import Testing
@testable import ShotCore

private let start = Date(timeIntervalSinceReferenceDate: 1000)

@Test func aTimelineThatHasNotStartedHasRunForNoTime() {
    #expect(RecordingTimeline().elapsed(at: start.addingTimeInterval(30)) == 0)
}

@Test func elapsedTimeGrowsWhileRunning() {
    var timeline = RecordingTimeline()
    timeline.run(at: start)
    #expect(timeline.elapsed(at: start.addingTimeInterval(12)) == 12)
}

@Test func elapsedTimeLeavesOutPausedStretches() {
    var timeline = RecordingTimeline()
    timeline.run(at: start)
    timeline.hold(at: start.addingTimeInterval(10))
    #expect(timeline.elapsed(at: start.addingTimeInterval(50)) == 10)
    timeline.run(at: start.addingTimeInterval(60))
    #expect(timeline.elapsed(at: start.addingTimeInterval(65)) == 15)
}

@Test func muteTogglesOnAndOff() {
    var timeline = RecordingTimeline()
    timeline.run(at: start)
    timeline.toggleMute(at: start.addingTimeInterval(2))
    #expect(timeline.isMuted)
    #expect(timeline.mutes.isEmpty)
    timeline.toggleMute(at: start.addingTimeInterval(5))
    #expect(!timeline.isMuted)
    #expect(timeline.mutes.cuts == [2..<5])
}

@Test func muteStretchesAreInRecordedTimeSoPausesDoNotCountTowardThem() {
    var timeline = RecordingTimeline()
    timeline.run(at: start)
    timeline.toggleMute(at: start.addingTimeInterval(4))
    timeline.hold(at: start.addingTimeInterval(6))
    timeline.run(at: start.addingTimeInterval(100))
    timeline.toggleMute(at: start.addingTimeInterval(103))
    #expect(timeline.mutes.cuts == [4..<9])
}

@Test func endingTheRecordingClosesAMuteInProgress() {
    var timeline = RecordingTimeline()
    timeline.run(at: start)
    timeline.toggleMute(at: start.addingTimeInterval(3))
    timeline.endMute(at: start.addingTimeInterval(8))
    #expect(!timeline.isMuted)
    #expect(timeline.mutes.cuts == [3..<8])
}

@Test func endingWithoutAMuteChangesNothing() {
    var timeline = RecordingTimeline()
    timeline.run(at: start)
    timeline.endMute(at: start.addingTimeInterval(8))
    #expect(timeline.mutes.isEmpty)
}

@Test func touchingMuteStretchesMerge() {
    var timeline = RecordingTimeline()
    timeline.run(at: start)
    timeline.toggleMute(at: start.addingTimeInterval(1))
    timeline.toggleMute(at: start.addingTimeInterval(2))
    timeline.toggleMute(at: start.addingTimeInterval(2))
    timeline.toggleMute(at: start.addingTimeInterval(3))
    #expect(timeline.mutes.cuts == [1..<3])
}
