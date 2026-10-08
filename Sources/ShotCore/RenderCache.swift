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
    /// Where the drawn image goes; `.zero` with nothing under it there, when it's the screenshot itself.
    let area: CGRect

    init(_ base: CGImage, below: ArraySlice<Annotation>, around rect: CGRect, outset: CGFloat) {
        let area = rect.insetBy(dx: -outset, dy: -outset).integral
        self.base = base
        self.below = Self.annotations(below.filter { !$0.isHidden }, reaching: area, base: base)
        self.area = self.below.isEmpty ? .zero : area
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
        guard !below.isEmpty, let ctx = CGContext(
            data: nil, width: Int(area.width), height: Int(area.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (base, .zero)
        }
        ctx.interpolationQuality = .high
        AnnotationRenderer.renderLayers(EditorDocument(base: base, annotations: below, canvasRect: area), into: ctx)
        guard let image = ctx.makeImage() else {
            return (base, .zero)
        }
        return (image, area.origin)
    }

    static func == (a: Self, b: Self) -> Bool {
        a.base === b.base && a.area == b.area && a.below == b.below
    }
}

/// A spotlight with a soft edge, which fades the dim rather than cutting it out.
struct SoftSpotlight: Equatable, Sendable {
    let rect: CGRect
    let style: SpotlightStyle
    let cornerRadius: CGFloat?
}
