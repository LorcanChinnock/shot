import CoreGraphics
import Testing
@testable import ShotCore

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
/// What a screen leaves with the menu bar at the top and a Dock that hides itself, which macOS 26 gives no room.
private let hiddenDock = CGRect(x: 0, y: 0, width: 1440, height: 875)

@Test func autoHideDockHeightComesFromItsIconSize() {
    #expect(AutoHideDock.height(autohide: true, orientation: nil, tileSize: 54) == 79)
    #expect(AutoHideDock.height(autohide: true, orientation: "bottom", tileSize: nil) == 89)
}

@Test func aDockThatStaysOrSitsOnASideHasNoHeight() {
    #expect(AutoHideDock.height(autohide: false, orientation: nil, tileSize: 54) == nil)
    #expect(AutoHideDock.height(autohide: true, orientation: "left", tileSize: 54) == nil)
}

@Test func aShowingDockIsTakenOffTheVisibleArea() {
    #expect(AutoHideDock.visible(hiddenDock, in: screen, shownHeight: 79) == CGRect(x: 0, y: 79, width: 1440, height: 796))
    #expect(AutoHideDock.visible(hiddenDock, in: screen, shownHeight: nil) == hiddenDock)
    // Older macOS keeps a 4 pt strip for it.
    let strip = CGRect(x: 0, y: 4, width: 1440, height: 871)
    #expect(AutoHideDock.visible(strip, in: screen, shownHeight: 79) == CGRect(x: 0, y: 79, width: 1440, height: 796))
}

@Test func aDockThatAlwaysShowsKeepsItsRoom() {
    let shownDock = CGRect(x: 0, y: 80, width: 1440, height: 795)
    #expect(AutoHideDock.visible(shownDock, in: screen, shownHeight: 79) == shownDock)
}
