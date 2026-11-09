import CoreGraphics
import Testing
@testable import ShotCore

private let bar = CGSize(width: 460, height: 38)
private let foot = CGSize(width: 270, height: 34)

@Test func theCropBarSitsCentredAtTheFoot() {
    let origin = CropBar.origin(bar: bar, in: CGSize(width: 1_200, height: 700), foot: foot)
    #expect(origin == CGPoint(x: 370, y: 646))
}

@Test func theCropBarMovesRightWhenCentredWouldReachTheZoomControl() {
    // Centred, it would start at 220, inside the zoom control and Canvas menu, which end at 16 + 270 + 8 = 294.
    let origin = CropBar.origin(bar: bar, in: CGSize(width: 900, height: 700), foot: foot)
    #expect(origin == CGPoint(x: 424, y: 646))
}

@Test func theCropBarSitsAboveTheFootWhenTheCanvasIsTooNarrow() {
    let origin = CropBar.origin(bar: bar, in: CGSize(width: 700, height: 700), foot: foot)
    // Centred, and the zoom control's height, the inset and the gap above the bottom.
    #expect(origin == CGPoint(x: 120, y: 604))
}

@Test func aCanvasNarrowerThanTheCropBarKeepsItAtTheInset() {
    let origin = CropBar.origin(bar: bar, in: CGSize(width: 300, height: 500), foot: foot)
    #expect(origin.x == 16)
}

@Test func theFittedImageClearsTheBar() {
    let canvas = CGSize(width: 1_200, height: 700)
    let origin = CropBar.origin(bar: bar, in: canvas, foot: foot)
    #expect(CropBar.clearance(origin: origin, in: canvas) == 54)
    #expect(CropBar.clearance(origin: CGPoint(x: 0, y: 800), in: canvas) == 0)
}

@Test func theFramesSizeIsTheWholePixelsTheCropKeeps() {
    let content = CGRect(x: 0, y: 0, width: 200, height: 100)
    let draft = CGRect(x: 10.4, y: 20.6, width: 50.2, height: 30)
    #expect(CropBar.keptSize(draft: draft, croppingImage: false, contentRect: content) == CGSize(width: 51, height: 31))
    let past = CGRect(x: 150, y: 50, width: 100, height: 100)
    #expect(CropBar.keptSize(draft: past, croppingImage: false, contentRect: content) == CGSize(width: 50, height: 50))
}

@Test func aPlacedImagesSizeIsTheDraftAsItIs() {
    let draft = CGRect(x: 10.4, y: 20.6, width: 50.2, height: 30)
    #expect(CropBar.keptSize(draft: draft, croppingImage: true, contentRect: .zero) == draft.size)
}
