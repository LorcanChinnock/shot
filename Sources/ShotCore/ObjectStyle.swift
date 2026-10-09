import CoreGraphics
import Foundation

/// The shadow and border drawn around an object: the capture or an image placed on it. The empty style draws neither.
public struct ObjectStyle: Equatable, Hashable, Sendable, Codable {
    public var shadow: Shadow?
    public var border: Border?

    public init(shadow: Shadow? = nil, border: Border? = nil) {
        self.shadow = shadow
        self.border = border
    }

    public var isEmpty: Bool { shadow == nil && border == nil }

    /// `rect` grown by how far the shadow and border paint past it.
    public func paintedRect(around rect: CGRect) -> CGRect {
        var painted = rect
        if let border {
            painted = painted.insetBy(dx: -border.width, dy: -border.width)
        }
        if let shadow {
            let reach = shadow.reach
            painted = painted.union(CGRect(
                x: rect.minX - reach.side, y: rect.minY - reach.top,
                width: rect.width + reach.side * 2, height: rect.height + reach.top + reach.bottom
            ))
        }
        return painted
    }
}

/// A soft shadow under an object, lit from straight above. Each preset is a point in the one space of elevation,
/// opacity, colour and whether it drops below the object, so a slider moves from any preset to a custom look.
public struct Shadow: Equatable, Hashable, Sendable, Codable {
    /// Where the shadow's colour comes from.
    public enum Tint: String, Equatable, Hashable, Sendable, Codable {
        /// A dark, greyed shade of the canvas background, or black with none.
        case ambient
        /// The object's own colour, for a glow.
        case object
    }

    /// How high the object seems to float, in image pixels: it sets the offset and blur of every layer.
    public var elevation: CGFloat
    /// The alpha of each layer.
    public var opacity: CGFloat
    public var tint: Tint
    /// Whether the shadow falls below the object, as from a light above, or spreads evenly around it.
    public var isOffset: Bool

    public init(elevation: CGFloat, opacity: CGFloat, tint: Tint = .ambient, isOffset: Bool = true) {
        self.elevation = elevation
        self.opacity = opacity
        self.tint = tint
        self.isOffset = isOffset
    }

    /// The elevations the slider offers, in points.
    public static let elevations: ClosedRange<CGFloat> = 1...48
    /// The opacities the slider offers.
    public static let opacities: ClosedRange<CGFloat> = 0.04...0.6

    /// One pass of the shadow: how far below the object it falls and how far it blurs, in image pixels.
    public struct Layer: Equatable, Sendable {
        public var offset: CGFloat
        public var blur: CGFloat
    }

    /// Three passes, each falling and blurring twice as far as the one before, which together look like real light.
    public var layers: [Layer] {
        [elevation / 4, elevation / 2, elevation].map { distance in
            Layer(offset: isOffset ? distance : 0, blur: distance * 2)
        }
    }

    /// How far the shadow paints past the object above it, to each side and below it. A shadow blurs as far as its blur.
    public var reach: (top: CGFloat, side: CGFloat, bottom: CGFloat) {
        let layers = layers
        return (
            max(0, layers.map { $0.blur - $0.offset }.max() ?? 0).rounded(.up),
            (layers.map(\.blur).max() ?? 0).rounded(.up),
            (layers.map { $0.blur + $0.offset }.max() ?? 0).rounded(.up)
        )
    }

    /// The colour of each layer, at full alpha: `object` for a glow, else a dark, greyed shade of `background`, or
    /// black on a transparent canvas, so the shadow sits in the colours around it.
    public func color(background: RGBA?, object: RGBA) -> RGBA {
        switch tint {
        case .object:
            return RGBA(object.r, object.g, object.b)
        case .ambient:
            guard let background else {
                return RGBA(0, 0, 0)
            }
            let grey = (background.r + background.g + background.b) / 3
            func shade(_ c: CGFloat) -> CGFloat { (c + grey) / 2 * 0.2 }
            return RGBA(shade(background.r), shade(background.g), shade(background.b))
        }
    }
}

/// The named shadows the Style popover offers.
public enum ShadowPreset: String, CaseIterable, Sendable {
    case soft, float, contact, glow

    public var title: String {
        switch self {
        case .soft: "Soft"
        case .float: "Float"
        case .contact: "Contact"
        case .glow: "Glow"
        }
    }

    /// The preset's shadow on a document of `scale` pixels per point.
    public func shadow(scale: CGFloat) -> Shadow {
        switch self {
        case .soft: Shadow(elevation: 12 * scale, opacity: 0.1)
        case .float: Shadow(elevation: 32 * scale, opacity: 0.14)
        case .contact: Shadow(elevation: 3 * scale, opacity: 0.3)
        case .glow: Shadow(elevation: 10 * scale, opacity: 0.35, tint: .object, isOffset: false)
        }
    }

