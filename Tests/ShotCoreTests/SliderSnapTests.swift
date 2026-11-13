import Foundation
import Testing
@testable import ShotCore

@Test func sliderSnapTakesAValueNearTheDefaultToIt() {
    #expect(SliderSnap.value(0.53, default: 0.5, in: 0...1, threshold: 0.04) == 0.5)
    #expect(SliderSnap.value(0.47, default: 0.5, in: 0...1, threshold: 0.04) == 0.5)
    #expect(SliderSnap.value(190, default: 190, in: 120...320, threshold: 0.04) == 190)
}

@Test func sliderSnapLeavesAValueBeyondTheThreshold() {
    #expect(SliderSnap.value(0.55, default: 0.5, in: 0...1, threshold: 0.04) == 0.55)
    #expect(SliderSnap.value(0.45, default: 0.5, in: 0...1, threshold: 0.04) == 0.45)
}

@Test func sliderSnapMeasuresTheThresholdAcrossTheRange() {
    // 4% of 120...320 is 8.
    #expect(SliderSnap.value(197, default: 190, in: 120...320, threshold: 0.04) == 190)
    #expect(SliderSnap.value(199, default: 190, in: 120...320, threshold: 0.04) == 199)
}

@Test func sliderSnapSnapsToADefaultAtAnEnd() {
    #expect(SliderSnap.value(2, default: 0, in: 0...120, threshold: 0.04) == 0)
    #expect(SliderSnap.value(10, default: 0, in: 0...120, threshold: 0.04) == 10)
}

@Test func sliderSnapNeverSnapsWithoutADefaultOrARange() {
    #expect(SliderSnap.value(0.51, default: nil, in: 0...1, threshold: 0.04) == 0.51)
    #expect(SliderSnap.value(1, default: 1, in: 1...1, threshold: 0.04) == 1)
}

@Test func sliderSnapStepStopsOnTheDefaultItWouldPass() {
    #expect(SliderSnap.stepping(from: 0.004, to: 0.01, default: 0.008) == 0.008)
    #expect(SliderSnap.stepping(from: 0.012, to: 0.0, default: 0.008) == 0.008)
}

@Test func sliderSnapStepLeavesTheDefaultAndStepsShortOfIt() {
    #expect(SliderSnap.stepping(from: 0.5, to: 0.6, default: 0.5) == 0.6)
    #expect(SliderSnap.stepping(from: 0.5, to: 0.4, default: 0.5) == 0.4)
    #expect(SliderSnap.stepping(from: 0.2, to: 0.3, default: 0.5) == 0.3)
    #expect(SliderSnap.stepping(from: 0.4, to: 0.5, default: 0.5) == 0.5)
    #expect(SliderSnap.stepping(from: 0.2, to: 0.3, default: nil) == 0.3)
}
