import CoreGraphics
import ShotCore
import Testing

@Suite struct QuickAccessPreviewTests {
    // 720 pt wide pictures the 1440 pt display at half size, and the height limit makes the preview 340 pt tall.
    private let size = CGSize(width: 720, height: 340)

    @Test func heightIsHalfTheWidthWithinLimits() {
        #expect(QuickAccessPreviewLayout.height(forWidth: 520) == 260)
        #expect(QuickAccessPreviewLayout.height(forWidth: 300) == 200)
        #expect(QuickAccessPreviewLayout.height(forWidth: 900) == 340)
    }

    @Test func placesTheCardAsThePanelDoesInTheBottomLeft() {
        let layout = QuickAccessPreviewLayout(size: size, position: .left)
        #expect(layout.scale == 0.5)
        // 280 × 175 pt, its edge 30 pt in from the side and bottom: 20 for the panel and 10 for its padding.
        #expect(layout.card == CGRect(x: 15, y: 237.5, width: 140, height: 87.5))
        #expect(layout.cardRadius == 7)
        #expect(layout.slide == -160)
    }

    @Test func mirrorsTheCardInTheBottomRight() {
        let layout = QuickAccessPreviewLayout(size: size, position: .right)
        #expect(layout.card == CGRect(x: 565, y: 237.5, width: 140, height: 87.5))
        #expect(layout.card.maxX == size.width - 15)
        #expect(layout.slide == 160)
    }

    @Test func centresTheWindowUnderTheMenuBar() {
        let layout = QuickAccessPreviewLayout(size: size, position: .left)
        #expect(layout.menuBar == CGRect(x: 0, y: 0, width: 720, height: 12))
        #expect(layout.window == CGRect(x: 171, y: 47, width: 378, height: 238))
        #expect(!layout.window.intersects(layout.card))
    }

    @Test func shortensTheWindowInAShortPreview() {
        let layout = QuickAccessPreviewLayout(size: CGSize(width: 720, height: 200), position: .right)
        #expect(layout.window.height == 141)
        #expect(layout.window.maxY == 188)
        #expect(abs(layout.window.width / layout.window.height - 756 / 476) < 1e-9)
        #expect(abs(layout.window.midX - 360) < 1e-9)
        #expect(layout.card.maxY == 185)
    }

    @Test func countsWholeSecondsDown() {
        #expect(QuickAccessPreviewLayout.secondsLeft(duration: 8, elapsed: 0) == 8)
        #expect(QuickAccessPreviewLayout.secondsLeft(duration: 8, elapsed: 0.25) == 8)
        #expect(QuickAccessPreviewLayout.secondsLeft(duration: 8, elapsed: 1) == 7)
        #expect(QuickAccessPreviewLayout.secondsLeft(duration: 8, elapsed: 7.5) == 1)
        #expect(QuickAccessPreviewLayout.secondsLeft(duration: 8, elapsed: 9) == 0)
        #expect(QuickAccessPreviewLayout.secondsLeft(duration: 0, elapsed: 0) == 0)
    }
}
