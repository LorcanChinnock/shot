#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import ShotCore

@Test func quickAccessCardsStackUpFromTheBottomWithTheLastLowest() {
    let layout = QuickAccessLayout(cardHeights: [180, 135])
    #expect(layout.size == CGSize(width: 260, height: 180 + 135 + 14 + 20))
    #expect(layout.cardFrames == [
        CGRect(x: 10, y: 10 + 135 + 14, width: 240, height: 180),
        CGRect(x: 10, y: 10, width: 240, height: 135),
    ])
}

@Test func anEmptyQuickAccessPanelIsJustItsPadding() {
    let layout = QuickAccessLayout(cardHeights: [])
    #expect(layout.size == CGSize(width: 260, height: 20))
    #expect(layout.cardFrames.isEmpty)
}
