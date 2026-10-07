import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private func keys(_ pairs: (Double, Double)...) -> [Keyframe<Double>] {
    pairs.map { Keyframe(time: $0.0, value: $0.1) }
}

@Test func everyEasingStartsAtZeroAndEndsAtOne() {
    for easing in Easing.allCases {
        #expect(easing.progress(0) == 0, "\(easing)")
        #expect(abs(easing.progress(1) - 1) < 1e-9, "\(easing)")
        #expect(easing.progress(-3) == 0 && abs(easing.progress(4) - 1) < 1e-9, "clamped")
    }
}

@Test func easingsHaveTheirShapes() {
    #expect(Easing.linear.progress(0.5) == 0.5)
    #expect(Easing.easeIn.progress(0.5) < 0.5)
    #expect(Easing.easeOut.progress(0.5) > 0.5)
    #expect(abs(Easing.easeInOut.progress(0.5) - 0.5) < 1e-9)
    #expect(Easing.easeInOut.progress(0.25) < 0.25 && Easing.easeInOut.progress(0.75) > 0.75)
}

@Test func aSpringOvershootsBeforeSettling() {
    let peak = stride(from: 0.0, through: 1, by: 0.01).map(Easing.spring.progress).max() ?? 0
    #expect(peak > 1.05)
    #expect(abs(Easing.spring.progress(1) - 1) < 1e-9)
}

@Test func easingsNeverGoBackwardsExceptSpring() {
    for easing in [Easing.linear, .easeIn, .easeOut, .easeInOut] {
        let samples = stride(from: 0.0, through: 1, by: 0.05).map(easing.progress)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
    }
}

@Test func noKeyframesGiveTheBaseValue() {
    #expect(Keyframes.value([Keyframe<Double>](), at: 3, base: 7) == 7)
}

@Test func aValueHoldsBeforeTheFirstAndAfterTheLastKeyframe() {
    let frames = keys((1, 10), (3, 30))
    #expect(Keyframes.value(frames, at: 0, base: 99) == 10)
    #expect(Keyframes.value(frames, at: 5, base: 99) == 30)
    #expect(Keyframes.value(frames, at: 1, base: 99) == 10 && Keyframes.value(frames, at: 3, base: 99) == 30)
}

@Test func valuesBetweenKeyframesFollowTheEarlierOnesEasing() {
    var frames = keys((0, 0), (2, 100))
    #expect(Keyframes.value(frames, at: 1, base: 0) == 50)
    frames[0].easing = .easeIn
    #expect(Keyframes.value(frames, at: 1, base: 0) == 25)
    frames[0].easing = .easeOut
    #expect(Keyframes.value(frames, at: 1, base: 0) == 75)
}

@Test func sizesInterpolateBothSides() {
    let frames = [Keyframe(time: 0, value: CGSize(width: 0, height: 100)), Keyframe(time: 1, value: CGSize(width: 50, height: 0))]
    #expect(Keyframes.value(frames, at: 0.5, base: .zero) == CGSize(width: 25, height: 50))
}

@Test func settingAddsInOrderAndKeepsTheEasingOfOneThatIsThere() {
    var frames = keys((0, 0), (4, 40))
    frames[0].easing = .spring
    frames = Keyframes.setting(frames, at: 2, to: 5)
    #expect(frames.map(\.time) == [0, 2, 4])
    frames = Keyframes.setting(frames, at: 0, to: 1)
    #expect(frames[0].value == 1 && frames[0].easing == .spring && frames.count == 3)
}

@Test func removingAndShifting() {
    let frames = keys((0, 0), (2, 20), (4, 40))
    #expect(Keyframes.removing(frames, at: 2).map(\.time) == [0, 4])
    #expect(Keyframes.removing(frames, at: 2.0001).map(\.time) == [0, 4], "within the tolerance")
    #expect(Keyframes.shifted(frames, by: -1).map(\.time) == [-1, 1, 3])
}

@Test func splittingKeepsTheCurveContinuousAcrossTheCut() {
    let frames = keys((0, 0), (4, 100))
    let (before, after) = Keyframes.splitting(frames, at: 1)
    #expect(before.map(\.time) == [0, 1] && before.last?.value == 25)
    #expect(after.map(\.time) == [0, 3] && after.first?.value == 25 && after.last?.value == 100)
    #expect(abs(Keyframes.value(after, at: 1.5, base: 0) - 62.5) < 1e-9)
}

