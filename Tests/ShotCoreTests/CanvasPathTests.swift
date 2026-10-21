import Foundation
import Testing
@testable import ShotCore

@Test func aCanvasPathKeepsItsStepsInOrder() {
    var path = CanvasPath()
    #expect(path.isEmpty)
    path.move(to: CGPoint(x: 1, y: 2))
    path.addLine(to: CGPoint(x: 3, y: 4))
    path.addQuadCurve(to: CGPoint(x: 5, y: 6), control: CGPoint(x: 7, y: 8))
    path.addCurve(to: CGPoint(x: 9, y: 10), control1: CGPoint(x: 11, y: 12), control2: CGPoint(x: 13, y: 14))
    path.addArc(tangent1End: CGPoint(x: 15, y: 16), tangent2End: CGPoint(x: 17, y: 18), radius: 2)
    path.addRect(CGRect(x: 0, y: 0, width: 5, height: 5))
    path.closeSubpath()
    #expect(path.elements == [
        .move(to: CGPoint(x: 1, y: 2)),
        .line(to: CGPoint(x: 3, y: 4)),
        .quadCurve(to: CGPoint(x: 5, y: 6), control: CGPoint(x: 7, y: 8)),
        .curve(to: CGPoint(x: 9, y: 10), control1: CGPoint(x: 11, y: 12), control2: CGPoint(x: 13, y: 14)),
        .arc(tangent1End: CGPoint(x: 15, y: 16), tangent2End: CGPoint(x: 17, y: 18), radius: 2),
        .rect(CGRect(x: 0, y: 0, width: 5, height: 5)),
        .close,
    ])
}

@Test func linesBetweenPointsStartASubpathAtTheFirst() {
    var path = CanvasPath()
    path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 3)])
    #expect(path.elements == [.move(to: CGPoint(x: 0, y: 0)), .line(to: CGPoint(x: 4, y: 0)), .line(to: CGPoint(x: 4, y: 3))])
    path.addLines(between: [])
    #expect(path.elements.count == 3)
}

@Test func rectsEllipsesAndRoundedRectsStayWhole() {
    let rect = CGRect(x: 2, y: 3, width: 40, height: 30)
    #expect(CanvasPath(rect: rect).elements == [.rect(rect)])
    #expect(CanvasPath(ellipseIn: rect).elements == [.ellipse(in: rect)])
    #expect(CanvasPath(roundedRect: rect, cornerRadius: 6).elements == [.roundedRect(rect, cornerWidth: 6, cornerHeight: 6)])
}

private func isClose(_ a: CGRect, _ b: CGRect, within tolerance: CGFloat = 1e-9) -> Bool {
    abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance && abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
}

@Test func theBoundingBoxHoldsACurveAtItsExtremesNotItsControlPoints() {
    var quad = CanvasPath()
    quad.move(to: CGPoint(x: 0, y: 0))
    quad.addQuadCurve(to: CGPoint(x: 100, y: 0), control: CGPoint(x: 50, y: 80))
    // The curve peaks halfway to its control point.
    #expect(isClose(quad.boundingBox, CGRect(x: 0, y: 0, width: 100, height: 40)))
    var cubic = CanvasPath()
    cubic.move(to: CGPoint(x: 0, y: 0))
    cubic.addCurve(to: CGPoint(x: 90, y: 0), control1: CGPoint(x: 0, y: 60), control2: CGPoint(x: 90, y: -60))
    let box = cubic.boundingBox
    #expect(box.minX == 0 && box.maxX == 90)
    // y is 180 t (1 - t) (1 - 2t), which peaks at 10√3.
    #expect(abs(box.maxY - 10 * sqrt(3)) < 1e-9 && abs(box.minY + box.maxY) < 1e-9)
}

@Test func theBoundingBoxOfAShapeIsItsRectAndOfNothingIsNull() {
    let rect = CGRect(x: 2, y: 3, width: 40, height: 30)
    #expect(CanvasPath(rect: rect).boundingBox == rect)
    #expect(isClose(CanvasPath(ellipseIn: rect).boundingBox, rect))
    #expect(isClose(CanvasPath(roundedRect: rect, cornerRadius: 6).boundingBox, rect))
    #expect(CanvasPath().boundingBox.isNull)
}

