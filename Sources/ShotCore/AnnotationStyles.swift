import CoreGraphics
import Foundation

/// The outline a shape annotation, or a spotlight's lit area, takes within its rect.
public enum BoxShape: String, CaseIterable, Codable, Sendable {
    case rectangle, ellipse, triangle, diamond, star

    /// The shapes a spotlight can light.
    public static let spotlightShapes: [BoxShape] = [.rectangle, .ellipse]

    /// Reads `rounded`, which an older version saved for a rounded rectangle, as a rectangle; `Annotation` gives it the
    /// radius it had.
    public init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let shape = name == "rounded" ? .rectangle : BoxShape(rawValue: name) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown shape \(name)"))
        }
        self = shape
    }

    /// The SF Symbol the toolbar and the layers show for it.
    public var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .triangle: "triangle"
        case .diamond: "diamond"
        case .star: "star"
        }
    }

    /// Whether it has corners to round: every shape but the ellipse.
    public var hasCorners: Bool { self != .ellipse }

    /// The outline stretched to fill `rect`, its corners rounded by `cornerRadius` (square for `nil`). A star rounds only
    /// its points.
    public func path(in rect: CGRect, cornerRadius: CGFloat? = nil) -> CanvasPath {
        switch self {
        case .rectangle:
            let radius = clampedRadius(cornerRadius, in: rect)
            return radius > 0 ? CanvasPath(roundedRect: rect, cornerRadius: radius) : CanvasPath(rect: rect)
        case .ellipse:
            return CanvasPath(ellipseIn: rect)
        case .triangle, .diamond, .star:
            let corners = vertices(in: rect)
            return Self.polygon(corners.points, rounding: clampedRadius(cornerRadius, in: rect), roundedIndices: corners.rounded)
        }
    }

    /// The corners of the outline within `rect`, clockwise from the top left or top, and which of them a radius rounds;
    /// none for an ellipse.
    public func vertices(in rect: CGRect) -> (points: [CGPoint], rounded: Set<Int>) {
        switch self {
        case .rectangle:
            return ([CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)], [0, 1, 2, 3])
        case .ellipse:
            return ([], [])
        case .triangle:
            return ([CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)], [0, 1, 2])
        case .diamond:
            return ([CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)], [0, 1, 2, 3])
        case .star:
            // Five points, scaled so the star's tips touch every side of the rect.
            let angles = (0..<10).map { -CGFloat.pi / 2 + CGFloat($0) * .pi / 5 }
            let unit = angles.enumerated().map { index, angle in
                let radius: CGFloat = index.isMultiple(of: 2) ? 1 : 0.4
                return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            }
            let minX = unit.map(\.x).min()!, maxX = unit.map(\.x).max()!
            let minY = unit.map(\.y).min()!, maxY = unit.map(\.y).max()!
            let points = unit.map {
                CGPoint(x: rect.minX + ($0.x - minX) / (maxX - minX) * rect.width, y: rect.minY + ($0.y - minY) / (maxY - minY) * rect.height)
            }
            // The inner corners between the points stay sharp.
            return (points, Set(stride(from: 0, to: 10, by: 2)))
        }
    }

    /// `radius` within what this shape can take in `rect`, 0 for `nil`: half the shorter side makes a rectangle a pill,
    /// and a triangle, diamond or star stops where the arcs of neighbouring corners would meet.
    public func clampedRadius(_ radius: CGFloat?, in rect: CGRect) -> CGFloat {
        guard hasCorners else {
            return 0
        }
        return min(max(radius ?? 0, 0), maxRadius(in: rect))
    }

    /// The largest radius that rounds every rounded corner of the shape in `rect` without two arcs overlapping. An arc of
    /// radius `r` in a corner of angle `a` takes `r / tan(a / 2)` of each edge it meets.
    public func maxRadius(in rect: CGRect) -> CGFloat {
        if self == .rectangle {
            return max(0, min(rect.width, rect.height) / 2)
        }
        let (points, rounded) = vertices(in: rect)
        let count = points.count
        // Per edge, from a point to the next, how much of it each unit of radius uses up, summed over its rounded ends.
        var use = [CGFloat](repeating: 0, count: count)
        for index in rounded {
            let before = (index + count - 1) % count
            let tangent = Self.tangentPerRadius(at: points[index], from: points[before], to: points[(index + 1) % count])
            use[before] += tangent
            use[index] += tangent
        }
        let limits = points.indices.compactMap { edge -> CGFloat? in
            let next = points[(edge + 1) % count]
            return use[edge] > 0 ? hypot(next.x - points[edge].x, next.y - points[edge].y) / use[edge] : nil
        }
        return limits.min() ?? 0
    }

    /// How far along each of its two edges an arc of radius 1 in the corner at `point` runs, `1 / tan(a / 2)`; 0 when the
    /// corner is flat or degenerate.
    private static func tangentPerRadius(at point: CGPoint, from previous: CGPoint, to next: CGPoint) -> CGFloat {
        let a = CGPoint(x: previous.x - point.x, y: previous.y - point.y), b = CGPoint(x: next.x - point.x, y: next.y - point.y)
        let lengths = hypot(a.x, a.y) * hypot(b.x, b.y)
        guard lengths > 0 else {
            return 0
        }
        let half = acos(min(max((a.x * b.x + a.y * b.y) / lengths, -1), 1)) / 2
        return half > 0 && half < .pi / 2 ? 1 / tan(half) : 0
    }

    /// `radius` within what `rect` can take as a rounded rectangle, which half its shorter side makes a pill; `nil` is
    /// square. Also the limit on a placed image's and the screenshot's corners.
    public static func cornerRadius(_ radius: CGFloat?, in rect: CGRect) -> CGFloat {
        BoxShape.rectangle.clampedRadius(radius, in: rect)
    }

    /// The closed outline through `points`, with an arc of `radius` tangent to both edges at each of `roundedIndices`.
    private static func polygon(_ points: [CGPoint], rounding radius: CGFloat, roundedIndices: Set<Int>) -> CanvasPath {
        var path = CanvasPath()
        let count = points.count
        guard radius > 0, !roundedIndices.isEmpty else {
            path.addLines(between: points)
            path.closeSubpath()
            return path
        }
        for index in 0..<count {
            let next = points[(index + 1) % count]
            if roundedIndices.contains(index) {
                if index == 0 {
                    // Starts where the arc at the first corner does, on the edge into it.
                    let corner = points[0], before = points[count - 1]
                    let distance = hypot(before.x - corner.x, before.y - corner.y)
                    let along = radius * tangentPerRadius(at: corner, from: before, to: next)
                    path.move(to: CGPoint(x: corner.x + (before.x - corner.x) / distance * along, y: corner.y + (before.y - corner.y) / distance * along))
                }
                path.addArc(tangent1End: points[index], tangent2End: next, radius: radius)
            } else if index == 0 {
                path.move(to: points[0])
            } else {
                path.addLine(to: points[index])
            }
        }
        path.closeSubpath()
        return path
    }
}

