import CoreGraphics
import os

/// Images a render made with Core Image, each with where it's drawn, kept while their inputs stay the same.
/// Each render sweeps out what wasn't used since the last one, so a 6K blur doesn't outlive its redaction.
final class RenderCache: Sendable {
    enum Key: Equatable, Sendable {
        case dimBlur(Backdrop, radius: CGFloat)
        case pixelate(Backdrop, rect: CGRect, scale: CGFloat)
        case blur(Backdrop, rect: CGRect, radius: CGFloat)
        case softSpotlight(SoftSpotlight)
        case softSpotlightMask([SoftSpotlight], area: CGRect)
        case edgeSample(SampledImage)
        case outlineMask(SampledImage, radius: CGFloat)
        case shadow(ShadowCaster, color: RGBA, unit: CGFloat)
    }

    typealias Value = (image: CGImage, frame: CGRect)

    private let entries = OSAllocatedUnfairLock<[(key: Key, value: Value, used: Bool)]>(initialState: [])

    /// The image cached for `key`, or else what `make` returns, cached.
    func value(for key: Key, make: () -> Value?) -> Value? {
        let hit = entries.withLock { entries -> Value? in
            guard let index = entries.firstIndex(where: { $0.key == key }) else {
                return nil
            }
            entries[index].used = true
            return entries[index].value
        }
        if let hit {
            return hit
        }
        guard let value = make() else {
            return nil
        }
        entries.withLock { $0.append((key, value, true)) }
        return value
    }

    /// Drops every image not used since the last sweep.
    func sweep() {
        entries.withLock { entries in
            entries = entries.filter(\.used).map { ($0.key, $0.value, false) }
        }
    }

    var count: Int { entries.withLock { $0.count } }
}

/// What a layer that reads what's under it acts on at `rect`: the screenshot with the annotations under it drawn over it,
/// as they look by then. It reaches `outset` past `rect`, so the filter's edges sample what's really there. Two are
/// equal when they'd draw the same image, which tells without drawing it.
struct Backdrop: Equatable, Sendable {
    let base: CGImage
    /// The annotations under it that can change what's drawn in `area`, back to front.
    let below: [Annotation]
    /// How the screenshot itself is drawn.
    let look: CaptureLook
    /// Where the drawn image goes; `.zero` with nothing under it there and a plain screenshot, when it's the screenshot itself.
    let area: CGRect

    init(_ base: CGImage, below: ArraySlice<Annotation>, around rect: CGRect, outset: CGFloat, look: CaptureLook = CaptureLook()) {
        let area = rect.insetBy(dx: -outset, dy: -outset).integral
        self.base = base
        self.below = Self.annotations(below.filter { !$0.isHidden }, reaching: area, base: base)
        self.look = look
        self.area = self.below.isEmpty && look.isPlain ? .zero : area
    }

    /// Those of `annotations` that can change what's drawn in `area`: working down from the top, each one drawn in the
    /// region that matters so far, which grows by how far the ones that read what's under them read.
    private static func annotations(_ annotations: [Annotation], reaching area: CGRect, base: CGImage) -> [Annotation] {
        var region = area
        var picked: [Annotation] = []
        for annotation in annotations.reversed() where annotation.drawnArea.intersects(region) {
            picked.append(annotation)
            if let reach = annotation.backdropReach(base: base) {
                region = region.union(annotation.drawnArea.intersection(region).insetBy(dx: -reach, dy: -reach))
            }
        }
        return picked.reversed()
    }

    /// The image, and where its top-left pixel sits.
    func draw() -> (image: CGImage, origin: CGPoint) {
        guard area != .zero, let ctx = CGContext(
            data: nil, width: Int(area.width), height: Int(area.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (base, .zero)
        }
        ctx.interpolationQuality = .high
        var doc = EditorDocument(base: base, annotations: below, canvasRect: area)
        doc.captureCornerRadius = look.cornerRadius
        doc.captureStyle = look.style
        AnnotationRenderer.renderLayers(doc, into: ctx, shadowBackground: look.background)
        guard let image = ctx.makeImage() else {
            return (base, .zero)
        }
        return (image, area.origin)
    }

    static func == (a: Self, b: Self) -> Bool {
        a.base === b.base && a.area == b.area && a.below == b.below && a.look == b.look
    }
}

/// How the screenshot under the annotations is drawn: its corners, shadow and border, and the background that tints
/// the shadows. A backdrop draws without the background itself, so the layer over it sees the padding as it did before.
struct CaptureLook: Equatable, Sendable {
    var cornerRadius: CGFloat = 0
    var style = ObjectStyle()
    var background: RGBA?

    /// True when the screenshot is drawn as it is, which a backdrop with nothing else in it needn't draw.
    var isPlain: Bool { cornerRadius == 0 && style.isEmpty }
}

/// An image whose edge colour is sampled or whose outline is grown, the same while it's the same image, so comparing
/// never reads the pixels.
struct SampledImage: Equatable, Sendable {
    let image: CGImage

    static func == (a: Self, b: Self) -> Bool {
        a.image === b.image
    }
}

/// What casts a shadow, and where, which tells whether a shadow drawn before is still the same without drawing it.
enum ShadowCaster: Equatable, Sendable {
    case annotation(Annotation)
    case image(SampledImage, rect: CGRect, cornerRadius: CGFloat, style: ObjectStyle)

    /// The caster with `origin` moved to zero and every position on a grid of 1/64 of a pixel, so the same caster
    /// anywhere else, even moved by a fraction of a pixel, compares equal, and its shadow only needs moving.
    func relative(to origin: CGPoint) -> ShadowCaster {
        func snap(_ point: CGPoint) -> CGPoint {
            CGPoint(x: ((point.x - origin.x) * 64).rounded() / 64, y: ((point.y - origin.y) * 64).rounded() / 64)
        }
        switch self {
        case var .annotation(annotation):
            annotation.movePositions(snap)
            return .annotation(annotation)
        case let .image(image, rect, cornerRadius, style):
            return .image(image, rect: CGRect(origin: snap(rect.origin), size: rect.size), cornerRadius: cornerRadius, style: style)
        }
    }
}

/// A spotlight with a soft edge, which fades the dim rather than cutting it out.
struct SoftSpotlight: Equatable, Sendable {
    let rect: CGRect
    let style: SpotlightStyle
    let cornerRadius: CGFloat?
}
