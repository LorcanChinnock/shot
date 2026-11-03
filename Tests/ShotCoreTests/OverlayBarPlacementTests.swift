import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let block = CGSize(width: 700, height: 74)

private func place(_ aim: OverlayBarPlacement.Aim?, current: OverlayBarPlacement = .top, pointerOnChip: Bool = false) -> OverlayBarPlacement {
    OverlayBarPlacement.placement(for: block, in: screen, avoiding: aim, current: current, pointerOnChip: pointerOnChip)
}

@Test func overlayBarFramesSitAnInsetFromEachEdge() {
    #expect(OverlayBarPlacement.top.frame(of: block, in: screen) == CGRect(x: 370, y: 762, width: 700, height: 74))
    #expect(OverlayBarPlacement.bottom.frame(of: block, in: screen) == CGRect(x: 370, y: 64, width: 700, height: 74))
    #expect(OverlayBarPlacement.hidden.frame(of: block, in: screen) == nil)
}

@Test func overlayBarStaysAtTheTopWithNothingUnderIt() {
    #expect(place(nil) == .top)
    #expect(place(.area(CGRect(x: 100, y: 200, width: 400, height: 300))) == .top)
}

@Test func overlayBarMovesDownWhenAnAreaReachesIt() {
    #expect(place(.area(CGRect(x: 500, y: 600, width: 200, height: 170))) == .bottom)
    // Within the clearance counts as touching.
    #expect(place(.area(CGRect(x: 500, y: 600, width: 200, height: 155))) == .bottom)
    // Beside the block, even at the same height, leaves it at the top.
    #expect(place(.area(CGRect(x: 10, y: 700, width: 300, height: 190))) == .top)
}

@Test func overlayBarHidesWhenAnAreaSpansBothEdges() {
    #expect(place(.area(CGRect(x: 600, y: 40, width: 100, height: 820))) == .hidden)
    #expect(place(.area(CGRect(x: 600, y: 300, width: 100, height: 100)), current: .hidden) == .top)
}

@Test func overlayBarStaysOverALargeWindowItCoversOnlyAStripOf() {
    #expect(place(.target(CGRect(x: 0, y: 0, width: 1440, height: 875))) == .top)
}

@Test func overlayBarMovesOffASmallWindowItWouldMostlyCover() {
    #expect(place(.target(CGRect(x: 600, y: 720, width: 300, height: 140))) == .bottom)
    // A window that only grazes the block keeps it at the top.
    #expect(place(.target(CGRect(x: 600, y: 300, width: 300, height: 480))) == .top)
}

@Test func overlayBarStaysPutUnderThePointer() {
    let under = OverlayBarPlacement.Aim.target(CGRect(x: 600, y: 720, width: 300, height: 140))
    #expect(place(under, current: .top, pointerOnChip: true) == .top)
    #expect(place(nil, current: .bottom, pointerOnChip: true) == .bottom)
    #expect(place(nil, current: .hidden, pointerOnChip: true) == .top)
}
