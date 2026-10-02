import CoreGraphics
import Testing
@testable import ShotCore

private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
private let size = CGSize(width: 400, height: 52)

@Test func placesBelowRegionWhenThereIsRoom() {
    let origin = ControlPlacement.origin(for: size, region: CGRect(x: 400, y: 300, width: 600, height: 400), visible: visible)
    #expect(origin == CGPoint(x: 500, y: 234))
}

@Test func placesAboveWhenNoRoomBelow() {
    let origin = ControlPlacement.origin(for: size, region: CGRect(x: 400, y: 20, width: 600, height: 400), visible: visible)
    #expect(origin.y == 434)
}

@Test func placesInsideForFullScreenAndClampsToScreen() {
    let origin = ControlPlacement.origin(for: size, region: visible, visible: visible)
    #expect(origin == CGPoint(x: 520, y: 20))
    let edge = ControlPlacement.origin(for: size, region: CGRect(x: 0, y: 300, width: 100, height: 100), visible: visible)
    #expect(edge.x == 8)
}
