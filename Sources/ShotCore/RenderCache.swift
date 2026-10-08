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

/// What a pixelate or blur at `rect` hides: the screenshot, with the images placed under it drawn over it.
/// It reaches `outset` past `rect`, so the filter's edges sample what's really there. Two are equal when they'd
/// draw the same image, which tells without drawing it.
struct Backdrop: Equatable, Sendable {
    let base: CGImage
    let images: [(image: CGImage, rect: CGRect)]
    /// Where the drawn image goes; `.zero` with no placed image under it, when it's the screenshot itself.
    let area: CGRect

    init(_ base: CGImage, images below: ArraySlice<Annotation>, around rect: CGRect, outset: CGFloat) {
        let area = rect.insetBy(dx: -outset, dy: -outset).integral
        self.base = base
        images = below.compactMap { annotation in
            guard case let .image(image, imageRect) = annotation.kind, imageRect.intersects(area) else {
                return nil
            }
            return (image.image, AnnotationRenderer.pixelAligned(imageRect))
        }
        self.area = images.isEmpty ? .zero : area
    }

    /// The image, and where its top-left pixel sits.
    func draw() -> (image: CGImage, origin: CGPoint) {
        guard !images.isEmpty, let ctx = CGContext(
            data: nil, width: Int(area.width), height: Int(area.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (base, .zero)
        }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: area.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -area.minX, y: -area.minY)
        AnnotationRenderer.drawUpright(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height), ctx: ctx)
        for (image, imageRect) in images {
            AnnotationRenderer.drawUpright(image, in: imageRect, ctx: ctx)
        }
        guard let image = ctx.makeImage() else {
            return (base, .zero)
        }
        return (image, area.origin)
    }

    static func == (a: Self, b: Self) -> Bool {
        a.base === b.base && a.area == b.area && a.images.count == b.images.count
            && zip(a.images, b.images).allSatisfy { $0.image === $1.image && $0.rect == $1.rect }
    }
}

/// A spotlight with a soft edge, which fades the dim rather than cutting it out.
struct SoftSpotlight: Equatable, Sendable {
    let rect: CGRect
    let style: SpotlightStyle
    let cornerRadius: CGFloat?
}
