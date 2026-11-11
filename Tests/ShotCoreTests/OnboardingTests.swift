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

@Test func someoneNewIsAskedOnlyForScreenRecordingAndSkipsItOnceGranted() {
    #expect(OnboardingProgress.new.steps(hasPermission: false, hasAccessibility: false) == [.permission, .setup, .tryIt])
    #expect(OnboardingProgress.new.steps(hasPermission: true, hasAccessibility: false) == [.setup, .tryIt])
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

@Test func theTitleBarListsScreenRecordingFirstAndTicksItWhenGranted() {
    let afterRelaunch = OnboardingIndicatorItem.items(steps: [.setup, .tryIt], current: 0, finished: false)
    #expect(afterRelaunch == [
        OnboardingIndicatorItem(step: .permission, state: .done),
        OnboardingIndicatorItem(step: .setup, state: .current),
        OnboardingIndicatorItem(step: .tryIt, state: .upcoming),
    ])
    let asking = OnboardingIndicatorItem.items(steps: [.permission, .setup, .tryIt], current: 0, finished: false)
    #expect(asking.map(\.state) == [.current, .upcoming, .upcoming])
}

@Test func theTitleBarTicksEachStepPassedAndTheLastOnceFinished() {
    let replay: [OnboardingStep] = [.accessibility, .setup, .tryIt]
    #expect(OnboardingIndicatorItem.items(steps: replay, current: 2, finished: false).map(\.state) == [.done, .done, .done, .current])
    #expect(OnboardingIndicatorItem.items(steps: replay, current: 2, finished: true).map(\.state) == [.done, .done, .done, .done])
    #expect(OnboardingIndicatorItem.items(steps: replay, current: 0, finished: false).map(\.step) == [.permission, .accessibility, .setup, .tryIt])
}

@Test func aWindowWithOneStepListsNone() {
    #expect(OnboardingIndicatorItem.items(steps: [.permission], current: 0, finished: false).isEmpty)
}
