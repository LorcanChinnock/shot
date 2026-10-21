import Testing
@testable import ShotCore

@Test func theTimerOffersTheRecordingCountdownsExceptOff() {
    #expect(ScreenshotTimer.delays == [3, 5])
    #expect(ScreenshotTimer.delays.contains(ScreenshotTimer.defaultDelay))
}

@Test func aTimerURLTakesAWholeMinuteAtMost() {
    #expect(ScreenshotTimer.urlDelays.contains(1))
    #expect(ScreenshotTimer.urlDelays.contains(60))
    #expect(!ScreenshotTimer.urlDelays.contains(0))
    #expect(!ScreenshotTimer.urlDelays.contains(61))
}
