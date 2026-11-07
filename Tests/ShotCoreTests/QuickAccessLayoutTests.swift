import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

@Test func fannedOutQuickAccessCardsStackUpFromTheBottomWithTheNewestLowest() {
    let layout = QuickAccessLayout(cardHeights: [210, 158], fannedOut: true)
    #expect(layout.size == CGSize(width: 300, height: 402))
    #expect(layout.cardFrames == [
        CGRect(x: 10, y: 182, width: 280, height: 210),
        CGRect(x: 10, y: 10, width: 280, height: 158),
    ])
    #expect(layout.placements.allSatisfy { !$0.isBehind })
}

@Test func atRestTheNewestQuickAccessCardIsInFrontWhereItIsWhenFannedOut() {
    let resting = QuickAccessLayout(cardHeights: [210, 158], fannedOut: false)
    let fanned = QuickAccessLayout(cardHeights: [210, 158], fannedOut: true)
    #expect(resting.placements[1] == fanned.placements[1])
    #expect(resting.placements[1].scale == 1)
}

@Test func atRestOlderQuickAccessCardsShrinkBehindTheFrontOneAndShowTheirTopEdge() {
    let layout = QuickAccessLayout(cardHeights: [210, 158], fannedOut: false)
    let behind = layout.placements[0]
    #expect(behind.isBehind)
    #expect(behind.scale == 0.94)
    // It takes the front card's height, so none of it shows below the front card.
    #expect(behind.height == 158)
    // 14 pt above the front card's top at 168, and 94% of the front card's size.
    #expect(behind.frame == CGRect(x: 19, y: 33, width: 263, height: 149))
    #expect(layout.size == CGSize(width: 300, height: 192))
}

@Test func atRestEveryOlderQuickAccessCardSitsInTheSamePlaceBehind() {
    let layout = QuickAccessLayout(cardHeights: [175, 210, 190, 158], fannedOut: false)
    #expect(layout.placements[0] == layout.placements[2])
    #expect(layout.placements[1] == layout.placements[2])
    #expect(layout.placements[3].isBehind == false)
}

@Test func aSingleQuickAccessCardHasNothingShowingAboveIt() {
    let layout = QuickAccessLayout(cardHeights: [175], fannedOut: false)
    #expect(layout.size == CGSize(width: 300, height: 195))
    #expect(layout == QuickAccessLayout(cardHeights: [175], fannedOut: true))
}

@Test func anEmptyQuickAccessPanelIsJustItsPadding() {
    let layout = QuickAccessLayout(cardHeights: [], fannedOut: false)
    #expect(layout.size == CGSize(width: 300, height: 20))
    #expect(layout.cardFrames.isEmpty)
}

@Test func aPointOnTheStripAboveTheFrontCardFindsTheCardBehind() {
    let layout = QuickAccessLayout(cardHeights: [210, 158], fannedOut: false)
    #expect(layout.card(at: CGPoint(x: 150, y: 175)) == 0)
}

@Test func aPointWhereCardsOverlapFindsTheFrontOne() {
    let layout = QuickAccessLayout(cardHeights: [210, 158], fannedOut: false)
    #expect(layout.card(at: CGPoint(x: 150, y: 100)) == 1)
}

@Test func aPointBetweenFannedOutCardsFindsNoCard() {
    let layout = QuickAccessLayout(cardHeights: [210, 158], fannedOut: true)
    #expect(layout.card(at: CGPoint(x: 150, y: 175)) == nil)
    #expect(layout.card(at: CGPoint(x: 150, y: 200)) == 0)
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