    /// The preset `shadow` is, on a document of `scale` pixels per point; `nil` for a custom one.
    public static func matching(_ shadow: Shadow, scale: CGFloat) -> ShadowPreset? {
        allCases.first { $0.shadow(scale: scale) == shadow }
    }
}

/// A line around an object.
public struct Border: Equatable, Hashable, Sendable, Codable {
    public enum Kind: String, Equatable, Hashable, Sendable, Codable {
        /// One pixel, light on dark content and dark on light, so a screenshot keeps its edge on a page of the same colour.
        case hairline
    }

    public var kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public static let hairline = Border(kind: .hairline)

    /// How far it paints past the object's edge, in image pixels.
    public var width: CGFloat {
        switch kind {
        case .hairline: 1
        }
    }

    /// A light rim on dark content and a dark one on light, from `edge`, the average colour near the object's edge.
    /// Content with nothing near its edge to go by gets the dark one.
    public static func hairlineColor(edge: RGBA?) -> RGBA {
        guard let edge, edge.contrastingInk == RGBA(1, 1, 1) else {
            return RGBA(0, 0, 0, 0.12)
        }
        return RGBA(1, 1, 1, 0.14)
    }
}

/// What the Style popover changes: the capture, or one annotation.
public enum StyleTarget: Equatable, Sendable {
    case capture
    case annotation(UUID)
}

extension Annotation {
    /// True for the kinds the Style popover can give a shadow, border and corner radius: placed images.
    public var takesObjectStyle: Bool {
        if case .image = kind { true } else { false }
    }

    /// A placed image's corner radius, within what its rect can take; 0 for anything else.
    public var imageCornerRadius: CGFloat {
        guard case let .image(_, rect) = kind else {
            return 0
        }
        return BoxShape.cornerRadius(cornerRadius ?? 0, in: rect)
    }
}

extension EditorDocument {
    /// The capture's corner radius, within what the image can take.
    public var clampedCaptureCornerRadius: CGFloat {
        BoxShape.cornerRadius(captureCornerRadius, in: fullRect)
    }

    /// The image plus how far its shadow and border paint past it.
    public var capturePaintedBounds: CGRect {
        captureStyle.paintedRect(around: fullRect)
    }

    /// The style of `target`; empty for an annotation that isn't there.
    public func style(of target: StyleTarget) -> ObjectStyle {
        switch target {
        case .capture: captureStyle
        case let .annotation(id): annotations.first { $0.id == id }?.style ?? ObjectStyle()
        }
    }

    /// The corner radius of `target`, as set; 0 for an annotation that isn't there.
    public func cornerRadius(of target: StyleTarget) -> CGFloat {
        switch target {
        case .capture: captureCornerRadius
        case let .annotation(id): annotations.first { $0.id == id }?.cornerRadius ?? 0
        }
    }

    /// Restyles `target`, growing the canvas to hold its shadow and border and pulling back padding they no longer need.
    /// A locked annotation, or one that can't be styled, is left alone.
    public mutating func setStyle(_ style: ObjectStyle, of target: StyleTarget, margin: CGFloat) {
        switch target {
        case .capture:
            captureStyle = style
            growToFitCapture()
        case let .annotation(id):
            guard let index = annotations.firstIndex(where: { $0.id == id }), annotations[index].takesObjectStyle, !annotations[index].isLocked else {
                return
            }
            annotations[index].style = style
            grow(toFit: annotations[index], margin: margin)
        }
        shrinkPadding(margin: margin)
    }

    /// Sets the corner radius of `target`. A locked annotation, or one that can't be styled, is left alone.
    public mutating func setCornerRadius(_ radius: CGFloat, of target: StyleTarget) {
        let radius = max(0, radius)
        switch target {
        case .capture:
            captureCornerRadius = radius
        case let .annotation(id):
            guard let index = annotations.firstIndex(where: { $0.id == id }), annotations[index].takesObjectStyle, !annotations[index].isLocked else {
                return
            }
            annotations[index].cornerRadius = radius == 0 ? nil : radius
        }
    }

    /// Grows the canvas just enough to show the capture's shadow and border. As with annotations, only edges at or
    /// beyond the image grow; a crop edge inside the image stays.
    public mutating func growToFitCapture() {
        let painted = capturePaintedBounds, image = fullRect
        var minX = canvasRect.minX, minY = canvasRect.minY, maxX = canvasRect.maxX, maxY = canvasRect.maxY
        if minX <= image.minX { minX = min(minX, painted.minX) }
        if minY <= image.minY { minY = min(minY, painted.minY) }
        if maxX >= image.maxX { maxX = max(maxX, painted.maxX) }
        if maxY >= image.maxY { maxY = max(maxY, painted.maxY) }
        canvasRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
    }
}