/// How a redaction hides what's under it.
public enum Redaction: String, CaseIterable, Codable, Sendable {
    case blur, pixelate

    /// How strongly a redaction can hide: its block size or blur radius as a fraction of the image's longer side.
    /// The default is about the strength a line of text got before the amount existed.
    public static let amounts: ClosedRange<CGFloat> = 0.004...0.016
    public static let defaultAmount: CGFloat = 0.008
    /// The smallest block size or blur radius in image pixels, whatever the amount and image, so even the weakest
    /// redaction of a small capture hides body text.
    public static let minimumSize: CGFloat = 6

    public static func clamped(_ amount: CGFloat) -> CGFloat {
        min(max(amount, amounts.lowerBound), amounts.upperBound)
    }

    /// The block size or blur radius in pixels that `amount` gives on an image whose longer side is `imageLength` pixels.
    public static func size(amount: CGFloat, imageLength: CGFloat) -> CGFloat {
        max(minimumSize, amount * imageLength)
    }
}

/// How the lines of a text annotation or note line up within it.
public enum TextAlign: String, CaseIterable, Codable, Sendable {
    case left, center, right

    /// The SF Symbol the toolbar shows for it.
    public var symbol: String {
        switch self {
        case .left: "text.alignleft"
        case .center: "text.aligncenter"
        case .right: "text.alignright"
        }
    }

