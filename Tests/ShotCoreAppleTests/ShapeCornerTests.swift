import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let frame = CGRect(x: 0, y: 0, width: 200, height: 160)
private let red = RGBA.presets[0]

/// Whether `point` lies on the outline of `path`, within half a point.
private func isOnOutline(_ point: CGPoint, of path: CGPath) -> Bool {
    path.copy(strokingWithWidth: 1, lineCap: .butt, lineJoin: .miter, miterLimit: 10).contains(point)
}

@Test func noRadiusKeepsEveryShapeSquare() {
    for shape in BoxShape.allCases where shape.hasCorners {
        let path = shape.path(in: frame).cgPath
        for corner in shape.vertices(in: frame).points {
            #expect(isOnOutline(corner, of: path), "\(shape)")
        }
        #expect(path.boundingBoxOfPath.integral == frame || shape == .star)
    }
    #expect(BoxShape.rectangle.path(in: frame, cornerRadius: nil).cgPath == CGPath(rect: frame, transform: nil))
}

@Test func aRectangleWithARadiusIsTheRoundedRectangleItAlwaysWas() {
    #expect(BoxShape.rectangle.path(in: frame, cornerRadius: 20).cgPath == CGPath(roundedRect: frame, cornerWidth: 20, cornerHeight: 20, transform: nil))
    #expect(BoxShape.rectangle.maxRadius(in: frame) == 80)
    #expect(BoxShape.rectangle.path(in: frame, cornerRadius: 500).cgPath == CGPath(roundedRect: frame, cornerWidth: 80, cornerHeight: 80, transform: nil))
}

@Test func roundingATriangleOrDiamondCutsEveryVertexAndStaysInsideTheBox() {
    for shape in [BoxShape.triangle, .diamond] {
        let path = shape.path(in: frame, cornerRadius: 12).cgPath
        for corner in shape.vertices(in: frame).points {
            #expect(!isOnOutline(corner, of: path), "\(shape) kept a sharp corner")
        }
        #expect(frame.insetBy(dx: -0.001, dy: -0.001).contains(path.boundingBoxOfPath), "\(shape)")
        // The arc is tangent to the edges, so the outline is still closed and reaches the middle of its sides.
        #expect(path.contains(CGPoint(x: frame.midX, y: frame.midY)))
    }
}

@Test func theRadiusIsCappedSoNeighbouringArcsNeverOverlap() {
    // A thin triangle has a sharp apex, which an arc eats a long way along its edges.
    let thin = CGRect(x: 0, y: 0, width: 20, height: 200)
    let wide = CGRect(x: 0, y: 0, width: 200, height: 200)
    let thinCap = BoxShape.triangle.maxRadius(in: thin)
    #expect(thinCap > 0 && thinCap < BoxShape.triangle.maxRadius(in: wide))
    #expect(BoxShape.triangle.clampedRadius(1000, in: thin) == thinCap)
    #expect(BoxShape.triangle.clampedRadius(-5, in: thin) == 0 && BoxShape.triangle.clampedRadius(nil, in: thin) == 0)
    // At the cap the arcs at the base meet the arc at the apex without crossing it: the outline stays inside the box.
    let path = BoxShape.triangle.path(in: thin, cornerRadius: 1000).cgPath
    #expect(thin.insetBy(dx: -0.001, dy: -0.001).contains(path.boundingBoxOfPath))
    #expect(path.boundingBoxOfPath == BoxShape.triangle.path(in: thin, cornerRadius: thinCap).cgPath.boundingBoxOfPath)
}

@Test func theCapOnATriangleIsWhereTwoArcsMeetOnAnEdge() {
    // For a square diamond, each edge holds two arcs of 90 degrees, which take r each: they meet when r is half the edge.
    let square = CGRect(x: 0, y: 0, width: 100, height: 100)
    let edge = (50.0 * 50.0 + 50.0 * 50.0).squareRoot()
    #expect(abs(BoxShape.diamond.maxRadius(in: square) - edge / 2) < 0.001)
}

@Test func aStarRoundsItsPointsAndKeepsTheCornersBetweenThemSharp() {
    let (points, rounded) = BoxShape.star.vertices(in: frame)
    #expect(points.count == 10 && rounded == [0, 2, 4, 6, 8])
    let radius = BoxShape.star.maxRadius(in: frame)
    #expect(radius > 0)
    let path = BoxShape.star.path(in: frame, cornerRadius: radius).cgPath
    for (index, corner) in points.enumerated() {
        #expect(isOnOutline(corner, of: path) == !rounded.contains(index), "corner \(index)")
    }
    // A rounded point no longer reaches its box edge.
    #expect(path.boundingBoxOfPath.minY > frame.minY)
    #expect(BoxShape.star.path(in: frame).cgPath.boundingBoxOfPath.minY == frame.minY)
}

