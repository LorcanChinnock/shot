import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let bar = CGSize(width: 300, height: 38)

private func place(
    _ aim: OverlayBarPlacement.Aim?, dragging: Bool = false, current: OverlayBarPlacement = .bottom, pointerOnBar: Bool = false
) -> OverlayBarPlacement {
    OverlayBarPlacement.placement(for: bar, in: screen, avoiding: aim, dragging: dragging, current: current, pointerOnBar: pointerOnBar)
}

@Test func overlayBarFramesSitAnInsetFromEachEdge() {
    #expect(OverlayBarPlacement.bottom.frame(of: bar, in: screen) == CGRect(x: 570, y: 56, width: 300, height: 38))
    #expect(OverlayBarPlacement.top.frame(of: bar, in: screen) == CGRect(x: 570, y: 806, width: 300, height: 38))
    #expect(OverlayBarPlacement.hidden.frame(of: bar, in: screen) == nil)
}

@Test func overlayBarSitsAtTheBottomWithNothingUnderIt() {
    #expect(place(nil) == .bottom)
    #expect(place(.area(CGRect(x: 100, y: 200, width: 400, height: 300))) == .bottom)
}

@Test func overlayBarHidesWhileAnAreaIsDraggedOut() {
    #expect(place(nil, dragging: true) == .hidden)
    #expect(place(.area(CGRect(x: 100, y: 200, width: 40, height: 30)), dragging: true, pointerOnBar: true) == .hidden)
}

@Test func overlayBarMovesUpWhenAnAreaReachesIt() {
    #expect(place(.area(CGRect(x: 600, y: 80, width: 200, height: 200))) == .top)
    // Within the clearance counts as touching.
    #expect(place(.area(CGRect(x: 600, y: 100, width: 200, height: 200))) == .top)
    // Beside the bar, even at the same height, leaves it at the bottom.
    #expect(place(.area(CGRect(x: 10, y: 10, width: 300, height: 200))) == .bottom)
}

@Test func overlayBarHidesWhenAnAreaSpansBothEdges() {
    #expect(place(.area(CGRect(x: 650, y: 40, width: 100, height: 820))) == .hidden)
    #expect(place(.area(CGRect(x: 650, y: 300, width: 100, height: 100)), current: .hidden) == .bottom)
}

@Test func overlayBarStaysOverALargeWindowItCoversOnlyAStripOf() {
    #expect(place(.target(CGRect(x: 0, y: 0, width: 1440, height: 875))) == .bottom)
}

@Test func overlayBarMovesOffASmallWindowItWouldMostlyCover() {
    #expect(place(.target(CGRect(x: 600, y: 40, width: 200, height: 80))) == .top)
    // A window that only grazes the bar keeps it at the bottom.
    #expect(place(.target(CGRect(x: 600, y: 80, width: 200, height: 400))) == .bottom)
}

@Test func overlayBarStaysPutUnderThePointer() {
    let under = OverlayBarPlacement.Aim.target(CGRect(x: 600, y: 40, width: 200, height: 80))
    #expect(place(under, current: .bottom, pointerOnBar: true) == .bottom)
    #expect(place(nil, current: .top, pointerOnBar: true) == .top)
    #expect(place(nil, current: .hidden, pointerOnBar: true) == .bottom)
}
