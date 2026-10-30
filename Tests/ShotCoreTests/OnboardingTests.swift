import Testing
@testable import ShotCore

@Test func aFirstLaunchIsNewAndAnEarlierUserIsDone() {
    #expect(OnboardingProgress(saved: nil, hasSavedSettings: false) == .new)
    #expect(OnboardingProgress(saved: nil, hasSavedSettings: true) == .done)
}

@Test func savedProgressWinsOverSavedSettings() {
    #expect(OnboardingProgress(saved: "new", hasSavedSettings: true) == .new)
    #expect(OnboardingProgress(saved: "done", hasSavedSettings: false) == .done)
}

@Test func unknownSavedProgressFallsBackToSavedSettings() {
    #expect(OnboardingProgress(saved: "later", hasSavedSettings: true) == .done)
    #expect(OnboardingProgress(saved: "", hasSavedSettings: false) == .new)
}

@Test func someoneNewSeesEveryStepAndSkipsAccessOnceGranted() {
    #expect(OnboardingProgress.new.steps(hasPermission: false, hasAccessibility: false) == [.permission, .accessibility, .setup, .tryIt])
    #expect(OnboardingProgress.new.steps(hasPermission: true, hasAccessibility: false) == [.accessibility, .setup, .tryIt])
    #expect(OnboardingProgress.new.steps(hasPermission: false, hasAccessibility: true) == [.permission, .setup, .tryIt])
    #expect(OnboardingProgress.new.steps(hasPermission: true, hasAccessibility: true) == [.setup, .tryIt])
}

@Test func someoneDoneSeesOnlyScreenRecordingAndOnlyWhileItIsMissing() {
    #expect(OnboardingProgress.done.steps(hasPermission: false, hasAccessibility: false) == [.permission])
    #expect(OnboardingProgress.done.steps(hasPermission: true, hasAccessibility: false).isEmpty)
}

@Test func openingItAgainShowsSetupAndTryItWhateverTheProgress() {
    #expect(OnboardingProgress.replaySteps(hasPermission: true, hasAccessibility: true) == [.setup, .tryIt])
    #expect(OnboardingProgress.replaySteps(hasPermission: false, hasAccessibility: false) == [.permission, .accessibility, .setup, .tryIt])
}
