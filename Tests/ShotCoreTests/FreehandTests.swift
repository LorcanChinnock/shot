import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let blue = RGBA(0, 0, 1)

private func pen(_ points: [CGPoint], lineWidth: CGFloat = 4) -> Annotation {
    Annotation(kind: .freehand(points), color: blue, lineWidth: lineWidth)
}

/// A tick: down and right, then a longer stroke up and right.
private let tick = [CGPoint(x: 20, y: 40), CGPoint(x: 30, y: 50), CGPoint(x: 40, y: 60), CGPoint(x: 60, y: 40), CGPoint(x: 80, y: 20)]

/// A closed loop of `count` points around `center`, like a quick circle round something.
private func loop(center: CGPoint, radius: CGFloat, count: Int = 24) -> [CGPoint] {
    (0...count).map { i in
        let angle = CGFloat(i) / CGFloat(count) * 2 * .pi
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}

/// Renders as the editor does: into a context zoomed by `scale`.
private func render(_ doc: EditorDocument, scale: CGFloat) throws -> CGImage {
    let size = doc.exportSize
    let ctx = try #require(CGContext(
        data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: scale, y: scale)
    AnnotationRenderer.render(doc, into: ctx)
    return try #require(ctx.makeImage())
}

/// The pixel at canvas point (`x`, `y`), top-left origin, as 0...1 premultiplied components.
private func pixel(_ image: CGImage, _ x: CGFloat, _ y: CGFloat, scale: CGFloat = 1) throws -> [CGFloat] {
    let data = try #require(image.dataProvider?.data as Data?)
    let offset = Int(y * scale) * image.bytesPerRow + Int(x * scale) * 4
    return data[offset..<offset + 4].map { CGFloat($0) / 255 }
}

private func isInk(_ p: [CGFloat]) -> Bool { p[2] > 0.9 && p[0] < 0.1 }
private func isBase(_ p: [CGFloat]) -> Bool { p[0] > 0.9 && p[2] < 0.1 }

// MARK: Smoothing

@Test func theSmoothedPathIsACurveThroughEveryPoint() {
    var ends: [CGPoint] = []
    var curves = 0, lines = 0
    Freehand.path(through: tick).applyWithBlock { element in
        switch element.pointee.type {
        case .moveToPoint:
            ends.append(element.pointee.points[0])
        case .addCurveToPoint:
            curves += 1
            ends.append(element.pointee.points[2])
        case .addLineToPoint:
            lines += 1
        default:
            break
        }
    }
    #expect(curves == tick.count - 1)
    #expect(lines == 0)
    #expect(ends == tick)
}

@Test func aSmoothedCornerHasNoKink() {
    // At each inner point the curve leaves in the direction it arrived, which a polyline wouldn't.
    var controls: [(CGPoint, CGPoint)] = []
    Freehand.path(through: tick).applyWithBlock { element in
        if element.pointee.type == .addCurveToPoint {
            controls.append((element.pointee.points[0], element.pointee.points[1]))
        }
    }
    for i in 1..<tick.count - 1 {
        let inward = controls[i - 1].1, outward = controls[i].0, p = tick[i]
        let cross = (p.x - inward.x) * (outward.y - p.y) - (p.y - inward.y) * (outward.x - p.x)
        #expect(abs(cross) < 1e-9, "at \(p)")
    }
}

@Test func aSinglePointIsADot() {
    let path = Freehand.path(through: [CGPoint(x: 10, y: 10)])
    #expect(!path.isEmpty)
    #expect(pen([CGPoint(x: 10, y: 10)]).hitTest(CGPoint(x: 11, y: 10), tolerance: 0))
    #expect(Freehand.path(through: []).isEmpty)
}

@Test func pointsTooCloseToTheLastAreDropped() {
    var points: [CGPoint] = []
    points = Freehand.adding(CGPoint(x: 0, y: 0), to: points, minDistance: 2)
    points = Freehand.adding(CGPoint(x: 1, y: 1), to: points, minDistance: 2)
    points = Freehand.adding(CGPoint(x: 2, y: 0), to: points, minDistance: 2)
    points = Freehand.adding(CGPoint(x: 2, y: 1), to: points, minDistance: 2)
    #expect(points == [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0)])
}

// MARK: Bounds

@Test func boundsHoldEveryPoint() {
    let a = pen(tick)
    #expect(a.bounds == CGRect(x: 20, y: 20, width: 60, height: 40))
}

