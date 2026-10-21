import Testing
@testable import ShotCore

private let start = ContinuousClock.now

@Test func firstTipWaitsTheColdDelay() {
    var timing = TipTiming()
    timing.entered(at: start)
    #expect(timing.delay == TipTiming.coldDelay)
}

@Test func tipsShowAtOnceOnNeighbouringControlsOnceOneHasShown() {
    var timing = TipTiming()
    timing.entered(at: start)
    timing.shown()
    timing.left(at: start + .seconds(2))
    timing.entered(at: start + .seconds(2.2))
    #expect(timing.delay == .zero)
}

@Test func tipsCoolDownAfterThePointerIsOffTippedControlsForTheWarmWindow() {
    var timing = TipTiming()
    timing.entered(at: start)
    timing.shown()
    timing.left(at: start + .seconds(2))
    timing.entered(at: start + .seconds(2) + TipTiming.warmWindow)
    #expect(timing.delay == TipTiming.coldDelay)
}

@Test func tipsStayWarmWhileThePointerIsOnAnyTippedControl() {
    var timing = TipTiming()
    timing.entered(at: start)
    timing.shown()
    timing.entered(at: start + .seconds(1))
    timing.left(at: start + .seconds(1))
    timing.left(at: start + .seconds(5))
    timing.entered(at: start + .seconds(5.1))
    #expect(timing.delay == .zero)
}

@Test func passingOverControlsWithoutATipShowingStaysCold() {
    var timing = TipTiming()
    timing.entered(at: start)
    timing.left(at: start + .seconds(0.3))
    timing.entered(at: start + .seconds(0.3))
    #expect(timing.delay == TipTiming.coldDelay)
}
