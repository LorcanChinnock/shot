import Foundation
@testable import ShotCore
import Testing

@Test func recordingClockCountsWholeSeconds() {
    #expect(RecordingClock.seconds(0) == 0)
    #expect(RecordingClock.seconds(0.99) == 0)
    #expect(RecordingClock.seconds(7.2) == 7)
    #expect(RecordingClock.seconds(-1) == 0)
}

@Test func recordingClockLabels() {
    #expect(RecordingClock.label(0) == "0:00")
    #expect(RecordingClock.label(7) == "0:07")
    #expect(RecordingClock.label(754) == "12:34")
    #expect(RecordingClock.label(3723) == "1:02:03")
    #expect(RecordingClock.label(-3) == "0:00")
}

@Test func recordingClockPlaceholderHoldsWidthUntilAnHour() {
    #expect(RecordingClock.placeholder("0:07") == "00:00")
    #expect(RecordingClock.placeholder("12:34") == "00:00")
    #expect(RecordingClock.placeholder("1:02:03") == "0:00:00")
}

@Test func recordingClockWaitsForTheNextSecond() {
    #expect(abs(RecordingClock.untilNextSecond(7.25) - 0.76) < 0.0001)
    #expect(abs(RecordingClock.untilNextSecond(3) - 1.01) < 0.0001)
}
