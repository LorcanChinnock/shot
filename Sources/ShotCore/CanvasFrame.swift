import CoreGraphics
import Foundation

/// The shape the Style panel's Size holds the canvas to. Auto leaves it the shape of what it holds.
public enum CanvasAspect: String, CaseIterable, Sendable, Codable {
    case auto, wide, standard, square, portrait

    /// Width over height, or `nil` for Auto.
    public var ratio: CGFloat? {
        switch self {
        case .auto: nil
        case .wide: 16.0 / 9
        case .standard: 4.0 / 3
        case .square: 1
        case .portrait: 4.0 / 5
        }
    }

    public var title: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .wide: "16:9"
        case .standard: "4:3"
        case .square: "1:1"
        case .portrait: "4:5"
        }
    }
}

/// The space the Style panel puts around the screenshot, and the shape it holds the canvas to. Both only ever add canvas,
/// so nothing that was on it is cut off.
public struct CanvasFrame: Equatable, Sendable, Codable {
    /// Space on every side of the screenshot, in image pixels.
    public var padding: CGFloat
    public var aspect: CanvasAspect

    public init(padding: CGFloat = 0, aspect: CanvasAspect = .auto) {
        self.padding = padding
        self.aspect = aspect
    }

    public static let none = CanvasFrame()
    public var isNone: Bool { padding <= 0 && aspect == .auto }

    /// The Padding slider's range, in points.
    public static let paddings: ClosedRange<CGFloat> = 0...120

    /// `canvas` grown to hold `padding` on every side of `image`, then to the aspect, about its centre, on whole pixels.
    /// The side that grows is rounded to the nearest pixel, so a square comes out exactly square.
    public func framing(_ canvas: CGRect, image: CGRect) -> CGRect {
        guard !isNone else {
            return canvas
        }
        var rect = (padding > 0 ? canvas.union(image.insetBy(dx: -padding, dy: -padding)) : canvas).integral
        if let ratio = aspect.ratio, rect.width > 0, rect.height > 0 {
            if rect.width / rect.height < ratio {
                let width = max(rect.width, (rect.height * ratio).rounded())
                rect = CGRect(x: (rect.midX - width / 2).rounded(.down), y: rect.minY, width: width, height: rect.height)
            } else {
                let height = max(rect.height, (rect.width / ratio).rounded())
                rect = CGRect(x: rect.minX, y: (rect.midY - height / 2).rounded(.down), width: rect.width, height: height)
            }
        }
        return rect
    }
}

/// A canvas fill richer than one colour: a soft gradient, or the desktop picture. The document's `background` holds a
/// colour close to it, which tints shadows and stands in where a gradient can't go.
public enum BackgroundFill: String, CaseIterable, Sendable, Codable {
    case dusk, sea, citrus, desktop

    /// The colours from the top-left corner to the bottom-right; the desktop's are drawn when there's no picture of it.
    public var colors: (start: RGBA, end: RGBA) {
        switch self {
        case .dusk: (RGBA(hex: 0xF6C9A8), RGBA(hex: 0xB9A8E8))
        case .sea: (RGBA(hex: 0x9ED6CF), RGBA(hex: 0x6E9BD8))
        case .citrus: (RGBA(hex: 0xFFE48A), RGBA(hex: 0xFF9F6B))
        case .desktop: (RGBA(hex: 0x9C948A), RGBA(hex: 0x776E65))
        }
    }

    /// Whether it runs top to bottom rather than corner to corner.
    public var isVertical: Bool { self == .desktop }

    /// The colour halfway along, which tints shadows over it.
    public var average: RGBA {
        let (start, end) = colors
        return RGBA((start.r + end.r) / 2, (start.g + end.g) / 2, (start.b + end.b) / 2)
    }

    public var title: String {
        switch self {
        case .dusk: String(localized: "Dusk")
        case .sea: String(localized: "Sea")
        case .citrus: String(localized: "Citrus")
        case .desktop: String(localized: "Desktop")
        }
    }
}

/// The background colours the Style panel offers, with their names, ahead of its gradients and custom colour.
public enum BackgroundSwatches {
    public static let colors: [(color: RGBA, name: String)] = [
        (RGBA(hex: 0xF3D9B1), String(localized: "Sand")),
        (RGBA(hex: 0xC9DCEB), String(localized: "Sky")),
        (RGBA(hex: 0xD8E8D0), String(localized: "Sage")),
        (RGBA(hex: 0xF2D3D8), String(localized: "Blush")),
        (RGBA(hex: 0xDCD6F2), String(localized: "Lilac")),
        (RGBA(hex: 0x2A2A2E), String(localized: "Graphite")),
        (RGBA(1, 1, 1), String(localized: "White")),
    ]

    /// Whether `color` is one of the panel's, rather than a custom one.
    public static func contains(_ color: RGBA?) -> Bool {
        color.map { color in colors.contains { $0.color == color } } ?? false
    }
}

/// The canvas part of the style Use for new captures saves: the background, the fill, the padding in points and the size.
public struct CanvasStyle: Equatable, Sendable, Codable {
    public var background: RGBA?
    public var fill: BackgroundFill?
    public var padding: CGFloat
    public var aspect: CanvasAspect

    public init(background: RGBA?, fill: BackgroundFill?, padding: CGFloat, aspect: CanvasAspect) {
        self.background = background
        self.fill = fill
        self.padding = padding
        self.aspect = aspect
    }

    /// Whether `other` is the same, allowing for the rounding a trip from points to pixels and back leaves.
    public func isSame(as other: CanvasStyle) -> Bool {
        background == other.background && fill == other.fill && aspect == other.aspect && abs(padding - other.padding) < 0.001
    }
}

extension RGBA {
    /// An opaque colour from `0xRRGGBB`.
    public init(hex: UInt32) {
        self.init(CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
    }
}

/// What the Style panel shows, and in what order. With the screenshot as the target it's one list in the board's order;
/// with a selection, the selection's own parts come first and the canvas's follow under their own heading.
public enum StylePanelLayout {
    public enum Section: Hashable, Sendable {
        case background, padding, corners, shadow, border, size
        /// The screenshot is a window with the macOS shadow, so it takes no shadow, border or corners of its own.
        case windowShadowNote
        /// Nothing the panel can style is selected, such as a locked mark or text being typed.
        case noTargetNote
        case newCaptures
    }

    /// `kind` is the target's, `nil` when nothing can be styled; `borders` says whether it can take any border.
    public static func sections(kind: StyleKind?, windowShadow: Bool, borders: Bool) -> (target: [Section], canvas: [Section]) {
        let canvas: [Section] = [.background, .padding, .size]
        guard let kind else {
            return ([.noTargetNote], canvas)
        }
        var own: [Section] = []
        if kind == .capture, windowShadow {
            own = [.windowShadowNote]
        } else {
            if kind.takesCorners {
                own.append(.corners)
            }
            own.append(.shadow)
            if borders {
                own.append(.border)
            }
        }
        guard kind == .capture else {
            return (own, canvas)
        }
        return ([.background, .padding] + own + [.size, .newCaptures], [])
    }
}
