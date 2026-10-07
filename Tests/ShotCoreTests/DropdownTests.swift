import CoreGraphics
import Testing
@testable import ShotCore

private let pickable = [true, false, true, true, false]

@Test func stepSkipsWhatCantBePickedAndWraps() {
    #expect(Dropdown.step(from: 0, by: 1, pickable: pickable) == 2)
    #expect(Dropdown.step(from: 3, by: 1, pickable: pickable) == 0)
    #expect(Dropdown.step(from: 0, by: -1, pickable: pickable) == 3)
    #expect(Dropdown.step(from: 2, by: -1, pickable: pickable) == 0)
}

@Test func stepFromNothingStartsAtAnEnd() {
    #expect(Dropdown.step(from: nil, by: 1, pickable: pickable) == 0)
    #expect(Dropdown.step(from: nil, by: -1, pickable: pickable) == 3)
    #expect(Dropdown.step(from: nil, by: 1, pickable: [false, false]) == nil)
    #expect(Dropdown.step(from: nil, by: 1, pickable: []) == nil)
}

@Test func matchFindsTheTypedPrefixFromTheCurrentItem() {
    let titles: [String?] = ["Zoom In", nil, "Zoom Out", "Actual Size", "Zoom to Fit"]
    #expect(Dropdown.match("zoom", titles: titles, from: nil) == 0)
    #expect(Dropdown.match("zoom", titles: titles, from: 2) == 2)
    #expect(Dropdown.match("zoom", titles: titles, from: 3) == 4)
    #expect(Dropdown.match("a", titles: titles, from: 4) == 3)
    #expect(Dropdown.match("q", titles: titles, from: nil) == nil)
    #expect(Dropdown.match("", titles: titles, from: nil) == nil)
}

@Test func originSitsUnderTheAnchorOrAboveWhenThereIsNoRoom() {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 200, height: 300)
    #expect(Dropdown.origin(size: size, anchor: CGRect(x: 100, y: 600, width: 80, height: 30), visible: visible, gap: 8) == CGPoint(x: 100, y: 292))
    #expect(Dropdown.origin(size: size, anchor: CGRect(x: 100, y: 100, width: 80, height: 30), visible: visible, gap: 8) == CGPoint(x: 100, y: 138))
}

@Test func originStaysOnScreen() {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 200, height: 300)
    #expect(Dropdown.origin(size: size, anchor: CGRect(x: 900, y: 600, width: 80, height: 30), visible: visible, gap: 8).x == 800)
    #expect(Dropdown.origin(size: size, anchor: CGRect(x: -50, y: 600, width: 80, height: 30), visible: visible, gap: 8).x == 0)
    #expect(Dropdown.origin(size: CGSize(width: 200, height: 700), anchor: CGRect(x: 100, y: 300, width: 80, height: 30), visible: visible, gap: 8).y == 100)
}
