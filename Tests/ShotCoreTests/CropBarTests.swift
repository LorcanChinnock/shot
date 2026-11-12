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

@Test func theVideoCropBarShowsTheFrameAsItExports() {
    // The frame's crop comes out on even pixels, as the export does.
    let size = CropBar.keptSize(videoDraft: CGRect(x: 10, y: 10, width: 641, height: 359), croppingFrame: true, canvas: CGSize(width: 1280, height: 720))
    #expect(Int(size.width) % 2 == 0 && Int(size.height) % 2 == 0)
    #expect(abs(size.width - 641) <= 1 && abs(size.height - 359) <= 1)
}

@Test func theVideoCropBarShowsAClipsPixelsAsTheyAre() {
    let size = CropBar.keptSize(videoDraft: CGRect(x: 100, y: 50, width: 801, height: 451), croppingFrame: false, canvas: CGSize(width: 1280, height: 720))
    #expect(size == CGSize(width: 801, height: 451))
}

@Test func cropMarksPutAnLOutsideEachCorner() {
    let crop = CGRect(x: 100, y: 100, width: 300, height: 200)
    let corners = CropMarks.corners(of: crop)
    #expect(corners.count == 4)
    // The top-left L starts 3 pt up and left of the corner, runs 18 pt along each side and is 4 pt thick.
    #expect(corners[0] == [
        CGPoint(x: 97, y: 97), CGPoint(x: 115, y: 97), CGPoint(x: 115, y: 101),
        CGPoint(x: 101, y: 101), CGPoint(x: 101, y: 115), CGPoint(x: 97, y: 115),
    ])
    // The bottom-right one mirrors it.
    #expect(corners[3].first == CGPoint(x: 403, y: 303))
    #expect(corners[3][1] == CGPoint(x: 385, y: 303))
}

@Test func cropMarksBarEachSideWithRoom() {
    let crop = CGRect(x: 100, y: 100, width: 300, height: 200)
    let bars = CropMarks.bars(of: crop)
    #expect(bars.count == 4)
    #expect(bars[0] == CGRect(x: 237, y: 96, width: 26, height: 5), "4 pt outside the top, 1 pt in")
    #expect(bars[1] == CGRect(x: 237, y: 299, width: 26, height: 5))
    #expect(bars[2] == CGRect(x: 96, y: 187, width: 5, height: 26))
    #expect(bars[3] == CGRect(x: 399, y: 187, width: 5, height: 26))
}

@Test func cropMarksLeaveOutBarsOnShortSides() {
    // A side needs more than 26 pt for the bar and 18 pt for each corner, 62 pt in all.
    let bars = CropMarks.bars(of: CGRect(x: 0, y: 0, width: 300, height: 62))
    #expect(bars.count == 2)
    #expect(bars.allSatisfy { $0.width == CropMarks.barLength })
    #expect(CropMarks.bars(of: CGRect(x: 0, y: 0, width: 40, height: 40)).isEmpty)
}
