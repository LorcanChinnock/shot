import CoreGraphics
import Foundation
import os

/// The shadow and border drawn around an object: the capture, an image placed on it, a mark or text. The empty style draws neither.
public struct ObjectStyle: Equatable, Hashable, Sendable, Codable {
    public var shadow: Shadow?
    public var border: Border?

    public init(shadow: Shadow? = nil, border: Border? = nil) {
        self.shadow = shadow
        self.border = border
    }

    public var isEmpty: Bool { shadow == nil && border == nil }

    /// `rect` grown by how far the shadow and border paint past it. A border that casts the shadow with the object
    /// moves the shadow out with it.
    public func paintedRect(around rect: CGRect) -> CGRect {
        var painted = rect, silhouette = rect
        if let border {
            painted = painted.insetBy(dx: -border.width, dy: -border.width)
            if border.castsShadow {
                silhouette = painted
            }
        }
        if let shadow {
            let reach = shadow.reach
            painted = painted.union(CGRect(
                x: silhouette.minX - reach.side, y: silhouette.minY - reach.top,
                width: silhouette.width + reach.side * 2, height: silhouette.height + reach.top + reach.bottom
            ))
        }
        return painted
    }

    /// The style with its sizes multiplied by `factor`, to turn one in points into pixels of a document or back.
    public func scaled(by factor: CGFloat) -> ObjectStyle {
        var scaled = self
        scaled.shadow?.elevation *= factor
        if let lineWidth = border?.lineWidth {
            scaled.border?.lineWidth = lineWidth * factor
        }
        return scaled
    }

    /// The style without a border `kind` can't have. `transparent` says whether the object has see-through pixels,
    /// which an outline needs.
    public func restricted(to kind: StyleKind, transparent: Bool) -> ObjectStyle {
        var style = self
        if let border, !kind.borders(transparent: transparent).contains(border.kind) {
            style.border = nil
        }
        return style
    }
}

/// What a style is on, which decides the borders and corners it can have.
public enum StyleKind: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    /// The screenshot.
    case capture
    /// An image placed on the canvas.
    case image
    /// An arrow, line, shape, pen stroke or counter.
    case mark
    case text

    /// The borders it can have. Only an object with see-through pixels, `transparent`, has a shape of its own to outline;
    /// text is outlined letter by letter.
    public func borders(transparent: Bool) -> [Border.Kind] {
        switch self {
        case .capture, .image: transparent ? [.hairline, .solid, .outline] : [.hairline, .solid]
        case .text: [.outline]
        case .mark: []
        }
    }

    /// True for the kinds whose corners the Style popover rounds.
    public var takesCorners: Bool {
        self == .capture || self == .image
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
        /// A line of one colour just outside the object's edge, its corners concentric with the object's.
        case solid
        /// A sticker outline: the shape of an image's opaque pixels grown by the width and filled with one colour, with no
        /// blur, so it stays crisp. Text is outlined letter by letter.
        case outline
    }

    public var kind: Kind
    /// How wide a solid border or an outline is, in image pixels. A hairline is always one pixel, so it has none, which
    /// keeps borders saved before the others decoding the same.
    public var lineWidth: CGFloat?
    /// The colour of a solid border or an outline; white when it has none. A hairline picks its own.
    public var color: RGBA?

    public init(kind: Kind, lineWidth: CGFloat? = nil, color: RGBA? = nil) {
        self.kind = kind
        self.lineWidth = lineWidth
        self.color = color
    }

    public static let hairline = Border(kind: .hairline)

    /// How far it paints past the object's edge, in image pixels.
    public var width: CGFloat {
        switch kind {
        case .hairline: 1
        case .solid, .outline: lineWidth ?? 0
        }
    }

    /// The colour a solid border or an outline is drawn in.
    public var paint: RGBA { color ?? RGBA(1, 1, 1) }

    /// Whether the shadow falls from the border along with the object. A hairline is only a faint rim, so it doesn't.
    public var castsShadow: Bool { kind != .hairline }

    /// The widths S, M and L offers for a `kind` border on `target`, in points. A solid border takes the editor's line
    /// widths; an outline on an image is wide enough to read as a sticker's edge, about 8, 18 and 30 pixels on a Retina
    /// capture, and on text a stroke round each letter, half the line widths. A hairline has none.
    public static func widths(_ kind: Kind, on target: StyleKind) -> [CGFloat] {
        switch (kind, target) {
        case (.hairline, _): []
        case (.solid, _): EditorStyle.widths
        case (.outline, .text): EditorStyle.widths.map { $0 / 2 }
        case (.outline, _): [4, 9, 15]
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
public enum StyleTarget: Equatable, Hashable, Sendable {
    case capture
    case annotation(UUID)
}

extension CGImage {
    /// Whether any of its pixels is see-through, read from a 64×64 copy. An image without alpha isn't, without reading it.
    public var hasTransparentPixels: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }
        let side = 64
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = ctx.data else {
            return false
        }
        // Averaging keeps a thin see-through edge visible in the small copy, where picking single pixels could miss it.
        ctx.interpolationQuality = .medium
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: side, height: side))
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        return (0..<side * side).contains { bytes[$0 * 4 + 3] < 255 }
    }
}

