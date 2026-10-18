#if canImport(CoreGraphics)
import CoreGraphics

// Hit tests, bounds and the spotlights' boolean operations still use CGPath, and a CoreGraphics canvas draws one.

extension CanvasPath {
    /// `path`'s elements, its curves kept as they are.
    public init(_ path: CGPath) {
        self.init()
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint: move(to: points[0])
            case .addLineToPoint: addLine(to: points[0])
            case .addQuadCurveToPoint: addQuadCurve(to: points[1], control: points[0])
            case .addCurveToPoint: addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closeSubpath: closeSubpath()
            @unknown default: break
            }
        }
    }

    public var cgPath: CGPath {
        // Kept as CoreGraphics makes each shape alone, which a test compares paths against.
        if elements.count == 1 {
            switch elements[0] {
            case let .rect(rect): return CGPath(rect: rect, transform: nil)
            case let .ellipse(rect): return CGPath(ellipseIn: rect, transform: nil)
            case let .roundedRect(rect, width, height): return CGPath(roundedRect: rect, cornerWidth: width, cornerHeight: height, transform: nil)
            default: break
            }
        }
        let path = CGMutablePath()
        for element in elements {
            switch element {
            case let .move(point): path.move(to: point)
            case let .line(point): path.addLine(to: point)
            case let .quadCurve(point, control): path.addQuadCurve(to: point, control: control)
            case let .curve(point, control1, control2): path.addCurve(to: point, control1: control1, control2: control2)
            case let .arc(tangent1End, tangent2End, radius): path.addArc(tangent1End: tangent1End, tangent2End: tangent2End, radius: radius)
            case let .rect(rect): path.addRect(rect)
            case let .ellipse(rect): path.addEllipse(in: rect)
            case let .roundedRect(rect, width, height): path.addRoundedRect(in: rect, cornerWidth: width, cornerHeight: height)
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}
#endif
