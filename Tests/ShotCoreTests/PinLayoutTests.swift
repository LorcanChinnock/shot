import CoreGraphics
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

@Test func aPinFromACardStartsInsideTheCardAtThePinsShape() {
    let card = CGRect(x: 1000, y: 30, width: 280, height: 175)
    // A wide pin takes the card's width and is centred up and down.
    let wide = PinLayout.launchFrame(for: CGRect(x: 400, y: 300, width: 800, height: 400), from: card)
    #expect(wide == CGRect(x: 1000, y: 48, width: 280, height: 140))
    // A tall pin takes the card's height and is centred across.
    let tall = PinLayout.launchFrame(for: CGRect(x: 0, y: 0, width: 300, height: 600), from: card)
    #expect(tall.height == 175)
    #expect(abs(tall.midX - card.midX) <= 0.5)
    #expect(card.contains(tall))
}

@Test func aPinWithNoSizeStartsAsTheCard() {
    let card = CGRect(x: 10, y: 10, width: 280, height: 158)
    #expect(PinLayout.launchFrame(for: .zero, from: card) == card)
}
