import Foundation
import Testing
@testable import ShotCore

@Test func recordingStartsAtOnceByDefault() {
    let start = RecordingStart.after(adjustBeforeRecording: false, countdown: 0, optionHeld: false)
    #expect(start == RecordingStart(showsSetup: false, countdown: 0))
}

@Test func adjustBeforeRecordingShowsTheSetupPanel() {
    #expect(RecordingStart.after(adjustBeforeRecording: true, countdown: 0, optionHeld: false).showsSetup)
}

@Test func holdingOptionShowsTheSetupPanelOnce() {
    #expect(RecordingStart.after(adjustBeforeRecording: false, countdown: 0, optionHeld: true).showsSetup)
    #expect(RecordingStart.after(adjustBeforeRecording: true, countdown: 0, optionHeld: true).showsSetup)
}

@Test func countdownAppliesWithOrWithoutTheSetupPanel() {
    #expect(RecordingStart.after(adjustBeforeRecording: false, countdown: 3, optionHeld: false) == RecordingStart(showsSetup: false, countdown: 3))
    #expect(RecordingStart.after(adjustBeforeRecording: true, countdown: 5, optionHeld: false) == RecordingStart(showsSetup: true, countdown: 5))
}

@Test func unknownCountdownLengthsTurnTheCountdownOff() {
    #expect(RecordingStart.after(adjustBeforeRecording: false, countdown: 7, optionHeld: false).countdown == 0)
    #expect(RecordingStart.after(adjustBeforeRecording: false, countdown: -3, optionHeld: false).countdown == 0)
}

@Test func storedCountdownOutsideTheOffersReadsAsOff() throws {
    let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }
    let prefs = Preferences(store: store)
    store.set(5, forKey: PreferenceKey.recordingCountdown)
    #expect(prefs.recordingCountdown == 5)
    store.set(4, forKey: PreferenceKey.recordingCountdown)
    #expect(prefs.recordingCountdown == 0)
}