@Test func anArcStartsWithALineAndRoundsTheCorner() {
    var path = CanvasPath()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addArc(tangent1End: CGPoint(x: 100, y: 0), tangent2End: CGPoint(x: 100, y: 60), radius: 10)
    #expect(isClose(path.boundingBox, CGRect(x: 0, y: 0, width: 100, height: 10)))
    // The corner is cut, so a thin stroke misses it but passes along both edges.
    #expect(path.strokeContains(CGPoint(x: 50, y: 0.5), width: 2, cap: .butt, join: .miter, miterLimit: 10))
    #expect(path.strokeContains(CGPoint(x: 99.5, y: 10), width: 2, cap: .butt, join: .miter, miterLimit: 10))
    #expect(!path.strokeContains(CGPoint(x: 99, y: 1), width: 2, cap: .butt, join: .miter, miterLimit: 10))
}

@Test func fillingUsesTheNonzeroWindingRule() {
    var path = CanvasPath()
    path.addRect(CGRect(x: 0, y: 0, width: 100, height: 100))
    // A square inside, drawn the other way round, cuts a hole.
    path.addLines(between: [CGPoint(x: 25, y: 25), CGPoint(x: 25, y: 75), CGPoint(x: 75, y: 75), CGPoint(x: 75, y: 25)])
    path.closeSubpath()
    #expect(path.contains(CGPoint(x: 10, y: 10)))
    #expect(!path.contains(CGPoint(x: 50, y: 50)))
    #expect(!path.contains(CGPoint(x: 150, y: 50)))
    // The same way round, it adds nothing.
    var twice = CanvasPath()
    twice.addRect(CGRect(x: 0, y: 0, width: 100, height: 100))
    twice.addRect(CGRect(x: 25, y: 25, width: 50, height: 50))
    #expect(twice.contains(CGPoint(x: 50, y: 50)))
    let ellipse = CanvasPath(ellipseIn: CGRect(x: 0, y: 0, width: 100, height: 50))
    #expect(ellipse.contains(CGPoint(x: 50, y: 25)))
    #expect(!ellipse.contains(CGPoint(x: 5, y: 5)))
}

@Test func anOpenPathFillsAsIfClosed() {
    var path = CanvasPath()
    path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)])
    #expect(path.contains(CGPoint(x: 90, y: 10)))
    #expect(!path.contains(CGPoint(x: 10, y: 90)))
}

@Test func capsShapeTheEndsOfAnOpenStroke() {
    var path = CanvasPath()
    path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
    let past = CGPoint(x: 103, y: 0), corner = CGPoint(x: 103, y: 4.5)
    #expect(path.strokeContains(CGPoint(x: 50, y: 4), width: 10, cap: .butt, join: .miter, miterLimit: 10))
    #expect(!path.strokeContains(CGPoint(x: 50, y: 6), width: 10, cap: .butt, join: .miter, miterLimit: 10))
    #expect(!path.strokeContains(past, width: 10, cap: .butt, join: .miter, miterLimit: 10))
    #expect(path.strokeContains(past, width: 10, cap: .round, join: .miter, miterLimit: 10))
    #expect(!path.strokeContains(corner, width: 10, cap: .round, join: .miter, miterLimit: 10))
    #expect(path.strokeContains(corner, width: 10, cap: .square, join: .miter, miterLimit: 10))
    #expect(!path.strokeContains(CGPoint(x: 106, y: 0), width: 10, cap: .square, join: .miter, miterLimit: 10))
}

@Test func aZeroLengthStrokeShowsOnlyWithARoundCap() {
    var dot = CanvasPath()
    dot.move(to: CGPoint(x: 10, y: 10))
    dot.addLine(to: CGPoint(x: 10, y: 10))
    #expect(dot.strokeContains(CGPoint(x: 13, y: 10), width: 8, cap: .round, join: .round, miterLimit: 10))
    #expect(!dot.strokeContains(CGPoint(x: 13, y: 10), width: 8, cap: .butt, join: .round, miterLimit: 10))
    var move = CanvasPath()
    move.move(to: CGPoint(x: 10, y: 10))
    #expect(!move.strokeContains(CGPoint(x: 10, y: 10), width: 8, cap: .round, join: .round, miterLimit: 10))
}

/// A tall, thin triangle, its apex at the origin. Its sides meet at about 15°, so a miter there reaches about 7.6 times
/// the line width.
private let spike: CanvasPath = {
    var path = CanvasPath()
    path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 12, y: 90), CGPoint(x: -12, y: 90)])
    path.closeSubpath()
    return path
}()

