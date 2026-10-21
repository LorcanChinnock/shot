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
    #expect(OnboardingProgress.new.steps(hasPermission: false) == [.permission, .setup, .tryIt])
    #expect(OnboardingProgress.new.steps(hasPermission: true) == [.setup, .tryIt])
}

@Test func someoneDoneSeesOnlyAccessAndOnlyWhileItIsMissing() {
    #expect(OnboardingProgress.done.steps(hasPermission: false) == [.permission])
    #expect(OnboardingProgress.done.steps(hasPermission: true).isEmpty)
}

@Test func openingItAgainShowsSetupAndTryItWhateverTheProgress() {
    #expect(OnboardingProgress.replaySteps(hasPermission: true) == [.setup, .tryIt])
    #expect(OnboardingProgress.replaySteps(hasPermission: false) == [.permission, .setup, .tryIt])
}
