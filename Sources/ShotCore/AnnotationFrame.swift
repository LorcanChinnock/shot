import CoreImage
import Synchronization

/// Annotation clips being edited, which the compositor draws in place of what the project has for them,
/// so a drag shows at once without rebuilding the preview, and the styles of pictures being restyled or previewed.
/// Safe to change from any thread.
public final class LiveAnnotations: Sendable {
    private struct State {
        var hidden: Set<UUID> = []
        var drawn: [AnnotationClip] = []
        var clipStyles: [UUID: ObjectStyle] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    /// Stops drawing the clips in `hidden`, which the project still has, and draws `drawn` in their place while they're showing.
    public func set(hidden: Set<UUID>, drawn: [AnnotationClip]) {
        state.withLock {
            $0.hidden = hidden
            $0.drawn = drawn
        }
    }

    /// Draws the picture of clip `id` with `style` in place of the project's, or as the project has it when `nil`.
    public func set(style: ObjectStyle?, ofClip id: UUID) {
        state.withLock { $0.clipStyles[id] = style }
    }

    public func clear() {
        state.withLock { $0 = State() }
    }

    func snapshot() -> (hidden: Set<UUID>, drawn: [AnnotationClip], clipStyles: [UUID: ObjectStyle]) {
        state.withLock { ($0.hidden, $0.drawn, $0.clipStyles) }
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

extension AnnotationFrame {
    /// `image` with each item drawn over it, bottom to top, on `canvasType` canvases. Runs of plain ones are drawn together.
    static func apply(_ items: [Item], to image: CIImage, canvas: CGRect, context: CIContext, cache: OverlayCache? = nil, canvasType: any Canvas.Type) -> CIImage {
        var result = image
        var batch: [Annotation] = []
        func flush() {
            if !batch.isEmpty {
                result = apply(batch, to: result, canvas: canvas, context: context, cache: cache, canvasType: canvasType)
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
            result = applySpecial(item, to: result, canvas: canvas, context: context, cache: cache, canvasType: canvasType)
        }
        flush()
        return result
    }

    private static func fade(_ image: CIImage, to opacity: Double) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(min(max(opacity, 0), 1)))])
    }

    /// One annotation that's turned or faded. What shows through a blur or highlight can't be turned apart from the frame,
    /// so those only fade, as a blend of the frame with and without them.
    private static func applySpecial(_ item: Item, to image: CIImage, canvas: CGRect, context: CIContext, cache: OverlayCache?, canvasType: any Canvas.Type) -> CIImage {
        if needsPicture(item.annotation) {
            let with = apply([item.annotation], to: image, canvas: canvas, context: context, canvasType: canvasType)
            return fade(with, to: item.opacity).composited(over: image)
        }
        var overlay = apply([item.annotation], to: CIImage(color: .clear).cropped(to: canvas), canvas: canvas, context: context, cache: cache, canvasType: canvasType)
        if abs(item.rotation) > 1e-6 {
            let bounds = item.annotation.bounds(shaper: canvasType.shaper)
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
    static func apply(_ annotations: [Annotation], to image: CIImage, canvas: CGRect, context: CIContext, cache: OverlayCache? = nil, canvasType: any Canvas.Type) -> CIImage {
        guard !annotations.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return image
        }
        if annotations.contains(where: needsPicture), let target = canvasType.init(width: Int(canvas.width), height: Int(canvas.height), format: .sRGB),
           let picture = context.createCGImage(image, from: canvas, format: .RGBA8, colorSpace: space) {
            // The renderer draws the picture too, then each annotation over it, with the dim of every spotlight at once.
            target.setInterpolation(.high)
            AnnotationRenderer.render(EditorDocument(base: picture, annotations: annotations), into: target)
            return target.makeImage().map { CIImage(cgImage: $0) } ?? image
        }
        let draw = { overlay(annotations, canvas: canvas, canvasType: canvasType) }
        guard let overlay = cache.map({ $0.overlay(for: annotations, canvas: canvas.size, draw: draw) }) ?? draw() else {
            return image
        }
        return overlay.composited(over: image)
    }

    /// `annotations` drawn on a clear canvas.
    private static func overlay(_ annotations: [Annotation], canvas: CGRect, canvasType: any Canvas.Type) -> CIImage? {
        guard let target = canvasType.init(width: Int(canvas.width), height: Int(canvas.height), format: .sRGB) else {
            return nil
        }
        target.translateBy(x: 0, y: CGFloat(Int(canvas.height)))
        target.scaleBy(x: 1, y: -1)
        for annotation in annotations {
            AnnotationRenderer.draw(annotation, base: canvasType.placeholder, in: target)
        }
        // A styled annotation's shadow is cached as `render` caches it, so let go of those this frame didn't draw.
        AnnotationRenderer.cache.sweep()
        return target.makeImage().map { CIImage(cgImage: $0) }
    }
}
