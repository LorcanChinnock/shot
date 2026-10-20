import CoreGraphics
import Testing
@testable import ShotCore
import ShotCoreApple

@Test func aCGPathBecomesACanvasPathWithTheSameSteps() {
    let curved = Freehand.path(through: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 0)]).cgPath
    #expect(CanvasPath(curved).cgPath == curved)
    let mutable = CGMutablePath()
    mutable.move(to: CGPoint(x: 1, y: 1))
    mutable.addQuadCurve(to: CGPoint(x: 9, y: 1), control: CGPoint(x: 5, y: 8))
    mutable.closeSubpath()
    #expect(CanvasPath(mutable).elements == [.move(to: CGPoint(x: 1, y: 1)), .quadCurve(to: CGPoint(x: 9, y: 1), control: CGPoint(x: 5, y: 8)), .close])
}

@Test func aWholeShapeIsTheCGPathCoreGraphicsMakesForIt() {
    let rect = CGRect(x: 5, y: 5, width: 50, height: 30)
    #expect(CanvasPath(rect: rect).cgPath == CGPath(rect: rect, transform: nil))
    #expect(CanvasPath(ellipseIn: rect).cgPath == CGPath(ellipseIn: rect, transform: nil))
    #expect(CanvasPath(roundedRect: rect, cornerRadius: 8).cgPath == CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
    var two = CanvasPath(rect: rect)
    two.addRect(rect.offsetBy(dx: 60, dy: 0))
    #expect(two.cgPath.boundingBoxOfPath == CGRect(x: 5, y: 5, width: 110, height: 30))
}

@Test func aNewCGCanvasHasTheFormatItWasMadeIn() throws {
    let grey = try #require(CGCanvas(width: 3, height: 2, format: .grey))
    #expect(grey.context.colorSpace?.model == .monochrome)
    #expect(grey.context.alphaInfo == .none)
    let sRGB = try #require(CGCanvas(width: 3, height: 2, format: .sRGB))
    #expect(sRGB.context.colorSpace?.name == CGColorSpace.sRGB)
    #expect(sRGB.context.alphaInfo == .premultipliedLast)
    let p3 = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
    let matching = try #require(CGCanvas(width: 3, height: 2, format: .matching(p3)))
    #expect(matching.context.colorSpace?.name == CGColorSpace.displayP3)
    #expect(matching.makeImage()?.width == 3)
    #expect(CGCanvas(width: 0, height: 2, format: .sRGB) == nil)
}

@Test func aCGCanvasReportsItsScaleAndClipInItsOwnCoordinates() throws {
    let canvas = try #require(CGCanvas(width: 20, height: 20, format: .sRGB))
    #expect(canvas.pixelScale == 1)
    canvas.scaleBy(x: 2, y: -2)
    #expect(canvas.pixelScale == 2)
    #expect(canvas.clipBounds == CGRect(x: 0, y: -10, width: 10, height: 10))
    canvas.clip(to: CGRect(x: 1, y: -9, width: 4, height: 4))
    #expect(canvas.clipBounds == CGRect(x: 1, y: -9, width: 4, height: 4))
}

@Test func aPathsPrimitivesAreTheElementsCoreGraphicsBuildsForIt() {
    func elements(_ path: CGPath) -> [CanvasPath.Primitive] {
        var result: [CanvasPath.Primitive] = []
        path.applyWithBlock { pointer in
            let points = pointer.pointee.points
            switch pointer.pointee.type {
            case .moveToPoint: result.append(.move(to: points[0]))
            case .addLineToPoint: result.append(.line(to: points[0]))
            case .addCurveToPoint: result.append(.curve(to: points[2], control1: points[0], control2: points[1]))
            case .closeSubpath: result.append(.close)
            default: Issue.record("an element CanvasPath doesn't make")
            }
        }
        return result
    }
    func isClose(_ a: [CanvasPath.Primitive], _ b: [CanvasPath.Primitive]) -> Bool {
        func points(_ primitive: CanvasPath.Primitive) -> [CGPoint] {
            switch primitive {
            case let .move(to), let .line(to): [to]
            case let .curve(to, c1, c2): [to, c1, c2]
            case .close: []
            }
        }
        return a.count == b.count && zip(a, b).allSatisfy { x, y in
            let (p, q) = (points(x), points(y))
            return p.count == q.count && zip(p, q).allSatisfy { abs($0.x - $1.x) < 1e-6 && abs($0.y - $1.y) < 1e-6 }
        }
    }
    let rect = CGRect(x: 5, y: 7, width: 50, height: 30)
    var arc = CanvasPath()
    arc.move(to: CGPoint(x: 0, y: 0))
    arc.addArc(tangent1End: CGPoint(x: 100, y: 0), tangent2End: CGPoint(x: 100, y: 60), radius: 10)
    arc.addLine(to: CGPoint(x: 100, y: 60))
    var rects = CanvasPath(rect: rect)
    rects.addRect(rect.offsetBy(dx: 60, dy: 0))
    for path in [CanvasPath(rect: rect), CanvasPath(ellipseIn: rect), CanvasPath(roundedRect: rect, cornerRadius: 8), arc, rects] {
        let built = path.cgPath
        let made = CGMutablePath()
        made.addPath(built)
        #expect(isClose(path.primitives, elements(made)))
    }
}
