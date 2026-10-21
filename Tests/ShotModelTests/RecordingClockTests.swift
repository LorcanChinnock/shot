import Foundation
import Testing
@testable import ShotModel

@Test func aRecordingClockLeavesThePausesOut() {
    var clock = RecordingClock(start: 100)
    #expect(!clock.isPaused && clock.elapsed(at: 101.5) == 1.5)
    clock.pause(at: 102)
    #expect(clock.isPaused && clock.elapsed(at: 150) == 2)
    // A second pause, or a resume while recording, changes nothing.
    clock.pause(at: 103)
    clock.resume(at: 110)
    clock.resume(at: 111)
    #expect(!clock.isPaused && clock.elapsed(at: 113) == 5)
    // A time before the stretch started counts as none of it.
    #expect(clock.elapsed(at: 105) == 2)
}

@Test func aRecordingClockCountsWhatItsSegmentsReallyHold() {
    // A quarter of a second was recorded before the clock heard it had started.
    var clock = RecordingClock(start: 100, offset: 0.25)
    #expect(clock.elapsed(at: 101) == 1.25)
    // The segment turned out longer, with the frames recorded after the pause was asked for.
    clock.pause(at: 102, length: 2.5)
    #expect(clock.elapsed(at: 103) == 2.5)
    clock.resume(at: 104, offset: 0.125)
    #expect(clock.elapsed(at: 105) == 3.625)
}
