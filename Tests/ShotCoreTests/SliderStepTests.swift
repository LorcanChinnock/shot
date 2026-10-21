import Foundation
import Testing
@testable import ShotCore

@Test func sliderStepMovesOneMarkFromAMark() {
    #expect(abs(SliderStep.value(0.44, up: true, fraction: 0.01, in: 0...1) - 0.45) < 1e-9)
    #expect(abs(SliderStep.value(0.44, up: false, fraction: 0.01, in: 0...1) - 0.43) < 1e-9)
}

@Test func sliderStepLandsOnTheNextMarkFromBetweenMarks() {
    #expect(abs(SliderStep.value(0.437, up: true, fraction: 0.01, in: 0...1) - 0.44) < 1e-9)
    #expect(abs(SliderStep.value(0.437, up: false, fraction: 0.01, in: 0...1) - 0.43) < 1e-9)
}

@Test func sliderStepScalesToTheRange() {
    #expect(abs(SliderStep.value(4, up: true, fraction: 0.1, in: 2...22) - 6) < 1e-9)
    #expect(abs(SliderStep.value(5, up: false, fraction: 0.1, in: 2...22) - 4) < 1e-9)
}

@Test func sliderStepStopsAtTheEnds() {
    #expect(SliderStep.value(1, up: true, fraction: 0.01, in: 0...1) == 1)
    #expect(SliderStep.value(0.995, up: true, fraction: 0.01, in: 0...1) == 1)
    #expect(SliderStep.value(0, up: false, fraction: 0.1, in: 0...1) == 0)
    #expect(SliderStep.value(-3, up: true, fraction: 0.1, in: 0...1) == 0.1)
}

@Test func sliderStepRepeatedStaysOnWholePercentages() {
    var value = 0.0
    for _ in 0..<37 {
        value = SliderStep.value(value, up: true, fraction: 0.01, in: 0...1)
    }
    #expect(abs(value - 0.37) < 1e-9)
    for _ in 0..<200 {
        value = SliderStep.value(value, up: true, fraction: 0.01, in: 0...1)
    }
    #expect(value == 1)
}
