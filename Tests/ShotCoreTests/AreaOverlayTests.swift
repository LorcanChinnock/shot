import CoreGraphics
import Testing
@testable import ShotCore

private let screen = CGRect(x: 0, y: 0, width: 1280, height: 800)

// MARK: Handles

@Test func aLargeAreaHasHandlesAtItsCornersAndMiddles() {
    let points = AreaHandles.points(around: CGRect(x: 100, y: 100, width: 400, height: 200))
    #expect(points.count == 8)
    #expect(points.contains(CGPoint(x: 300, y: 300)))
    #expect(points.contains(CGPoint(x: 500, y: 200)))
}

@Test func aNarrowAreaDropsTheMiddleHandlesOfItsShortSides() {
    let points = AreaHandles.points(around: CGRect(x: 0, y: 0, width: 30, height: 200))
    // Corners, plus the middles of the long left and right sides only.
    #expect(points.count == 6)
    #expect(!points.contains(CGPoint(x: 15, y: 0)))
    #expect(points.contains(CGPoint(x: 0, y: 100)))
}

@Test func aTinyAreaHasNoHandles() {
    #expect(AreaHandles.points(around: CGRect(x: 0, y: 0, width: 6, height: 10)).isEmpty)
}

// MARK: Chips

@Test func chipsSitAboveTheAreasTopLeftCorner() {
    let area = CGRect(x: 622, y: 238, width: 496, height: 220)
    let frame = AreaLabelPlacement.frame(of: CGSize(width: 180, height: 21), for: area, in: screen)
    #expect(frame.minX == 622)
    #expect(frame.minY == 472)
}

@Test func chipsGoBelowAnAreaAtTheTopOfTheScreen() {
    let area = CGRect(x: 100, y: 500, width: 300, height: 290)
    let frame = AreaLabelPlacement.frame(of: CGSize(width: 180, height: 21), for: area, in: screen)
    #expect(frame.maxY == 486)
}

@Test func chipsGoInsideAnAreaThatFillsTheScreensHeight() {
    let frame = AreaLabelPlacement.frame(of: CGSize(width: 180, height: 21), for: screen, in: screen)
    #expect(screen.insetBy(dx: 8, dy: 8).contains(frame))
    #expect(frame.maxY == 784)
}

@Test func chipsStayOnScreenAtTheRightEdge() {
    let area = CGRect(x: 1250, y: 200, width: 30, height: 100)
    let frame = AreaLabelPlacement.frame(of: CGSize(width: 180, height: 21), for: area, in: screen)
    #expect(frame.maxX == 1272)
}

@Test func chipsKeepOffTheBar() {
    let area = CGRect(x: 400, y: 600, width: 300, height: 100)
    let bar = CGRect(x: 300, y: 700, width: 600, height: 46)
    let frame = AreaLabelPlacement.frame(of: CGSize(width: 180, height: 21), for: area, in: screen, avoiding: [bar])
    #expect(!frame.intersects(bar))
    #expect(frame.maxY == 586)
}

// MARK: Loupe

@Test func theLoupeCentresOnTheDevicePixelUnderThePointer() {
    let pixel = Loupe.pixel(at: CGPoint(x: 10.3, y: 790.2), viewHeight: 800, scale: 2, imageSize: CGSize(width: 2560, height: 1600))
    #expect(pixel.x == 20)
    #expect(pixel.y == 19)
    #expect(Loupe.source(around: pixel) == CGRect(x: 15, y: 14, width: 11, height: 11))
}

@Test func thePixelUnderThePointerStaysOnTheImageAtItsFarEdge() {
    let pixel = Loupe.pixel(at: CGPoint(x: 1280, y: 0), viewHeight: 800, scale: 2, imageSize: CGSize(width: 2560, height: 1600))
    #expect(pixel.x == 2559)
    #expect(pixel.y == 1599)
}

@Test func aLoupeAtTheImagesCornerKeepsItsPixelsInTheirCells() throws {
    let loupe = CGRect(x: 0, y: 0, width: 132, height: 132)
    // Centred on the top-left pixel: the five pixels above and to the left are off the image.
    let source = Loupe.source(around: (0, 0))
    let placed = try #require(Loupe.destination(of: source, imageSize: CGSize(width: 100, height: 100), in: loupe))
    #expect(placed.crop == CGRect(x: 0, y: 0, width: 6, height: 6))
    // Cells are 12 pt, so the image starts 60 pt in from the left and stops 60 pt down from the top.
    #expect(placed.rect == CGRect(x: 60, y: 0, width: 72, height: 72))
}

@Test func aLoupeWhollyOffTheImageDrawsNoPixels() {
    #expect(Loupe.destination(of: CGRect(x: -20, y: 0, width: 11, height: 11), imageSize: CGSize(width: 100, height: 100), in: screen) == nil)
}

@Test func theLoupeSitsBelowAndRightOfThePointer() {
    let frame = Loupe.frame(side: 132, outset: 4.5, at: CGPoint(x: 600, y: 400), right: true, up: false, in: screen)
    #expect(frame == CGRect(x: 622, y: 246, width: 132, height: 132))
}

@Test func theLoupeTurnsTheCornerAtTheScreensEdge() {
    let frame = Loupe.frame(side: 132, outset: 4.5, at: CGPoint(x: 1250, y: 30), right: true, up: false, in: screen)
    #expect(frame.maxX == 1228)
    #expect(frame.minY == 52)
}

@Test func theLoupeKeepsOffTheChips() {
    let chips = CGRect(x: 620, y: 200, width: 200, height: 60)
    let frame = Loupe.frame(side: 132, outset: 4.5, at: CGPoint(x: 600, y: 400), right: true, up: false, in: screen, avoiding: [chips])
    #expect(!frame.insetBy(dx: -4.5, dy: -4.5).intersects(chips))
    #expect(frame.minX == 446)
}
