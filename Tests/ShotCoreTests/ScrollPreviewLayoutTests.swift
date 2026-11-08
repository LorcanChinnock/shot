import CoreGraphics
import Testing
@testable import ShotCore

private let box = CGSize(width: 150, height: 280)

@Test func beforeTheFirstFrameThePreviewIsAllNotYet() {
    let layout = ScrollPreviewLayout(size: .zero, viewport: .zero, frontier: .bottom, box: box, reserve: 40, growing: true)
    #expect(layout.image == .zero)
    #expect(layout.notYet == CGRect(origin: .zero, size: box))
    #expect(layout.edge == nil)
}

@Test func scrollingDownFillsFromTheTopWithNotYetAndTheEdgeBelow() {
    // A 600 × 400 pixel area scrolled down 400 pixels: the image is 600 × 800, the area at its bottom half.
    let layout = ScrollPreviewLayout(size: CGSize(width: 600, height: 800), viewport: CGRect(x: 0, y: 400, width: 600, height: 400), frontier: .bottom, box: box, reserve: 40, growing: true)
    #expect(layout.image == CGRect(x: 0, y: 0, width: 150, height: 200))
    #expect(layout.notYet == CGRect(x: 0, y: 200, width: 150, height: 80))
    #expect(layout.edge == CGRect(x: 0, y: 199, width: 150, height: 2))
}

@Test func aLongImageShrinksToKeepRoomForNotYet() {
    let layout = ScrollPreviewLayout(size: CGSize(width: 600, height: 4800), viewport: CGRect(x: 0, y: 4400, width: 600, height: 400), frontier: .bottom, box: box, reserve: 40, growing: true)
    #expect(layout.image.height == 240)
    #expect(layout.image.width == 30)
    #expect(layout.image.midX == 75)
    #expect(layout.notYet == CGRect(x: 0, y: 240, width: 150, height: 40))
}

@Test func scrollingUpFillsFromTheBottomWithTheEdgeAbove() {
    let layout = ScrollPreviewLayout(size: CGSize(width: 600, height: 800), viewport: CGRect(x: 0, y: 0, width: 600, height: 400), frontier: .top, box: box, reserve: 40, growing: true)
    #expect(layout.image == CGRect(x: 0, y: 80, width: 150, height: 200))
    #expect(layout.notYet == CGRect(x: 0, y: 0, width: 150, height: 80))
    #expect(layout.edge == CGRect(x: 0, y: 79, width: 150, height: 2))
}

@Test func scrollingRightPutsNotYetAndTheEdgeOnTheRight() {
    let layout = ScrollPreviewLayout(size: CGSize(width: 1200, height: 400), viewport: CGRect(x: 600, y: 0, width: 600, height: 400), frontier: .right, box: box, reserve: 40, growing: true)
    // 1200 × 400 pixels fit 110 points wide, leaving 40 for "Not yet", and sit in the middle top to bottom.
    #expect(abs(layout.image.width - 110) < 0.001)
    #expect(abs(layout.image.height - 110.0 / 3) < 0.001)
    #expect(abs(layout.image.midY - 140) < 0.001)
    #expect(abs((layout.notYet?.minX ?? 0) - 110) < 0.001)
    #expect(abs((layout.edge?.minX ?? 0) - 109) < 0.001)
    #expect(layout.edge?.width == 2)
}

@Test func theEdgeStaysInsideThePreviewAndAFullImageHasNoNotYet() {
    let layout = ScrollPreviewLayout(size: CGSize(width: 600, height: 1120), viewport: CGRect(x: 0, y: 720, width: 600, height: 400), frontier: .bottom, box: box, reserve: 40, growing: false)
    #expect(layout.image == CGRect(x: 0, y: 0, width: 150, height: 280))
    #expect(layout.notYet == nil)
    #expect(layout.edge == CGRect(x: 0, y: 278, width: 150, height: 2))
}

@Test func theFrontierFollowsTheSideTheImageGrewOn() {
    let start = CGSize(width: 600, height: 400)
    #expect(ScrollFrontier.after(.bottom, oldSize: start, newSize: CGSize(width: 600, height: 500), viewport: CGRect(x: 0, y: 0, width: 600, height: 400)) == .top)
    #expect(ScrollFrontier.after(.top, oldSize: start, newSize: CGSize(width: 600, height: 500), viewport: CGRect(x: 0, y: 100, width: 600, height: 400)) == .bottom)
    #expect(ScrollFrontier.after(.bottom, oldSize: start, newSize: CGSize(width: 700, height: 400), viewport: CGRect(x: 100, y: 0, width: 600, height: 400)) == .right)
    #expect(ScrollFrontier.after(.bottom, oldSize: start, newSize: CGSize(width: 700, height: 400), viewport: CGRect(x: 0, y: 0, width: 600, height: 400)) == .left)
    // Scrolling back over what's captured keeps it.
    #expect(ScrollFrontier.after(.top, oldSize: start, newSize: start, viewport: CGRect(x: 0, y: 0, width: 600, height: 400)) == .top)
}
