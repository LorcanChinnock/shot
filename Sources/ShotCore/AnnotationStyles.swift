import CoreGraphics
import CoreText
import Foundation

/// The outline a shape annotation, or a spotlight's lit area, takes within its rect.
public enum BoxShape: String, CaseIterable, Codable, Sendable {
    case rectangle, rounded, ellipse, triangle, diamond, star

    /// The shapes a spotlight can light.
    public static let spotlightShapes: [BoxShape] = [.rectangle, .rounded, .ellipse]

    public var title: String {
        switch self {
        case .rectangle: "Rectangle"
        case .rounded: "Rounded Rectangle"
        case .ellipse: "Ellipse"
        case .triangle: "Triangle"
        case .diamond: "Diamond"
        case .star: "Star"
        }
    }

    /// The outline stretched to fill `rect`.
    public func path(in rect: CGRect) -> CGPath {
        switch self {
        case .rectangle:
            return CGPath(rect: rect, transform: nil)
        case .rounded:
            let radius = min(rect.width, rect.height) / 5
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .triangle:
            return Self.polygon([CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)])
        case .diamond:
            return Self.polygon([CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)])
        case .star:
            // Five points, scaled so the star's tips touch every side of the rect.
            let angles = (0..<10).map { -CGFloat.pi / 2 + CGFloat($0) * .pi / 5 }
            let unit = angles.enumerated().map { index, angle in
                let radius: CGFloat = index.isMultiple(of: 2) ? 1 : 0.4
                return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            }
            let minX = unit.map(\.x).min()!, maxX = unit.map(\.x).max()!
            let minY = unit.map(\.y).min()!, maxY = unit.map(\.y).max()!
            return Self.polygon(unit.map {
                CGPoint(x: rect.minX + ($0.x - minX) / (maxX - minX) * rect.width, y: rect.minY + ($0.y - minY) / (maxY - minY) * rect.height)
            })
        }
    }

    private static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }
}

/// How a redaction hides what's under it.
public enum Redaction: String, CaseIterable, Codable, Sendable {
    case blur, pixelate

    public var title: String {
        switch self {
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        }
    }
}

/// How the lines of a text annotation or note line up within it.
public enum TextAlign: String, CaseIterable, Codable, Sendable {
    case left, center, right

    public var title: String {
        switch self {
        case .left: "Align Left"
        case .center: "Align Centre"
        case .right: "Align Right"
        }
    }

    /// How far right of the left edge of a box `width` wide `line` starts. Trailing spaces don't count,
    /// so a wrapped line lines up by its last word.
    public func offset(of line: CTLine, in width: CGFloat) -> CGFloat {
        let visible = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))
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

/// A spotlight's lit shape, and how it treats the image outside it. Every spotlight in an image
/// shares one dim, drawn with the lowest spotlight's effect and strength.
public struct SpotlightStyle: Equatable, Hashable, Codable, Sendable {
    public enum Effect: String, CaseIterable, Codable, Sendable {
        case darken, blur

        public var title: String {
            switch self {
            case .darken: "Darken"
            case .blur: "Blur"
            }
        }
    }

    public enum Strength: Int, CaseIterable, Codable, Sendable {
        case light, medium, strong

        public var title: String {
            switch self {
            case .light: "Light"
            case .medium: "Medium"
            case .strong: "Strong"
            }
        }
    }

    public var shape: BoxShape
    public var effect: Effect
    public var strength: Strength

    public init(shape: BoxShape = .rectangle, effect: Effect = .darken, strength: Strength = .medium) {
        self.shape = shape
        self.effect = effect
        self.strength = strength
    }

    /// How dark the darken effect makes the image outside the spotlights.
    public var dimAlpha: CGFloat {
        switch strength {
        case .light: 0.3
        case .medium: 0.5
        case .strong: 0.7
        }
    }

    /// The blur effect's radius on an image whose longer side is `length` pixels.
    public func blurRadius(forImageLength length: CGFloat) -> CGFloat {
        let fraction: CGFloat = switch strength {
        case .light: 0.004
        case .medium: 0.008
        case .strong: 0.016
        }
        return max(4, length * fraction)
    }
}