@Test func paintedBoundsHoldTheStrokeAndTheCurve() {
    let a = pen(tick, lineWidth: 8)
    #expect(a.paintedBounds.contains(a.bounds.insetBy(dx: -4, dy: -4)))
    #expect(a.paintedBounds.contains(Freehand.path(through: tick).boundingBoxOfPath.insetBy(dx: -4, dy: -4)))
}

// MARK: Hit-testing

@Test func hitTestFollowsTheStroke() {
    let a = pen(tick)
    // On the points, and between them.
    #expect(a.hitTest(CGPoint(x: 40, y: 60), tolerance: 0))
    #expect(a.hitTest(CGPoint(x: 70, y: 30), tolerance: 0))
    #expect(a.hitTest(CGPoint(x: 25, y: 46), tolerance: 1))
    // Inside the bounds but off the stroke.
    #expect(!a.hitTest(CGPoint(x: 40, y: 30), tolerance: 2))
    #expect(!a.hitTest(CGPoint(x: 75, y: 55), tolerance: 2))
    // The tolerance and the line width both widen it.
    #expect(!a.hitTest(CGPoint(x: 70, y: 38), tolerance: 0))
    #expect(a.hitTest(CGPoint(x: 70, y: 38), tolerance: 6))
    #expect(pen(tick, lineWidth: 16).hitTest(CGPoint(x: 70, y: 38), tolerance: 0))
}

@Test func theInsideOfACircleIsNotTheCircle() {
    // Clicking inside a circled area selects what's under it, not the circle.
    let a = pen(loop(center: CGPoint(x: 100, y: 100), radius: 50))
    #expect(a.hitTest(CGPoint(x: 150, y: 100), tolerance: 0))
    #expect(a.hitTest(CGPoint(x: 100, y: 52), tolerance: 2))
    #expect(!a.hitTest(CGPoint(x: 100, y: 100), tolerance: 6))
    let doc = [Annotation(kind: .rect(CGRect(x: 90, y: 90, width: 20, height: 20)), color: blue, lineWidth: 4), a]
    #expect(doc.topmostIndex(at: CGPoint(x: 90, y: 100), tolerance: 2) == 0)
    #expect(doc.topmostIndex(at: CGPoint(x: 150, y: 100), tolerance: 2) == 1)
}

// MARK: Moving

@Test func offsetMovesEveryPoint() {
    var a = pen(tick)
    a.offset(by: CGVector(dx: 5, dy: -10))
    #expect(a.kind == .freehand(tick.map { CGPoint(x: $0.x + 5, y: $0.y - 10) }))
    #expect(a.bounds == CGRect(x: 25, y: 10, width: 60, height: 40))
}

@Test func nudgingAndPastingMoveTheStroke() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [pen(tick)])
    let id = doc.annotations[0].id
    doc.move(id, by: NudgeDirection.right.offset(large: true), margin: 16)
    #expect(doc.annotations[0].bounds.origin == CGPoint(x: 30, y: 20))
    let pasted = doc.paste(doc.annotations[0], step: 10, margin: 16)
    let copy = doc.annotations.first { $0.id == pasted }
    #expect(copy?.bounds.origin == CGPoint(x: 40, y: 30))
}

// MARK: Resizing

@Test func aStrokeHasBoxHandlesOnItsBounds() {
    let a = pen(tick)
    let points = Dictionary(uniqueKeysWithValues: a.handles.map { ($0.handle, $0.point) })
    #expect(points.count == 8)
    #expect(points[.topLeft] == CGPoint(x: 20, y: 20))
    #expect(points[.bottomRight] == CGPoint(x: 80, y: 60))
    #expect(points[.right] == CGPoint(x: 80, y: 40))
}

@Test func resizingScalesThePointsWithinTheBounds() {
    var a = pen(tick)
    a.resize(.bottomRight, to: CGPoint(x: 140, y: 100))
    // The top-left stays put and every point keeps its place within the box, which doubles.
    #expect(a.kind == .freehand(tick.map { CGPoint(x: 20 + ($0.x - 20) * 2, y: 20 + ($0.y - 20) * 2) }))
    #expect(a.bounds == CGRect(x: 20, y: 20, width: 120, height: 80))

    var b = pen(tick)
    b.resize(.top, to: CGPoint(x: 999, y: 40))
    #expect(b.bounds == CGRect(x: 20, y: 40, width: 60, height: 20))
    #expect(b.kind == .freehand(tick.map { CGPoint(x: $0.x, y: 40 + ($0.y - 20) / 2) }))
}

