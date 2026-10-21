#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import ShotCore

private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

@Test func aSmallCaptureIsPinnedAtItsOwnSizeInTheMiddle() {
    let frame = PinLayout.initialFrame(for: CGSize(width: 400, height: 300), in: screen, index: 0)
    #expect(frame == CGRect(x: 600, y: 350, width: 400, height: 300))
}

@Test func aLargeCaptureShrinksToHalfTheScreenKeepingItsAspect() {
    let size = PinLayout.size(for: CGSize(width: 3200, height: 1000), in: screen)
    #expect(size == CGSize(width: 800, height: 250))
    let tall = PinLayout.size(for: CGSize(width: 500, height: 2000), in: screen)
    #expect(tall == CGSize(width: 125, height: 500))
}

@Test func aTinyCaptureGrowsToTheMinimumSide() {
    #expect(PinLayout.size(for: CGSize(width: 40, height: 20), in: screen) == CGSize(width: 160, height: 80))
}

@Test func aLongThinCaptureStillFitsOnScreen() {
    let size = PinLayout.size(for: CGSize(width: 10000, height: 10), in: screen)
    #expect(size.width <= screen.width)
    #expect(size.height <= screen.height)
}

@Test func furtherPinsCascadeDownAndRightThenWrap() {
    let image = CGSize(width: 400, height: 300)
    let second = PinLayout.initialFrame(for: image, in: screen, index: 1)
    #expect(second.origin == CGPoint(x: 628, y: 322))
    // 350 points below the centred pin fit 12 more steps of 28 before it would leave the screen.
    #expect(PinLayout.initialFrame(for: image, in: screen, index: 13) == PinLayout.initialFrame(for: image, in: screen, index: 0))
    for index in 0..<40 {
        #expect(screen.contains(PinLayout.initialFrame(for: image, in: screen, index: index)))
    }
}

@Test func anEmptyImageGetsAMinimumSquare() {
    #expect(PinLayout.size(for: .zero, in: screen) == CGSize(width: 80, height: 80))
}
