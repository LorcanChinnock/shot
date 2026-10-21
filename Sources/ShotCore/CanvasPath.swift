import Foundation

/// An outline to fill, stroke or clip to on a canvas, kept as the steps that draw it so any drawing library can replay
/// them. Rects, ellipses and rounded rects stay whole, so each library draws them its own exact way.
public struct CanvasPath: Equatable, Sendable {
    public enum Element: Equatable, Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        /// An arc of `radius` tangent to the line from the current point to `tangent1End` and to the line from there to
        /// `tangent2End`, joined to the current point by a straight line.
        case arc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat)
        case rect(CGRect)
        case ellipse(in: CGRect)
        case roundedRect(CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat)
        case close
    }

    public private(set) var elements: [Element] = []

    public init() {}

    public init(rect: CGRect) {
        elements = [.rect(rect)]
    }

    public init(ellipseIn rect: CGRect) {
        elements = [.ellipse(in: rect)]
    }

    public init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
        elements = [.roundedRect(rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)]
    }

    public var isEmpty: Bool { elements.isEmpty }

    public mutating func move(to point: CGPoint) {
        elements.append(.move(to: point))
    }

    public mutating func addLine(to point: CGPoint) {
        elements.append(.line(to: point))
    }

    /// A line through each of `points` in turn, starting a new subpath at the first.
    public mutating func addLines(between points: [CGPoint]) {
        guard let first = points.first else {
            return
        }
        move(to: first)
        for point in points.dropFirst() {
            addLine(to: point)
        }
    }

    public mutating func addQuadCurve(to point: CGPoint, control: CGPoint) {
        elements.append(.quadCurve(to: point, control: control))
    }

    public mutating func addCurve(to point: CGPoint, control1: CGPoint, control2: CGPoint) {
        elements.append(.curve(to: point, control1: control1, control2: control2))
    }

    public mutating func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat) {
        elements.append(.arc(tangent1End: tangent1End, tangent2End: tangent2End, radius: radius))
    }

    public mutating func addRect(_ rect: CGRect) {
        elements.append(.rect(rect))
    }

    public mutating func closeSubpath() {
        elements.append(.close)
    }
}

public enum CanvasLineCap: Sendable {
    case butt, round, square
}

public enum CanvasLineJoin: Sendable {
    case miter, round, bevel
}
