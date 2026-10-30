import CoreGraphics
import Testing
@testable import ShotCore

struct BrowserPageTests {
    let window = CGRect(x: 100, y: 50, width: 1200, height: 800)

    @Test func picksTheLargestWebArea() {
        let page = CGRect(x: 100, y: 130, width: 1200, height: 720)
        let frame = CGRect(x: 200, y: 300, width: 400, height: 300)
        #expect(BrowserPage.page(among: [frame, page], inside: window) == page)
    }

    @Test func clipsAWebAreaThatSpillsOutOfTheWindow() {
        let spill = CGRect(x: 100, y: 130, width: 1200, height: 2000)
        #expect(BrowserPage.page(among: [spill], inside: window) == CGRect(x: 100, y: 130, width: 1200, height: 720))
    }

    @Test func ignoresTinyAndOutsideAreas() {
        let tiny = CGRect(x: 150, y: 150, width: 40, height: 40)
        let outside = CGRect(x: 5000, y: 5000, width: 800, height: 600)
        #expect(BrowserPage.page(among: [tiny, outside], inside: window) == nil)
    }

    @Test func nilWithoutWebAreas() {
        #expect(BrowserPage.page(among: [], inside: window) == nil)
    }
}

struct PageInsetsTests {
    @Test func aResizedWindowKeepsItsToolbarHeight() {
        let window = CGRect(x: 100, y: 50, width: 1200, height: 800)
        let insets = PageInsets(window: window, page: CGRect(x: 100, y: 130, width: 1200, height: 720))
        let resized = CGRect(x: 300, y: 200, width: 900, height: 600)
        #expect(insets.page(in: resized) == CGRect(x: 300, y: 280, width: 900, height: 520))
    }

    @Test func aWindowShrunkBelowItsChromeStillHasAPage() {
        let insets = PageInsets(window: CGRect(x: 0, y: 0, width: 1000, height: 800), page: CGRect(x: 0, y: 700, width: 1000, height: 100))
        #expect(insets.page(in: CGRect(x: 0, y: 0, width: 500, height: 300)).height == 1)
    }
}

struct AspectFitTests {
    @Test func aWiderShapeIsLetterboxed() {
        let rect = AspectFit.rect(for: CGSize(width: 200, height: 50), in: CGSize(width: 100, height: 100))
        #expect(rect == CGRect(x: 0, y: 37.5, width: 100, height: 25))
    }

    @Test func aTallerShapeIsPillarboxed() {
        let rect = AspectFit.rect(for: CGSize(width: 50, height: 200), in: CGSize(width: 100, height: 100))
        #expect(rect == CGRect(x: 37.5, y: 0, width: 25, height: 100))
    }
}
