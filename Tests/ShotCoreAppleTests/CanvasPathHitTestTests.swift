import CoreGraphics
import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

// Checks that hit tests and bounds measured on CanvasPath agree with CGPath, which measured them before. Deleted when
// Annotation moves to ShotModel (#723).

private let red = RGBA.presets[0]

/// What `annotation` hit-tested as when CGPath measured it, set up once for every point.
private func cgPathHitTest(_ annotation: Annotation, tolerance: CGFloat) -> (CGPoint) -> Bool {
    let slop = tolerance + annotation.lineWidth / 2
    switch annotation.kind {
    case let .arrow(from, to), let .line(from, to):
        let path = CGMutablePath()
        path.move(to: from)
        if let curve = annotation.curve {
            path.addQuadCurve(to: curve.to, control: curve.control)
        } else {
            path.addLine(to: to)
        }
        let outline = path.copy(strokingWithWidth: slop * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return { outline.contains($0) }
    case let .shape(shape, rect):
        let path = shape.path(in: rect, cornerRadius: annotation.cornerRadius).cgPath
        let outline = path.copy(strokingWithWidth: slop * 2, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        return { outline.contains($0) || (annotation.fill != nil && path.contains($0)) }
    case .highlight, .pixelate, .blur, .spotlight, .text, .note, .image:
        let path = CGPath(rect: annotation.bounds.insetBy(dx: -tolerance, dy: -tolerance), transform: nil)
        return { path.contains($0) }
    case let .counter(_, center):
        let radius = annotation.counterRadius + tolerance
        let path = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), transform: nil)
        return { path.contains($0) }
    case let .freehand(points):
        let outline = Freehand.path(through: points).cgPath.copy(strokingWithWidth: slop * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return { outline.contains($0) }
    case let .marker(points):
        let outline = Freehand.path(through: points).cgPath.copy(strokingWithWidth: tolerance * 2 + annotation.markerWidth, lineCap: .butt, lineJoin: .round, miterLimit: 10)
        return { outline.contains($0) }
    }
}

/// The points `step` apart over `area` where `ours` and `expected` disagree, leaving out those within `margin` of the
/// edge of what `expected` holds. Each step doesn't divide the shapes' sizes, so the grid crosses their edges at every
/// offset.
private func disagreements(over area: CGRect, step: CGFloat, margin: CGFloat = 0.5, _ ours: (CGPoint) -> Bool, _ expected: (CGPoint) -> Bool) -> [CGPoint] {
    var found: [CGPoint] = []
    for y in stride(from: area.minY, through: area.maxY, by: step) {
        for x in stride(from: area.minX, through: area.maxX, by: step) {
            let point = CGPoint(x: x, y: y)
            let inside = expected(point)
            guard ours(point) != inside else {
                continue
            }
            let nearEdge = (0..<16).contains { index in
                let angle = CGFloat(index) / 16 * 2 * .pi
                return expected(CGPoint(x: x + cos(angle) * margin, y: y + sin(angle) * margin)) != inside
            }
            if !nearEdge {
                found.append(point)
            }
        }
    }
    return found
}

private func disagreements(_ annotation: Annotation, tolerance: CGFloat, step: CGFloat) -> [CGPoint] {
    disagreements(
        over: annotation.paintedBounds.insetBy(dx: -tolerance - 8, dy: -tolerance - 8),
        step: step,
        { annotation.hitTest($0, tolerance: tolerance) },
        cgPathHitTest(annotation, tolerance: tolerance)
    )
}

private let box = CGRect(x: 20, y: 30, width: 120, height: 70)
private let tall = CGRect(x: 10, y: 10, width: 24, height: 90)
/// A scribble whose last step doubles back, as a drag's end can jitter.
private let scribble = [
    CGPoint(x: 20, y: 40), CGPoint(x: 30, y: 52), CGPoint(x: 40, y: 60), CGPoint(x: 62, y: 38), CGPoint(x: 80, y: 20),
    CGPoint(x: 84, y: 22), CGPoint(x: 70, y: 70), CGPoint(x: 30, y: 75), CGPoint(x: 31, y: 74),
]
/// The scribble without the step back, which a marker's flat ends stroke differently; see
/// `aMarkerIsHitInTheGapCGPathLeavesWhereItDoublesBack`.
private let smoothScribble = Array(scribble.dropLast())

/// `shape` square, a little rounded and as round as it goes, in a wide and a tall rect, each with a thin unfilled
/// outline tested with no tolerance and a thick filled one tested with some.
private func shapes(_ shape: BoxShape) -> [(annotation: Annotation, tolerance: CGFloat)] {
    var result: [(Annotation, CGFloat)] = []
    for rect in [box, tall] {
        for radius in [nil, 6, 40] as [CGFloat?] {
            for (lineWidth, fill, tolerance) in [(CGFloat(2), nil, CGFloat(0)), (12, red, 4)] as [(CGFloat, RGBA?, CGFloat)] {
                var annotation = Annotation(kind: .shape(shape, rect: rect), color: red, fill: fill, lineWidth: lineWidth)
                annotation.cornerRadius = radius
                result.append((annotation, tolerance))
            }
        }
    }
    return result
}

private func strokes() -> [Annotation] {
    var bent = Annotation(kind: .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 140, y: 60)), color: red, lineWidth: 6)
    bent.bend = CGVector(dx: -20, dy: 35)
    var bentLine = Annotation(kind: .line(from: CGPoint(x: 10, y: 80), to: CGPoint(x: 90, y: 10)), color: red, lineWidth: 3)
    bentLine.bend = CGVector(dx: 30, dy: 30)
    return [
        Annotation(kind: .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 140, y: 60)), color: red, lineWidth: 4),
        Annotation(kind: .line(from: CGPoint(x: 50, y: 80), to: CGPoint(x: 52, y: 10)), color: red, lineWidth: 8),
        bent,
        bentLine,
        Annotation(kind: .freehand(scribble), color: red, lineWidth: 2),
        Annotation(kind: .freehand(scribble), color: red, lineWidth: 14),
        Annotation(kind: .freehand([CGPoint(x: 40, y: 40)]), color: red, lineWidth: 8),
        Annotation(kind: .freehand([CGPoint(x: 40, y: 40), CGPoint(x: 90, y: 40)]), color: red, lineWidth: 4),
        Annotation(kind: .marker(smoothScribble), color: red, lineWidth: 2),
        Annotation(kind: .marker(smoothScribble), color: red, lineWidth: 6),
        Annotation(kind: .marker([CGPoint(x: 40, y: 40)]), color: red, lineWidth: 4),
    ]
}