@Test func theStarsCapIsSetByItsPointsNotItsInnerCorners() {
    let cap = BoxShape.star.maxRadius(in: frame)
    // Past the cap the path doesn't change, so the points' arcs never run past the inner corners.
    #expect(BoxShape.star.path(in: frame, cornerRadius: cap * 5).cgPath == BoxShape.star.path(in: frame, cornerRadius: cap).cgPath)
    let thin = CGRect(x: 0, y: 0, width: 30, height: 200)
    #expect(BoxShape.star.maxRadius(in: thin) < cap)
}

@Test func anEllipseHasNoCornersToRound() {
    #expect(!BoxShape.ellipse.hasCorners)
    #expect(BoxShape.ellipse.maxRadius(in: frame) == 0)
    #expect(BoxShape.ellipse.path(in: frame, cornerRadius: 30).cgPath == CGPath(ellipseIn: frame, transform: nil))
}

@Test func roundedPolygonsRenderAndHitTestWithTheirRadius() {
    var triangle = Annotation(kind: .shape(.triangle, rect: frame), color: red, lineWidth: 4)
    let apex = CGPoint(x: frame.midX, y: frame.minY)
    // A little way in from the tip, where a sharp triangle still has a stroke and a rounded one doesn't.
    #expect(triangle.hitTest(CGPoint(x: apex.x, y: apex.y - 3), tolerance: 1))
    triangle.cornerRadius = 30
    #expect(!triangle.hitTest(CGPoint(x: apex.x, y: apex.y - 3), tolerance: 1))
}

// MARK: Copying and pasting a radius

private func scene(_ shapes: [Annotation]) -> EditorDocument {
    EditorDocument(base: solidImage(width: 400, height: 300), annotations: shapes)
}

@Test func aStylePastedBetweenShapesCarriesTheRadius() throws {
    var source = Annotation(kind: .shape(.triangle, rect: frame), color: red, lineWidth: 4)
    source.cornerRadius = 16
    let star = Annotation(kind: .shape(.star, rect: frame), color: red, lineWidth: 4)
    let ellipse = Annotation(kind: .shape(.ellipse, rect: frame), color: red, lineWidth: 4)
    let arrow = Annotation(kind: .arrow(from: .zero, to: CGPoint(x: 50, y: 50)), color: red, lineWidth: 4)
    var doc = scene([source, star, ellipse, arrow])
    let copied = try #require(doc.copyStyle(of: .annotation(source.id), scale: 2))
    #expect(copied.cornerRadius == 8 && copied.isFromShape)
    doc.pasteStyle(copied, to: [star, ellipse, arrow].map { .annotation($0.id) }, scale: 2, margin: 0)
    #expect(doc.annotations[1].cornerRadius == 16)
    // An ellipse has no corners, an arrow isn't a shape, and neither takes a radius.
    #expect(doc.annotations[2].cornerRadius == nil)
    #expect(doc.annotations[3].cornerRadius == nil)
}

@Test func aShapesRadiusAndAScreenshotsAreNotSwapped() throws {
    var shape = Annotation(kind: .shape(.rectangle, rect: frame), color: red, lineWidth: 4)
    shape.cornerRadius = 16
    var doc = scene([shape])
    let fromShape = try #require(doc.copyStyle(of: .annotation(shape.id), scale: 1))
    doc.pasteStyle(fromShape, to: [.capture], scale: 1, margin: 0)
    #expect(doc.captureCornerRadius == 0)
    doc.setCornerRadius(30, of: .capture)
    let fromCapture = try #require(doc.copyStyle(of: .capture, scale: 1))
    doc.pasteStyle(fromCapture, to: [.annotation(shape.id)], scale: 1, margin: 0)
    #expect(doc.annotations[0].cornerRadius == 16)
}

@Test func aSavedStyleFromBeforeShapesCouldBeRoundedStillDecodes() throws {
    let copied = CopiedStyle(style: ObjectStyle(), cornerRadius: 4, source: .image)
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(copied)) as? [String: Any])
    object["fromShape"] = nil
    let decoded = try JSONDecoder().decode(CopiedStyle.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded == copied && !decoded.isFromShape)
}

// MARK: Agent marks

@Test func aRoundedMarkIsARectangleWithTheDefaultRadius() throws {
    let mark = CaptureMark(id: "a", type: "rounded", rect: [10, 10, 80, 40])
    let annotation = try #require(Annotation(mark: mark))
    #expect(annotation.kind == .shape(.rectangle, rect: CGRect(x: 10, y: 10, width: 80, height: 40)))
    #expect(annotation.cornerRadius == Annotation.defaultCornerRadius)
    let reported = CaptureMark(annotation, origin: .zero, scale: 1)
    #expect(reported.type == "rectangle" && reported.cornerRadius == Double(Annotation.defaultCornerRadius))
    let sized = try #require(Annotation(mark: CaptureMark(id: "b", type: "rounded", rect: [10, 10, 80, 40], cornerRadius: 5)))
    #expect(sized.cornerRadius == 5)
    #expect(try #require(Annotation(mark: CaptureMark(id: "c", type: "rectangle", rect: [10, 10, 80, 40]))).cornerRadius == nil)
}

@Test func theMarkTypesStillAcceptRounded() {
    #expect(CaptureMark.types.contains("rounded") && CaptureMark.types.contains("rectangle"))
}