@Test func aMiterJoinReachesFarPastASharpCorner() {
    let tip = CGPoint(x: 0, y: -12)
    #expect(spike.strokeContains(tip, width: 4, cap: .butt, join: .miter, miterLimit: 10))
    #expect(!spike.strokeContains(CGPoint(x: 0, y: -16), width: 4, cap: .butt, join: .miter, miterLimit: 10))
    #expect(!spike.strokeContains(tip, width: 4, cap: .butt, join: .round, miterLimit: 10))
    #expect(!spike.strokeContains(tip, width: 4, cap: .butt, join: .bevel, miterLimit: 10))
    // Past the limit, the corner is cut off as a bevel.
    #expect(!spike.strokeContains(tip, width: 4, cap: .butt, join: .miter, miterLimit: 5))
    #expect(spike.strokeContains(CGPoint(x: 0, y: -1.9), width: 4, cap: .butt, join: .round, miterLimit: 10))
    #expect(!spike.strokeContains(CGPoint(x: 0, y: -1.9), width: 4, cap: .butt, join: .bevel, miterLimit: 10))
}

@Test func aMiterJoinFillsTheCornersOfARectangle() {
    let rect = CanvasPath(rect: CGRect(x: 0, y: 0, width: 50, height: 30))
    let corner = CGPoint(x: -4, y: -4)
    #expect(rect.strokeContains(corner, width: 10, cap: .butt, join: .miter, miterLimit: 10))
    #expect(!rect.strokeContains(corner, width: 10, cap: .butt, join: .round, miterLimit: 10))
    #expect(!rect.strokeContains(CGPoint(x: 25, y: 15), width: 10, cap: .butt, join: .miter, miterLimit: 10))
}

@Test func aStrokeBendsSmoothlyAlongACurveWhateverTheJoin() {
    var path = CanvasPath()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addQuadCurve(to: CGPoint(x: 100, y: 0), control: CGPoint(x: 50, y: 100))
    // The top of the curve is at y 50, so the stroke's outer edge passes 4 above it and nothing sticks out further.
    #expect(path.strokeContains(CGPoint(x: 50, y: 53.9), width: 8, cap: .butt, join: .miter, miterLimit: 10))
    #expect(!path.strokeContains(CGPoint(x: 50, y: 54.2), width: 8, cap: .butt, join: .miter, miterLimit: 10))
    #expect(path.strokeContains(CGPoint(x: 50, y: 46.1), width: 8, cap: .butt, join: .miter, miterLimit: 10))
    #expect(!path.strokeContains(CGPoint(x: 50, y: 45.8), width: 8, cap: .butt, join: .miter, miterLimit: 10))
}

@Test func theDistanceToASegmentIsToItsNearestPoint() {
    let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 10, y: 0)
    #expect(CanvasPath.distance(from: CGPoint(x: 5, y: 3), toSegment: a, b) == 3)
    #expect(CanvasPath.distance(from: CGPoint(x: 13, y: 4), toSegment: a, b) == 5)
    #expect(CanvasPath.distance(from: CGPoint(x: 3, y: 4), toSegment: a, a) == 5)
}

@Test func thePrimitivesBuildEachShapeFromItsCGPathStartPoint() {
    let rect = CGRect(x: 0, y: 0, width: 10, height: 6)
    #expect(CanvasPath(rect: rect).primitives == [
        .move(to: CGPoint(x: 0, y: 0)), .line(to: CGPoint(x: 10, y: 0)), .line(to: CGPoint(x: 10, y: 6)), .line(to: CGPoint(x: 0, y: 6)), .close,
    ])
    let ellipse = CanvasPath(ellipseIn: rect).primitives
    #expect(ellipse.first == .move(to: CGPoint(x: 10, y: 3)))
    #expect(ellipse.count == 6 && ellipse.last == .close)
    var open = CanvasPath()
    open.move(to: CGPoint(x: 1, y: 1))
    open.addQuadCurve(to: CGPoint(x: 7, y: 1), control: CGPoint(x: 4, y: 7))
    // A quadratic curve raised to a cubic, with no close.
    #expect(open.primitives == [.move(to: CGPoint(x: 1, y: 1)), .curve(to: CGPoint(x: 7, y: 1), control1: CGPoint(x: 3, y: 5), control2: CGPoint(x: 5, y: 5))])
}
