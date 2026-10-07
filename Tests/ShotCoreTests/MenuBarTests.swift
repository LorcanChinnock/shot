import CoreGraphics
import Testing
@testable import ShotCore

private let builtIn = CGRect(x: -1512, y: 0, width: 1512, height: 982)

@Test func menuBarHeightIsTheMenuBarOrTheNotch() {
    let visible = CGRect(x: -1512, y: 0, width: 1512, height: 950)
    #expect(MenuBar.height(screenFrame: builtIn, visibleFrame: visible, safeAreaTop: 32) == 32)
    #expect(MenuBar.height(screenFrame: builtIn, visibleFrame: builtIn, safeAreaTop: 32) == 32)
    #expect(MenuBar.height(screenFrame: builtIn, visibleFrame: visible, safeAreaTop: 0) == 32)
    #expect(MenuBar.height(screenFrame: builtIn, visibleFrame: builtIn, safeAreaTop: 0) == 0)
}

@Test func frameBelowDropsTheTopStrip() {
    #expect(MenuBar.frameBelow(screenFrame: builtIn, height: 32) == CGRect(x: -1512, y: 0, width: 1512, height: 950))
}

@Test func notchSitsBetweenTheMenuBarAreas() {
    let left = CGRect(x: -1512, y: 950, width: 663, height: 32)
    let right = CGRect(x: -664, y: 950, width: 664, height: 32)
    #expect(MenuBar.notch(safeAreaTop: 32, leftArea: left, rightArea: right) == CGRect(x: -849, y: 950, width: 185, height: 32))
    #expect(MenuBar.notch(safeAreaTop: 0, leftArea: left, rightArea: right) == nil)
    #expect(MenuBar.notch(safeAreaTop: 32, leftArea: nil, rightArea: nil) == nil)
}