    /// How far right of the left edge of a box `width` wide `line` starts. Trailing spaces don't count,
    /// so a wrapped line lines up by its last word.
    public func offset(of line: any ShapedLine, in width: CGFloat) -> CGFloat {
        let visible = line.width - line.trailingWhitespaceWidth
        return (width - visible) * fraction
    }

    /// The share of the spare width that goes before a line.
    public var fraction: CGFloat {
        switch self {
        case .left: 0
        case .center: 0.5
        case .right: 1
        }
    }
}

/// Where a note's text sits between its top and bottom when the note is taller than the text.
public enum VerticalTextAlign: String, CaseIterable, Codable, Sendable {
    case top, middle, bottom

    /// The SF Symbol the toolbar shows for it.
    public var symbol: String {
        switch self {
        case .top: "align.vertical.top"
        case .middle: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        }
    }

    /// The share of the spare height that goes above the text.
    public var fraction: CGFloat {
        switch self {
        case .top: 0
        case .middle: 0.5
        case .bottom: 1
        }
    }
}

/// A spotlight's lit shape and edge, and how it treats the image outside it. Every spotlight in an image
/// shares one dim, drawn with the lowest spotlight's effect and strength.
public struct SpotlightStyle: Equatable, Hashable, Codable, Sendable {
    public enum Effect: String, CaseIterable, Codable, Sendable {
        case darken, blur
    }

    /// The strengths the slider offers. Each is also the darken effect's alpha.
    public static let strengths: ClosedRange<Double> = 0.1...0.9

    public var shape: BoxShape
    public var effect: Effect
    public var strength: Double
    /// How far the lit shape fades into the dim, from 0 (a hard edge) to 1 (the softest).
    public var softEdge: Double

    public init(shape: BoxShape = .rectangle, effect: Effect = .darken, strength: Double = 0.5, softEdge: Double = 0) {
        self.shape = shape
        self.effect = effect
        self.strength = strength
        self.softEdge = softEdge
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shape = try container.decode(BoxShape.self, forKey: .shape)
        effect = try container.decode(Effect.self, forKey: .effect)
        // Strength used to be a preset stored as 0, 1 or 2 (light, medium, strong). None of those is in `strengths`.
        let stored = try container.decode(Double.self, forKey: .strength)
        strength = [0: 0.3, 1: 0.5, 2: 0.7][stored] ?? stored
        softEdge = try container.decodeIfPresent(Double.self, forKey: .softEdge) ?? 0
    }

    /// The blur radius of the edge of a spotlight lighting `rect`, relative to its size so it looks the same at any zoom.
    public func softEdgeRadius(in rect: CGRect) -> CGFloat {
        softEdge * 0.2 * min(rect.width, rect.height)
    }

    /// How dark the darken effect makes the image outside the spotlights.
    public var dimAlpha: CGFloat { strength }

    /// The blur effect's radius on an image whose longer side is `length` pixels. It doubles with every 0.2 of
    /// strength, so 0.3, 0.5 and 0.7 match the old light, medium and strong presets.
    public func blurRadius(forImageLength length: CGFloat) -> CGFloat {
        max(4, length * 0.008 * pow(2, (strength - 0.5) / 0.2))
    }
}
