import CoreImage

/// Annotation clips being edited, which the compositor draws in place of what the project has for them,
/// so a drag shows at once without rebuilding the preview, and the styles of pictures being restyled or previewed.
/// Safe to change from any thread.
public final class LiveAnnotations: @unchecked Sendable {
    private let lock = NSLock()
    private var hidden: Set<UUID> = []
    private var drawn: [AnnotationClip] = []
    private var clipStyles: [UUID: ObjectStyle] = [:]

    public init() {}

    /// Stops drawing the clips in `hidden`, which the project still has, and draws `drawn` in their place while they're showing.
    public func set(hidden: Set<UUID>, drawn: [AnnotationClip]) {
        lock.withLock {
            self.hidden = hidden
            self.drawn = drawn
        }
    }

    /// Draws the picture of clip `id` with `style` in place of the project's, or as the project has it when `nil`.
    public func set(style: ObjectStyle?, ofClip id: UUID) {
        lock.withLock { clipStyles[id] = style }
    }

    public func clear() {
        lock.withLock {
            hidden = []
            drawn = []
            clipStyles = [:]
        }
    }

    func snapshot() -> (hidden: Set<UUID>, drawn: [AnnotationClip], clipStyles: [UUID: ObjectStyle]) {
        lock.withLock { (hidden, drawn, clipStyles) }
    }
}

/// Overlays already drawn, so annotations that stay the same from frame to frame are drawn once, and Core Image keeps the
/// texture it uploaded for them. Keeps the few used most recently. Safe to use from any thread.
final class OverlayCache: @unchecked Sendable {
    private struct Entry {
        var canvas: CGSize
        var annotations: [Annotation]
        var overlay: CIImage
    }

    private let lock = NSLock()
    private let capacity: Int
    /// Most recently used first.
    private var entries: [Entry] = []

    init(capacity: Int = 4) {
        self.capacity = capacity
    }

    /// The overlay drawn before for `annotations` on `canvas`, or the one `draw` makes, which is kept for next time.
    func overlay(for annotations: [Annotation], canvas: CGSize, draw: () -> CIImage?) -> CIImage? {
        let hit = lock.withLock { () -> CIImage? in
            guard let index = entries.firstIndex(where: { $0.canvas == canvas && $0.annotations == annotations }) else {
                return nil
            }
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
            return entry.overlay
        }
        if let hit {
            return hit
        }
        guard let overlay = draw() else {
            return nil
        }
        lock.withLock {
            entries.insert(Entry(canvas: canvas, annotations: annotations, overlay: overlay), at: 0)
            entries = Array(entries.prefix(capacity))
        }
        return overlay
    }
}

enum AnnotationFrame {
    private static let placeholder: CGImage = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()

    /// Kinds that depend on what's under them: they blend with it, blur it, or dim all but a part of it.
    private static func needsPicture(_ annotation: Annotation) -> Bool {
        switch annotation.kind {
        case .highlight, .marker, .spotlight, .pixelate, .blur: true
        default: false
        }
    }

    /// An annotation to draw, with the turn and fade to give it.
    struct Item {
        var annotation: Annotation
        var rotation: Double = 0
        var opacity: Double = 1

        var isPlain: Bool { abs(rotation) < 1e-6 && opacity >= 0.999 }
    }

    /// `image` with each item drawn over it, bottom to top. Runs of plain ones are drawn together.
    static func apply(_ items: [Item], to image: CIImage, canvas: CGRect, context: CIContext, cache: OverlayCache? = nil) -> CIImage {
        var result = image
        var batch: [Annotation] = []
        func flush() {
            if !batch.isEmpty {
                result = apply(batch, to: result, canvas: canvas, context: context, cache: cache)
                batch = []
            }
        }
        for item in items {
            if item.isPlain {
                batch.append(item.annotation)
                continue
            }
            flush()
            guard item.opacity > 0.001 else {
                continue
            }
            result = applySpecial(item, to: result, canvas: canvas, context: context, cache: cache)
        }
        flush()
        return result
    }

    private static func fade(_ image: CIImage, to opacity: Double) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(min(max(opacity, 0), 1)))])
    }

    /// One annotation that's turned or faded. What shows through a blur or highlight can't be turned apart from the frame,
    /// so those only fade, as a blend of the frame with and without them.
    private static func applySpecial(_ item: Item, to image: CIImage, canvas: CGRect, context: CIContext, cache: OverlayCache?) -> CIImage {
        if needsPicture(item.annotation) {
            let with = apply([item.annotation], to: image, canvas: canvas, context: context)
            return fade(with, to: item.opacity).composited(over: image)
        }
        var overlay = apply([item.annotation], to: CIImage(color: .clear).cropped(to: canvas), canvas: canvas, context: context, cache: cache)
        if abs(item.rotation) > 1e-6 {
            let bounds = item.annotation.bounds
            // The canvas is y down and Core Image y up, so the same turn is the other way round.
            let center = CGPoint(x: bounds.midX, y: canvas.height - bounds.midY)
            let turn = CGAffineTransform(translationX: -center.x, y: -center.y)
                .concatenating(CGAffineTransform(rotationAngle: -item.rotation))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            overlay = overlay.transformed(by: turn)
        }
        return fade(overlay, to: item.opacity).composited(over: image)
    }

    /// `image` with `annotations` drawn over it, bottom to top, in the canvas's own pixels with the origin at the top left.
    /// Plain overlays come from `cache` when it has them.
    static func apply(_ annotations: [Annotation], to image: CIImage, canvas: CGRect, context: CIContext, cache: OverlayCache? = nil) -> CIImage {
        guard !annotations.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return image
        }
        if annotations.contains(where: needsPicture), let target = bitmap(canvas, space: space), let picture = context.createCGImage(image, from: canvas, format: .RGBA8, colorSpace: space) {
            // The renderer draws the picture too, then each annotation over it, with the dim of every spotlight at once.
            target.interpolationQuality = .high
            AnnotationRenderer.render(EditorDocument(base: picture, annotations: annotations), into: target)
            return target.makeImage().map { CIImage(cgImage: $0) } ?? image
        }
        let draw = { overlay(annotations, canvas: canvas, space: space) }
        guard let overlay = cache.map({ $0.overlay(for: annotations, canvas: canvas.size, draw: draw) }) ?? draw() else {
            return image
        }
        return overlay.composited(over: image)
    }

    private static func bitmap(_ canvas: CGRect, space: CGColorSpace) -> CGContext? {
        CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// `annotations` drawn on a clear canvas.
    private static func overlay(_ annotations: [Annotation], canvas: CGRect, space: CGColorSpace) -> CIImage? {
        guard let target = bitmap(canvas, space: space) else {
            return nil
        }
        target.translateBy(x: 0, y: CGFloat(target.height))
        target.scaleBy(x: 1, y: -1)
        for annotation in annotations {
            AnnotationRenderer.draw(annotation, base: placeholder, in: target)
        }
        // A styled annotation's shadow is cached as `render` caches it, so let go of those this frame didn't draw.
        AnnotationRenderer.cache.sweep()
        return target.makeImage().map { CIImage(cgImage: $0) }
    }
}
