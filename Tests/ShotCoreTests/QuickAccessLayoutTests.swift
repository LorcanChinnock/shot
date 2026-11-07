import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

@Test func quickAccessCardsStackUpFromTheBottomWithTheLastLowest() {
    let layout = QuickAccessLayout(cardHeights: [210, 158])
    #expect(layout.size == CGSize(width: 300, height: 210 + 158 + 14 + 20))
    #expect(layout.cardFrames == [
        CGRect(x: 10, y: 10 + 158 + 14, width: 280, height: 210),
        CGRect(x: 10, y: 10, width: 280, height: 158),
    ])
}

@Test func anEmptyQuickAccessPanelIsJustItsPadding() {
    let layout = QuickAccessLayout(cardHeights: [])
    #expect(layout.size == CGSize(width: 300, height: 20))
    #expect(layout.cardFrames.isEmpty)
}

@Test func aSixteenByTenCaptureGetsTheBoardsCardHeight() {
    #expect(QuickAccessLayout.cardHeight(for: CGSize(width: 1440, height: 900)) == 175)
}

@Test func aTallCaptureIsCroppedToTheTallestCard() {
    #expect(QuickAccessLayout.cardHeight(for: CGSize(width: 400, height: 1200)) == 210)
}

@Test func aWideCaptureIsCroppedToTheShortestCard() {
    #expect(QuickAccessLayout.cardHeight(for: CGSize(width: 3000, height: 400)) == 158)
}

@Test func aPictureWithNoSizeGetsTheTallestCard() {
    #expect(QuickAccessLayout.cardHeight(for: .zero) == 210)
}
