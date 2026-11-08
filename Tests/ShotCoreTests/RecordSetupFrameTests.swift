import CoreGraphics
import Testing
@testable import ShotCore

@Suite struct RecordSetupFrameTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func dimCoversEverythingButTheHole() {
        let hole = CGRect(x: 100, y: 200, width: 300, height: 400)
        let rects = RecordSetupFrame.dimRects(around: hole, in: screen)
        #expect(rects == [
            CGRect(x: 0, y: 0, width: 1000, height: 200),
            CGRect(x: 0, y: 600, width: 1000, height: 200),
            CGRect(x: 0, y: 200, width: 100, height: 400),
            CGRect(x: 400, y: 200, width: 600, height: 400),
        ])
        let area = rects.reduce(0) { $0 + $1.width * $1.height }
        #expect(area == screen.width * screen.height - hole.width * hole.height)
        #expect(rects.allSatisfy { !$0.intersects(hole) })
    }

    @Test func aFullScreenHoleDimsNothing() {
        #expect(RecordSetupFrame.dimRects(around: screen, in: screen).isEmpty)
    }

    @Test func aHoleAgainstAnEdgeLeavesThatSideOut() {
        let rects = RecordSetupFrame.dimRects(around: CGRect(x: 0, y: 0, width: 500, height: 800), in: screen)
        #expect(rects == [CGRect(x: 500, y: 0, width: 500, height: 800)])
    }

    @Test func aHoleOffScreenDimsTheWholeScreen() {
        #expect(RecordSetupFrame.dimRects(around: CGRect(x: 2000, y: 0, width: 100, height: 100), in: screen) == [screen])
    }

    @Test func labelShowsTheSizeAndAKnownRatio() {
        #expect(RecordSetupFrame.label(pixels: CGSize(width: 1040, height: 1040), ratio: 1) == "1040 × 1040 · 1:1")
        #expect(RecordSetupFrame.label(pixels: CGSize(width: 1280, height: 720), ratio: 16.0 / 9) == "1280 × 720 · 16:9")
        #expect(RecordSetupFrame.label(pixels: CGSize(width: 720, height: 1280), ratio: 9.0 / 16) == "720 × 1280 · 9:16")
    }

    @Test func labelLeavesOutAFreeOrUnknownRatio() {
        #expect(RecordSetupFrame.label(pixels: CGSize(width: 800, height: 600), ratio: nil) == "800 × 600")
        #expect(RecordSetupFrame.label(pixels: CGSize(width: 800, height: 600), ratio: 1.9) == "800 × 600")
    }

    @Test func levelBarsLightWithTheLevel() {
        #expect(LevelBars.lit(0) == 0)
        #expect(LevelBars.lit(0.001) == 1)
        #expect(LevelBars.lit(0.55) == 6)
        #expect(LevelBars.lit(1) == LevelBars.count)
        #expect(LevelBars.lit(1.5) == LevelBars.count)
        #expect(LevelBars.lit(0.5, of: 8) == 4)
    }
}