@Test func splittingOnAKeyframeDoesntDoubleIt() {
    let (before, after) = Keyframes.splitting(keys((0, 0), (2, 20), (4, 40)), at: 2)
    #expect(before.map(\.time) == [0, 2] && after.map(\.time) == [0, 2])
}

@Test func splittingEmptyKeyframesStaysEmpty() {
    let (before, after) = Keyframes.splitting([Keyframe<Double>](), at: 1)
    #expect(before.isEmpty && after.isEmpty)
}

@Test func animationValuesFallBackToTheBaseForPropertiesWithoutKeyframes() {
    var animation = ClipAnimation()
    animation.opacity = keys((0, 0), (1, 1))
    let base = PropertyValues(position: CGSize(width: 5, height: 6), scale: 2, rotation: 0.5, opacity: 1, volume: 0.8, reveal: 1)
    let values = animation.values(at: 0.5, base: base)
    #expect(values.opacity == 0.5)
    #expect(values.position == base.position && values.scale == 2 && values.rotation == 0.5 && values.volume == 0.8)
}

@Test func togglingAKeyframeAddsOneHoldingTheCurrentValueThenRemovesIt() {
    let base = PropertyValues(scale: 3)
    let added = ClipAnimation().togglingKeyframe(.scale, at: 2, current: base)
    #expect(added.scale == [Keyframe(time: 2, value: 3)])
    #expect(added.hasKeyframe(.scale, at: 2) && added.hasKeyframes(.scale) && !added.hasKeyframes(.opacity))
    let removed = added.togglingKeyframe(.scale, at: 2, current: base)
    #expect(removed.isEmpty)
}

@Test func timesListsEachMomentOnceAcrossProperties() {
    var animation = ClipAnimation()
    animation.scale = keys((1, 1), (3, 2))
    animation.opacity = keys((1.0001, 0), (2, 1))
    #expect(animation.times == [1, 2, 3])
}

@Test func easingCanBeSetAndReadAtATime() {
    var animation = ClipAnimation()
    animation.scale = keys((1, 1), (3, 2))
    let eased = animation.settingEasing(.spring, at: 1)
    #expect(eased.easing(at: 1) == .spring && eased.easing(at: 3) == .linear && eased.easing(at: 2) == nil)
}

@Test func movingKeyframesReplacesOnesAlreadyAtTheTarget() {
    var animation = ClipAnimation()
    animation.scale = keys((1, 1), (2, 5), (3, 2))
    animation.opacity = keys((1, 0))
    let moved = animation.movingKeyframes(from: 1, to: 2)
    #expect(moved.scale.map(\.time) == [2, 3] && moved.scale[0].value == 1)
    #expect(moved.opacity.map(\.time) == [2])
}

@Test func splittingAnAnimationSplitsEveryProperty() {
    var animation = ClipAnimation()
    animation.scale = keys((0, 1), (4, 2))
    animation.volume = keys((0, 1), (4, 0))
    let (before, after) = animation.splitting(at: 1)
    #expect(before.scale.map(\.time) == [0, 1] && after.scale.map(\.time) == [0, 3])
    #expect(after.volume.first?.value == 0.75)
}

@Test func animationsRoundTripThroughJSON() throws {
    var animation = ClipAnimation()
    animation.position = [Keyframe(time: 0, value: CGSize(width: 1, height: 2), easing: .spring)]
    animation.scale = keys((1, 2))
    let decoded = try JSONDecoder().decode(ClipAnimation.self, from: JSONEncoder().encode(animation))
    #expect(decoded == animation)
}

@Test func theScaleSliderSpansTheWholeScaleRangeWithOneTimesInTheMiddle() {
    let doublings = PropertyValues.scaleDoublings
    #expect(abs(exp2(doublings.lowerBound) - PropertyValues.scaleRange.lowerBound) < 1e-9)
    #expect(abs(exp2(doublings.upperBound) - PropertyValues.scaleRange.upperBound) < 1e-9)
    #expect(abs(doublings.lowerBound + doublings.upperBound) < 1e-9)
}