private func boxes() -> [Annotation] {
    [
        Annotation(kind: .highlight(box), color: red, lineWidth: 4),
        Annotation(kind: .pixelate(box), color: red, lineWidth: 4),
        Annotation(kind: .blur(box), color: red, lineWidth: 4),
        Annotation(kind: .spotlight(box, style: SpotlightStyle()), color: red, lineWidth: 4),
        Annotation(kind: .text("Hello", origin: CGPoint(x: 10, y: 10), fontSize: 20), color: red, lineWidth: 4),
        Annotation(kind: .note("A note", rect: box), color: red, lineWidth: 4),
        Annotation(kind: .counter(3, center: CGPoint(x: 50, y: 50)), color: red, lineWidth: 4),
        Annotation(kind: .image(AnnotationImage(solidImage(width: 60, height: 40)), rect: box), color: red, lineWidth: 0),
    ]
}

@Test(arguments: BoxShape.allCases)
func shapesHitTestAsCGPathDid(shape: BoxShape) {
    for (annotation, tolerance) in shapes(shape) {
        let found = disagreements(annotation, tolerance: tolerance, step: 1.07)
        #expect(found.isEmpty, "\(annotation.kind) radius \(String(describing: annotation.cornerRadius)) width \(annotation.lineWidth): \(found.prefix(5))")
    }
}

@Test(arguments: [0, 4] as [CGFloat])
func strokesHitTestAsCGPathDid(tolerance: CGFloat) {
    for annotation in strokes() {
        // Finer, as a stroke's ends and turns leave thin slivers.
        let found = disagreements(annotation, tolerance: tolerance, step: 0.73)
        #expect(found.isEmpty, "\(annotation.kind) width \(annotation.lineWidth): \(found.prefix(5))")
    }
}

@Test func boxesHitTestAsCGPathDid() {
    for annotation in boxes() {
        let found = disagreements(annotation, tolerance: 2, step: 1.07)
        #expect(found.isEmpty, "\(annotation.kind): \(found.prefix(5))")
    }
}

