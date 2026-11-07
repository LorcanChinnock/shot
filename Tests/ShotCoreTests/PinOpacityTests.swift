import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

@Test func aPinStartsSolid() {
    #expect(PinOpacity.full == 1)
    #expect(PinOpacity.percent(PinOpacity.full) == 100)
}

@Test func pinOpacityStaysBetweenItsMinimumAndSolid() {
    #expect(PinOpacity.clamped(0) == 0.2)
    #expect(PinOpacity.clamped(1.5) == 1)
    #expect(PinOpacity.clamped(0.55) == 0.55)
    #expect(PinOpacity.clamped(.nan) == 1)
}

@Test func pinOpacityShowsAsAWholePercentage() {
    #expect(PinOpacity.percent(0.8) == 80)
    #expect(PinOpacity.percent(0.834) == 83)
    #expect(PinOpacity.percent(0.836) == 84)
    #expect(PinOpacity.percent(0.05) == 20)
}

@Test func arrowKeysStepPinOpacityToTheNextTenth() {
    #expect(PinOpacity.stepped(0.83, up: true) == 0.9)
    #expect(PinOpacity.stepped(0.83, up: false) == 0.8)
    #expect(PinOpacity.stepped(0.8, up: true) == 0.9)
    #expect(PinOpacity.stepped(0.8, up: false) == 0.7)
    #expect(PinOpacity.stepped(0.7 + 0.1, up: false) == 0.7)
}

@Test func pinOpacityStepsStopAtEachEnd() {
    #expect(PinOpacity.stepped(1, up: true) == 1)
    #expect(PinOpacity.stepped(0.2, up: false) == 0.2)
    #expect(PinOpacity.stepped(0.25, up: false) == 0.2)
}

@Test func thePinBarStripRunsAcrossTheTopWithItsInset() {
    let frame = CGRect(x: 100, y: 200, width: 300, height: 400)
    #expect(PinLayout.barStrip(in: frame, barHeight: 38) == CGRect(x: 100, y: 550, width: 300, height: 50))
}

@Test func thePinBarStripIsNeverTallerThanThePin() {
    let frame = CGRect(x: 0, y: 0, width: 80, height: 30)
    #expect(PinLayout.barStrip(in: frame, barHeight: 38) == frame)
}
