import Testing
@testable import ShotCore

@Test func a60HzDisplayOffers30And60() {
    #expect(RecordingFrameRate.offered(maximumDisplayRate: 60) == [30, 60])
}

@Test func a120HzDisplayAlsoOffers120() {
    #expect(RecordingFrameRate.offered(maximumDisplayRate: 120) == [30, 60, 120])
    #expect(RecordingFrameRate.offered(maximumDisplayRate: 144) == [30, 60, 120])
}

@Test func aSlowOrUnknownDisplayStillOffersTheDefault() {
    #expect(RecordingFrameRate.offered(maximumDisplayRate: 0) == [30, 60])
    #expect(RecordingFrameRate.offered(maximumDisplayRate: 50) == [30, 60])
}

@Test func recordingKeepsTheSettingWhenTheDisplayIsFastEnough() {
    #expect(RecordingFrameRate.effective(setting: 120, displayRate: 120) == 120)
    #expect(RecordingFrameRate.effective(setting: 60, displayRate: 120) == 60)
    #expect(RecordingFrameRate.effective(setting: 30, displayRate: 60) == 30)
}

@Test func a120FpsSettingRecordsAt60OnASlowerDisplay() {
    #expect(RecordingFrameRate.effective(setting: 120, displayRate: 60) == 60)
    #expect(RecordingFrameRate.effective(setting: 120, displayRate: 100) == 60)
}

@Test func thirtyAnd60FpsAreKeptOnAnyDisplay() {
    #expect(RecordingFrameRate.effective(setting: 60, displayRate: 50) == 60)
    #expect(RecordingFrameRate.effective(setting: 60, displayRate: 0) == 60)
    #expect(RecordingFrameRate.effective(setting: 30, displayRate: 24) == 30)
}

@Test func anUnknownFrameRateSettingFallsBackToTheDefault() {
    #expect(RecordingFrameRate.effective(setting: 0, displayRate: 120) == 60)
    #expect(RecordingFrameRate.effective(setting: 90, displayRate: 120) == 60)
}

@Test func onlyRecordingsAbove60FpsUseHEVC() {
    #expect(!RecordingFrameRate.usesHEVC(fps: 30))
    #expect(!RecordingFrameRate.usesHEVC(fps: 60))
    #expect(RecordingFrameRate.usesHEVC(fps: 120))
}