// Where a marker's stroke doubles back within a curve, CGPath's outline overlaps itself the wrong way round and leaves
// a gap up to about 3 pt across, which it also paints. The hit test selects there, as every point in the gap is within
// half the marker's width of its curve.
@Test func aMarkerIsHitInTheGapCGPathLeavesWhereItDoublesBack() {
    let marker = Annotation(kind: .marker(scribble), color: red, lineWidth: 2)
    let point = CGPoint(x: 30.13, y: 72.24)
    #expect(!cgPathHitTest(marker, tolerance: 0)(point))
    #expect(marker.hitTest(point, tolerance: 0))
}

@Test func curveAndFreehandBoundsMatchCGPath() {
    for annotation in strokes() {
        switch annotation.kind {
        case let .arrow(from, _), let .line(from, _):
            guard let curve = annotation.curve else {
                continue
            }
            let path = CGMutablePath()
            path.move(to: from)
            path.addQuadCurve(to: curve.to, control: curve.control)
            let expected = path.boundingBoxOfPath, bounds = annotation.bounds
            #expect(abs(bounds.minX - expected.minX) < 1e-6 && abs(bounds.minY - expected.minY) < 1e-6, "\(bounds) \(expected)")
            #expect(abs(bounds.maxX - expected.maxX) < 1e-6 && abs(bounds.maxY - expected.maxY) < 1e-6, "\(bounds) \(expected)")
        case let .freehand(points), let .marker(points):
            let expected = Freehand.path(through: points).cgPath.boundingBoxOfPath, bounds = Freehand.path(through: points).boundingBox
            #expect(abs(bounds.minX - expected.minX) < 1e-6 && abs(bounds.minY - expected.minY) < 1e-6, "\(bounds) \(expected)")
            #expect(abs(bounds.maxX - expected.maxX) < 1e-6 && abs(bounds.maxY - expected.maxY) < 1e-6, "\(bounds) \(expected)")
        default:
            continue
        }
    }
}

@Test(arguments: [CanvasLineJoin.miter, .round, .bevel])
func everyCanvasPathElementBoundsFillsAndStrokesAsCGPathDoes(join: CanvasLineJoin) {
    var path = CanvasPath()
    path.move(to: CGPoint(x: 5, y: 90))
    path.addLine(to: CGPoint(x: 40, y: 95))
    path.addArc(tangent1End: CGPoint(x: 70, y: 60), tangent2End: CGPoint(x: 20, y: 40), radius: 12)
    path.addQuadCurve(to: CGPoint(x: 10, y: 10), control: CGPoint(x: -20, y: 30))
    path.addCurve(to: CGPoint(x: 60, y: 5), control1: CGPoint(x: 30, y: -10), control2: CGPoint(x: 50, y: 30))
    path.closeSubpath()
    path.addRect(CGRect(x: 80, y: 10, width: 30, height: 20))
    let paths = [
        path,
        CanvasPath(ellipseIn: CGRect(x: 10, y: 20, width: 90, height: 40)),
        CanvasPath(roundedRect: CGRect(x: 10, y: 20, width: 90, height: 40), cornerRadius: 15),
    ]
    for path in paths {
        let cgPath = path.cgPath
        let expected = cgPath.boundingBoxOfPath, bounds = path.boundingBox
        #expect(abs(bounds.minX - expected.minX) < 0.01 && abs(bounds.minY - expected.minY) < 0.01, "\(bounds) \(expected)")
        #expect(abs(bounds.maxX - expected.maxX) < 0.01 && abs(bounds.maxY - expected.maxY) < 0.01, "\(bounds) \(expected)")
        let area = bounds.insetBy(dx: -10, dy: -10)
        let fills = disagreements(over: area, step: 1.07, path.contains) { cgPath.contains($0) }
        #expect(fills.isEmpty, "\(path.elements.first!) fill: \(fills.prefix(5))")
        for cap in [CanvasLineCap.butt, .round, .square] {
            let outline = cgPath.copy(strokingWithWidth: 10, lineCap: cgCap(cap), lineJoin: cgJoin(join), miterLimit: 10)
            let strokes = disagreements(over: area, step: 1.07, { path.strokeContains($0, width: 10, cap: cap, join: join, miterLimit: 10) }) { outline.contains($0) }
            #expect(strokes.isEmpty, "\(path.elements.first!) \(cap) \(join): \(strokes.prefix(5))")
        }
    }
}

private func cgCap(_ cap: CanvasLineCap) -> CGLineCap {
    switch cap {
    case .butt: .butt
    case .round: .round
    case .square: .square
    }
}

private func cgJoin(_ join: CanvasLineJoin) -> CGLineJoin {
    switch join {
    case .miter: .miter
    case .round: .round
    case .bevel: .bevel
    }
}