extension Annotation {
    /// What its style is on, which decides what the Style popover offers; `nil` for the kinds it can't style: blurs,
    /// pixelates, spotlights, the highlighter and notes, which have a shadow of their own.
    public var styleKind: StyleKind? {
        switch kind {
        case .image: .image
        case .arrow, .line, .shape, .freehand, .counter: .mark
        case .text: .text
        case .highlight, .pixelate, .blur, .spotlight, .note, .marker: nil
        }
    }

    /// True for the kinds the Style popover can give a shadow or border.
    public var takesObjectStyle: Bool { styleKind != nil }

    /// Whether it's a placed image with see-through pixels, which can take an outline.
    public var hasTransparency: Bool {
        if case let .image(image, _) = kind { image.hasTransparency } else { false }
    }

    /// A placed image's corner radius, within what its rect can take; 0 for anything else.
    public var imageCornerRadius: CGFloat {
        guard case let .image(_, rect) = kind else {
            return 0
        }
        return BoxShape.cornerRadius(cornerRadius ?? 0, in: rect)
    }
}

/// A style copied from one object to paste on others. Its sizes are in points, so it looks the same pasted in a
/// document of another scale.
public struct CopiedStyle: Equatable, Sendable, Codable {
    public var style: ObjectStyle
    /// The corner radius, in points; it's pasted only between kinds with corners.
    public var cornerRadius: CGFloat
    /// What it was copied from, which says which of its fields mean anything.
    public var source: StyleKind

    public init(style: ObjectStyle, cornerRadius: CGFloat = 0, source: StyleKind) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.source = source
    }
}

public extension CopiedStyle {
    /// `style`, the style of a `kind` object on a document of `scale` pixels per point, with this pasted on it: the fields
    /// both have. Every kind has a shadow; the border goes only on a kind that can have that border, `transparent` saying
    /// whether the object has see-through pixels for an outline, and S, M and L stay S, M and L.
    func pasted(on style: ObjectStyle, of kind: StyleKind, transparent: Bool, scale: CGFloat) -> ObjectStyle {
        var copy = self.style
        if var border = copy.border, let lineWidth = border.lineWidth {
            let from = Border.widths(border.kind, on: source), to = Border.widths(border.kind, on: kind)
            if let size = from.firstIndex(of: lineWidth), to.indices.contains(size) {
                border.lineWidth = to[size]
                copy.border = border
            }
        }
        let pasted = copy.scaled(by: scale)
        var restyled = style
        restyled.shadow = pasted.shadow
        if let border = pasted.border {
            if kind.borders(transparent: transparent).contains(border.kind) {
                restyled.border = border
            }
        } else if !source.borders(transparent: true).isEmpty, !kind.borders(transparent: true).isEmpty {
            restyled.border = nil
        }
        return restyled
    }

    /// The corner radius pasted on a `kind` object, in pixels of a document of `scale` pixels per point; `nil` unless both
    /// it and what this was copied from have corners.
    func pastedCornerRadius(on kind: StyleKind, scale: CGFloat) -> CGFloat? {
        source.takesCorners && kind.takesCorners ? cornerRadius * scale : nil
    }

    /// `image`, a new capture of `scale` pixels per point, with this style on it over `background`, as Use this style
    /// for new captures copies it; `nil` when the style changes nothing. A window captured with the macOS shadow,
    /// `windowShadow`, takes no style, so it's `nil` for one.
    func styledCapture(_ image: CGImage, scale: CGFloat, background: RGBA?, windowShadow: Bool = false) -> CGImage? {
        var doc = EditorDocument(base: image, background: background)
        doc.hasWindowShadow = windowShadow
        doc.pasteStyle(self, to: [.capture], scale: scale, margin: 0)
        guard !doc.captureStyle.isEmpty || doc.captureCornerRadius > 0 else {
            return nil
        }
        return AnnotationRenderer.flatten(doc)
    }

    /// Whether `other` is the same style, allowing for the rounding a trip from points to pixels and back leaves.
    func isSameStyle(as other: CopiedStyle) -> Bool {
        func same(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
        func same(_ a: CGFloat?, _ b: CGFloat?) -> Bool {
            switch (a, b) {
            case (nil, nil): true
            case let (a?, b?): same(a, b)
            default: false
            }
        }
        guard source == other.source, same(cornerRadius, other.cornerRadius) else {
            return false
        }
        switch (style.shadow, other.style.shadow) {
        case (nil, nil):
            break
        case let (a?, b?):
            guard a.tint == b.tint, a.isOffset == b.isOffset, same(a.elevation, b.elevation), same(a.opacity, b.opacity) else {
                return false
            }
        default:
            return false
        }
        switch (style.border, other.style.border) {
        case (nil, nil):
            return true
        case let (a?, b?):
            return a.kind == b.kind && a.color == b.color && same(a.lineWidth, b.lineWidth)
        default:
            return false
        }
    }
}
