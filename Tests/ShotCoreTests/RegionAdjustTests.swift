import CoreGraphics
import Testing
@testable import ShotCore

private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
private let rect = CGRect(x: 100, y: 100, width: 400, height: 300)

@Test func cornerAndEdgeResize() {
    #expect(RegionHandle.bottomRight.adjust(rect, by: CGVector(dx: 50, dy: -20), in: bounds) == CGRect(x: 100, y: 80, width: 450, height: 320))
    #expect(RegionHandle.topLeft.adjust(rect, by: CGVector(dx: -30, dy: 40), in: bounds) == CGRect(x: 70, y: 100, width: 430, height: 340))
    #expect(RegionHandle.left.adjust(rect, by: CGVector(dx: 10, dy: 99), in: bounds) == CGRect(x: 110, y: 100, width: 390, height: 300))
    #expect(RegionHandle.top.adjust(rect, by: CGVector(dx: 99, dy: 10), in: bounds) == CGRect(x: 100, y: 100, width: 400, height: 310))
}

@Test func resizeClampsToBoundsAndMinimumSize() {
    #expect(RegionHandle.right.adjust(rect, by: CGVector(dx: 900, dy: 0), in: bounds).maxX == 1000)
    #expect(RegionHandle.right.adjust(rect, by: CGVector(dx: -900, dy: 0), in: bounds).width == 80)
    #expect(RegionHandle.bottomLeft.adjust(rect, by: CGVector(dx: -500, dy: -500), in: bounds).origin == .zero)
}

@Test func moveKeepsSizeInsideBounds() {
    let moved = RegionHandle.move.adjust(rect, by: CGVector(dx: 900, dy: -500), in: bounds)
    #expect(moved == CGRect(x: 600, y: 0, width: 400, height: 300))
}

@Test func anchors() {
    #expect(RegionHandle.topLeft.anchor(in: rect) == CGPoint(x: 100, y: 400))
    #expect(RegionHandle.bottom.anchor(in: rect) == CGPoint(x: 300, y: 100))
}

private let wide = CGRect(x: 100, y: 100, width: 400, height: 200)

@Test func ratioLockedCornerPivotsOnOppositeCorner() {
    let adjusted = RegionHandle.bottomRight.adjust(wide, by: CGVector(dx: 100, dy: 0), in: bounds, ratio: 2)
    #expect(adjusted == CGRect(x: 100, y: 50, width: 500, height: 250))
}

@Test func ratioLockedEdgeGrowsAroundCentreLine() {
    let adjusted = RegionHandle.top.adjust(wide, by: CGVector(dx: 0, dy: 50), in: bounds, ratio: 2)
    #expect(adjusted == CGRect(x: 50, y: 100, width: 500, height: 250))
}

@Test func ratioLockedStaysInBounds() {
    let adjusted = RegionHandle.right.adjust(wide, by: CGVector(dx: 900, dy: 0), in: bounds, ratio: 2)
    #expect(adjusted.maxX <= bounds.maxX && adjusted.minY >= bounds.minY && adjusted.maxY <= bounds.maxY)
    #expect(adjusted.width == adjusted.height * 2)
}