@Test func draggingPastTheOppositeSideMirrorsTheStroke() {
    var a = pen(tick)
    a.resize(.right, to: CGPoint(x: 0, y: 0))
    #expect(a.bounds == CGRect(x: 0, y: 20, width: 20, height: 40))
    // The tick's long arm now points left.
    #expect(a.kind == .freehand(tick.map { CGPoint(x: 20 - ($0.x - 20) / 3, y: $0.y) }))
}

@Test func aStraightStrokeKeepsItsFlatSide() {
    let flat = [CGPoint(x: 10, y: 50), CGPoint(x: 60, y: 50), CGPoint(x: 110, y: 50)]
    var a = pen(flat)
    a.resize(.bottomRight, to: CGPoint(x: 210, y: 90))
    #expect(a.kind == .freehand([CGPoint(x: 10, y: 50), CGPoint(x: 110, y: 50), CGPoint(x: 210, y: 50)]))
}

@Test func aResizedStrokeGrowsTheCanvasAndUndoes() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [pen(tick)])
    var stack = UndoStack<EditorSnapshot>()
    let placed = doc.snapshot
    stack.record(doc.snapshot)
    doc.annotations[0].resize(.bottomRight, to: CGPoint(x: 260, y: 140))
    doc.grow(toFit: doc.annotations[0], margin: 10)
    #expect(doc.canvasRect.contains(doc.annotations[0].paintedBounds.insetBy(dx: -10, dy: -10)))
    doc.restore(stack.undo(from: doc.snapshot)!)
    #expect(doc.snapshot == placed)
}

// MARK: Restyling

@Test func restylingKeepsThePoints() {
    var a = pen(tick)
    a.setLineWidth(16)
    a.color = RGBA.presets[1]
    #expect(a.kind == .freehand(tick))
    #expect(a.lineWidth == 16)
}

// MARK: Canvas

@Test func aStrokePastTheEdgeGrowsTheCanvas() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    let past = pen([CGPoint(x: 150, y: 50), CGPoint(x: 220, y: 70), CGPoint(x: 260, y: 120)], lineWidth: 8)
    doc.annotations.append(past)
    doc.grow(toFit: past, margin: 10)
    #expect(doc.canvasRect.minX == 0 && doc.canvasRect.minY == 0)
    #expect(doc.canvasRect.contains(past.paintedBounds.insetBy(dx: -10, dy: -10)))
}

@Test func undoingAStrokeRemovesItInOneStep() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    var stack = UndoStack<EditorSnapshot>()
    let empty = doc.snapshot
    stack.record(doc.snapshot)
    doc.annotations.append(pen(tick + [CGPoint(x: 250, y: 20)]))
    doc.grow(toFit: doc.annotations[0], margin: 10)
    doc.restore(stack.undo(from: doc.snapshot)!)
    #expect(doc.snapshot == empty)
}

// MARK: Rendering

@Test func theExportDrawsASmoothRoundCappedStroke() throws {
    let doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [pen(tick, lineWidth: 6)])
    let image = try #require(AnnotationRenderer.flatten(doc))
    #expect(isInk(try pixel(image, 40, 60)))
    #expect(isInk(try pixel(image, 70, 30)))
    #expect(isBase(try pixel(image, 40, 30)))
    // Round caps reach back past the first point; a butt cap wouldn't.
    #expect(isInk(try pixel(image, 18, 38)))
}

@Test(arguments: [1.0, 2.0])
func aStrokeRendersTheSameInTheEditorAndTheExport(scale: CGFloat) throws {
    let doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [
        pen(tick, lineWidth: 6),
        pen(loop(center: CGPoint(x: 140, y: 50), radius: 30), lineWidth: 4),
    ])
    let flat = try #require(AnnotationRenderer.flatten(doc))
    let editor = try render(doc, scale: scale)
    for x in stride(from: 3.0, to: 200, by: 7) {
        for y in stride(from: 3.0, to: 100, by: 7) {
            let exported = try pixel(flat, x, y), shown = try pixel(editor, x, y, scale: scale)
            // Antialiased edges differ between zooms, so a pixel clearly one colour mustn't be clearly the other.
            #expect(!(isInk(exported) && isBase(shown)) && !(isBase(exported) && isInk(shown)), "at \(x), \(y)")
        }
    }
}
