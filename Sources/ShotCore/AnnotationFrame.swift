import CoreImage

/// Annotation clips being edited, which the compositor draws in place of what the project has for them,
/// so a drag shows at once without rebuilding the preview. Safe to change from any thread.
public final class LiveAnnotations: @unchecked Sendable {
    private let lock = NSLock()
    private var hidden: Set<UUID> = []
    private var drawn: [AnnotationClip] = []

    public init() {}

    /// Stops drawing the clips in `hidden`, which the project still has, and draws `drawn` in their place while they're showing.
    public func set(hidden: Set<UUID>, drawn: [AnnotationClip]) {
        lock.withLock {
            self.hidden = hidden
            self.drawn = drawn
        }
    }

    public func clear() {
        set(hidden: [], drawn: [])
    }

    func snapshot() -> (hidden: Set<UUID>, drawn: [AnnotationClip]) {
        lock.withLock { (hidden, drawn) }
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
        case .highlight, .spotlight, .pixelate, .blur: true
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
    static func apply(_ items: [Item], to image: CIImage, canvas: CGRect, context: CIContext) -> CIImage {
        var result = image
        var batch: [Annotation] = []
        func flush() {
            if !batch.isEmpty {
                result = apply(batch, to: result, canvas: canvas, context: context)
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
            result = applySpecial(item, to: result, canvas: canvas, context: context)
        }
        flush()
        return result
    }

    private static func fade(_ image: CIImage, to opacity: Double) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(min(max(opacity, 0), 1)))])
    }

    /// One annotation that's turned or faded. What shows through a blur or highlight can't be turned apart from the frame,
    /// so those only fade, as a blend of the frame with and without them.
    private static func applySpecial(_ item: Item, to image: CIImage, canvas: CGRect, context: CIContext) -> CIImage {
        if needsPicture(item.annotation) {
            let with = apply([item.annotation], to: image, canvas: canvas, context: context)
            return fade(with, to: item.opacity).composited(over: image)
        }
        var overlay = apply([item.annotation], to: CIImage(color: .clear).cropped(to: canvas), canvas: canvas, context: context)
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
    static func apply(_ annotations: [Annotation], to image: CIImage, canvas: CGRect, context: CIContext) -> CIImage {
        guard !annotations.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return image
        }
        let width = Int(canvas.width), height = Int(canvas.height)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let target = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo) else {
            return image
        }
        if annotations.contains(where: needsPicture), let picture = context.createCGImage(image, from: canvas, format: .RGBA8, colorSpace: space) {
            // The renderer draws the picture too, then each annotation over it, with the dim of every spotlight at once.
            target.interpolationQuality = .high
            AnnotationRenderer.render(EditorDocument(base: picture, annotations: annotations), into: target)
            return target.makeImage().map { CIImage(cgImage: $0) } ?? image
        }
        target.translateBy(x: 0, y: CGFloat(height))
        target.scaleBy(x: 1, y: -1)
        for annotation in annotations {
            AnnotationRenderer.draw(annotation, base: placeholder, in: target)
        }
        guard let overlay = target.makeImage() else {
            return image
        }
        return CIImage(cgImage: overlay).composited(over: image)
    }
}
