import Foundation
import Testing
@testable import ShotModel

private let bounds = CGRect(x: -20, y: -20, width: 240, height: 160)
private let crop = CGRect(x: 40, y: 30, width: 100, height: 50)

@Test func cropHandlesAreFoundAtCornersAndSides() {
    #expect(CropGeometry.handle(at: CGPoint(x: 41, y: 31), in: crop, tolerance: 6) == .topLeft)
    #expect(CropGeometry.handle(at: CGPoint(x: 139, y: 79), in: crop, tolerance: 6) == .bottomRight)
    #expect(CropGeometry.handle(at: CGPoint(x: 90, y: 28), in: crop, tolerance: 6) == .top)
    #expect(CropGeometry.handle(at: CGPoint(x: 142, y: 55), in: crop, tolerance: 6) == .right)
    #expect(CropGeometry.handle(at: CGPoint(x: 90, y: 55), in: crop, tolerance: 6) == nil)
}

@Test func cropCornersWinOverTheSidesTheySitOn() {
    let tiny = CGRect(x: 0, y: 0, width: 6, height: 6)
    #expect(CropGeometry.handle(at: CGPoint(x: 1, y: 1), in: tiny, tolerance: 6) == .topLeft)
}

@Test func draggingAHandleOutwardGrowsTheCropUpToTheBounds() {
    let grown = CropGeometry.resize(crop, handle: .left, to: CGPoint(x: 10, y: 55), within: bounds)
    #expect(grown == CGRect(x: 10, y: 30, width: 130, height: 50))
    let past = CropGeometry.resize(crop, handle: .bottomRight, to: CGPoint(x: 900, y: 900), within: bounds)
    #expect(past == CGRect(x: 40, y: 30, width: 180, height: 110))
}

@Test func draggingAnEdgePastTheOppositeOneStopsAtTheMinimumSize() {
    let squashed = CropGeometry.resize(crop, handle: .right, to: CGPoint(x: 0, y: 0), within: bounds)
    #expect(squashed.width == CropGeometry.minimumSize)
    #expect(squashed.minX == 40)
    let top = CropGeometry.resize(crop, handle: .top, to: CGPoint(x: 0, y: 500), within: bounds)
    #expect(top.maxY == 80 && top.height == CropGeometry.minimumSize)
}

@Test func cropEdgesSnapToTheImageEdges() {
    let snap = CropSnap(xs: [0, 200], ys: [0, 100], tolerance: 4)
    #expect(CropGeometry.resize(crop, handle: .left, to: CGPoint(x: 3, y: 0), within: bounds, snap: snap).minX == 0)
    #expect(CropGeometry.resize(crop, handle: .left, to: CGPoint(x: 8, y: 0), within: bounds, snap: snap).minX == 8)
    #expect(CropGeometry.resize(crop, handle: .bottom, to: CGPoint(x: 0, y: 97), within: bounds, snap: snap).maxY == 100)
    let moved = CropGeometry.move(crop, dx: -38, dy: 0, within: bounds, snap: snap)
    #expect(moved.minX == 0)
    let movedRight = CropGeometry.move(crop, dx: 58, dy: 0, within: bounds, snap: snap)
    #expect(movedRight.maxX == 200)
}

@Test func movingTheCropKeepsItInsideTheBounds() {
    let moved = CropGeometry.move(crop, dx: 1000, dy: -1000, within: bounds)
    #expect(moved == CGRect(x: 120, y: -20, width: 100, height: 50))
}

@Test func aShiftedCornerKeepsTheRatio() {
    let ratio = crop.width / crop.height
    let resized = CropGeometry.resize(crop, handle: .bottomRight, to: CGPoint(x: 200, y: 90), within: bounds, ratio: ratio)
    #expect(resized.minX == 40 && resized.minY == 30)
    #expect(abs(resized.width / resized.height - ratio) < 1e-9)
    let top = CropGeometry.resize(crop, handle: .topLeft, to: CGPoint(x: -1000, y: -1000), within: bounds, ratio: ratio)
    #expect(top.maxX == 140 && top.maxY == 80)
    #expect(bounds.contains(top))
    #expect(abs(top.width / top.height - ratio) < 1e-9)
}

@Test func aSideKeepsTheRatioAboutTheMiddleAndStaysInTheBounds() {
    let wider = CropGeometry.resize(crop, handle: .right, to: CGPoint(x: 160, y: 0), within: bounds, ratio: 2)
    #expect(wider.minX == 40 && wider.width == 120 && wider.height == 60)
    #expect(wider.midY == crop.midY)
    let limited = CropGeometry.resize(crop, handle: .right, to: CGPoint(x: 10_000, y: 0), within: bounds, ratio: 2)
    #expect(bounds.contains(limited))
    #expect(limited.width / limited.height == 2)
    let taller = CropGeometry.resize(crop, handle: .top, to: CGPoint(x: 0, y: 10), within: bounds, ratio: 2)
    #expect(taller.maxY == 80 && taller.height == 70 && taller.width == 140)
    #expect(bounds.contains(taller))
}

@Test func drawingACropFromAPointClampsToTheBounds() {
    let drawn = CropGeometry.draw(from: CGPoint(x: 50, y: 60), to: CGPoint(x: 10, y: 500), within: bounds)
    #expect(drawn == CGRect(x: 10, y: 60, width: 40, height: 80))
    let ratioed = CropGeometry.draw(from: CGPoint(x: 50, y: 20), to: CGPoint(x: 150, y: 30), within: bounds, ratio: 1)
    #expect(ratioed == CGRect(x: 50, y: 20, width: 100, height: 100))
    let squeezed = CropGeometry.draw(from: CGPoint(x: 50, y: 60), to: CGPoint(x: 500, y: 500), within: bounds, ratio: 1)
    #expect(squeezed == CGRect(x: 50, y: 60, width: 80, height: 80))
}

@Test func aRatioFitsTheLargestCropInsideTheCurrentOneCentred() {
    let area = CGRect(x: 10, y: 20, width: 400, height: 300)
    #expect(CropGeometry.fit(ratio: 16 / 9, in: area) == CGRect(x: 10, y: 57, width: 400, height: 225))
    #expect(CropGeometry.fit(ratio: 1, in: area) == CGRect(x: 60, y: 20, width: 300, height: 300))
    #expect(CropGeometry.fit(ratio: 9 / 16, in: area) == CGRect(x: 126, y: 20, width: 168, height: 300))
}

@Test func aRatioFollowsTheCropsOrientation() {
    let landscape = CGSize(width: 300, height: 200), portrait = CGSize(width: 200, height: 300)
    func ratio(_ aspect: CropAspect, _ size: CGSize) -> Double? { aspect.ratio(for: size).map { Double($0) } }
    #expect(ratio(.free, landscape) == nil)
    #expect(ratio(.square, portrait) == 1)
    #expect(abs((ratio(.sixteenNine, landscape) ?? 0) - 16.0 / 9.0) < 1e-9)
    #expect(abs((ratio(.sixteenNine, portrait) ?? 0) - 9.0 / 16.0) < 1e-9)
    #expect(abs((ratio(.fourThree, CGSize(width: 100, height: 100)) ?? 0) - 4.0 / 3.0) < 1e-9)
    #expect(abs((ratio(.fourThree, portrait) ?? 0) - 3.0 / 4.0) < 1e-9)
}
