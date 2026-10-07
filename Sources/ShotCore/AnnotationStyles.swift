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

    /// The outline stretched to fill `rect`, a rounded rectangle's corners rounded by `cornerRadius`.
    public func path(in rect: CGRect, cornerRadius: CGFloat? = nil) -> CGPath {
        switch self {
        case .rectangle:
            return CGPath(rect: rect, transform: nil)
        case .rounded:
            let radius = Self.cornerRadius(cornerRadius, in: rect)
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

    /// `radius` within what `rect` can take: half its shorter side makes a pill. `nil` is the radius from before it could
    /// be set, a fifth of the shorter side, so older annotations keep their look.
    public static func cornerRadius(_ radius: CGFloat?, in rect: CGRect) -> CGFloat {
        let shorter = max(0, min(rect.width, rect.height))
        return min(max(radius ?? shorter / 5, 0), shorter / 2)
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

/// A spotlight's lit shape and edge, and how it treats the image outside it. Every spotlight in an image
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
