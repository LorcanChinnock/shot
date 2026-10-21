import Foundation

/// A colour in sRGB, each channel from 0 to 1.
public struct RGBA: Equatable, Hashable, Sendable, Codable {
    public var r, g, b, a: CGFloat

    public init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// `#RRGGBB`, plus the alpha when it isn't opaque.
    public var hex: String { HexColor.string(red: r, green: g, blue: b, alpha: a) }

    public static let presets: [RGBA] = [
        RGBA(1, 0.23, 0.19), RGBA(1, 0.58, 0), RGBA(1, 0.8, 0),
        RGBA(0.2, 0.78, 0.35), RGBA(0, 0.48, 1), RGBA(0, 0, 0), RGBA(1, 1, 1),
    ]

    /// A sticky note's paper: the colour mixed most of the way to white.
    public var noteFill: RGBA {
        RGBA(r + (1 - r) * 0.6, g + (1 - g) * 0.6, b + (1 - b) * 0.6, a)
    }

    /// WCAG relative luminance of the sRGB colour.
    public var relativeLuminance: CGFloat {
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Near-black or white, whichever reads better on this colour.
    public var contrastingInk: RGBA {
        let ink = RGBA(0.07, 0.07, 0.10), white = RGBA(1, 1, 1)
        let l = relativeLuminance
        return (l + 0.05) / (ink.relativeLuminance + 0.05) >= (white.relativeLuminance + 0.05) / (l + 0.05) ? ink : white
    }
}
