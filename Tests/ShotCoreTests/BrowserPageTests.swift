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
