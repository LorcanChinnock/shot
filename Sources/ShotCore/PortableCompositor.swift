import Foundation

/// Draws a project's frames one at a time on `Canvas`es, as `ProjectCompositor` draws them on a Mac with Core Image, for
/// where there's no Core Image. Each frame is the canvas background, then each layer `FrameLayers` gives bottom to top:
/// a picture placed by its clip's geometry, with its corners, border, shadow and fade, or a run of annotations drawn
/// together, so an effect acts on everything under it. It keeps the Mac compositor's caches: each clip's blurred shadow
/// mask by scale step, and its edge colour once a second. Safe to use from any thread.
public final class PortableCompositor: Sendable {
    public let project: Project
    /// What the frames and annotations are drawn on.
    public let canvasType: any Canvas.Type
    private let segments: [VideoSegment]
    private let clips: [UUID: Clip]
    private let annotations: [UUID: AnnotationClip]
    private let shadows = ClipShadowCache()
    private let edges = ClipEdgeCache()

    public init(project: Project, canvasType: any Canvas.Type) {
        self.project = project
        self.canvasType = canvasType
        segments = project.videoSegments()
        clips = Dictionary(project.videoTracks.flatMap(\.clips).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        annotations = Dictionary(project.annotationClips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The video clips showing at timeline `time`, bottom to top, each with the time in its source of the frame it
    /// shows then, which `frame(at:pictures:)` needs.
    public func pictures(at time: Double) -> [(clip: Clip, sourceTime: Double)] {
        (segment(at: time)?.clips ?? []).compactMap { clips[$0] }.map { ($0, $0.sourceStart + time - $0.start) }
    }

    /// The frame at timeline `time`, at the project's output size. `pictures` holds the source frame each clip showing
    /// then shows, by the clip's id, upright and at the clip's size; a clip without one isn't drawn, so the annotations
    /// either side of it draw together. `nil` if a canvas can't be made.
    public func frame(at time: Double, pictures: [UUID: PlatformImage]) -> PlatformImage? {
        let canvas = LayerGeometry.evenSize(project.canvasSize)
        guard let ctx = canvasType.init(width: Int(canvas.width), height: Int(canvas.height), format: .sRGB) else {
            return nil
        }
        ctx.setFillColor(RGBA(0, 0, 0))
        ctx.fill(CGRect(origin: .zero, size: canvas))
        let stack = (segment(at: time)?.layers ?? []).compactMap { layer -> FrameLayers.Source<PlatformImage>? in
            switch layer {
            case let .clip(id): clips[id].flatMap { clip in pictures[id].map { .picture($0, clip) } }
            case let .annotation(id): annotations[id].map(FrameLayers.Source.annotation)
            }
        }
        let layers = FrameLayers.layers(of: stack, at: time, hidden: [], drawn: [], clipStyles: [:], shaper: canvasType.shaper)
        for layer in layers {
            switch layer {
            case let .annotations(items):
                draw(items, on: ctx, canvas: canvas)
            case let .picture(frame, clip):
                draw(frame, of: clip, at: time, on: ctx, canvas: canvas)
            }
        }
        // Annotations' shadows and the like are kept from frame to frame while they're drawn.
        AnnotationRenderer.cache.sweep()
        guard let image = ctx.makeImage() else {
            return nil
        }
        // A cropped frame shows only its part of the canvas.
        let output = project.outputRect
        return output == CGRect(origin: .zero, size: canvas) ? image : image.cropping(to: output)
    }

    /// The segment showing at `time`; the last one runs on to the end, as the Mac's last instruction does.
    private func segment(at time: Double) -> VideoSegment? {
        segments.first { time < $0.range.upperBound } ?? segments.last
    }

    // MARK: - Pictures

    /// Draws `frame`, `clip`'s picture with the clip's transform and style at `time`, on `ctx`, `canvas` pixels.
    private func draw(_ frame: PlatformImage, of clip: Clip, at time: Double, on ctx: any Canvas, canvas: CGSize) {
        let size = clip.size
        guard size.width > 0, size.height > 0, clip.transform.scale > 0 else {
            return
        }
        // Fitted by the whole picture, so a crop masks it where it is.
        let fit = min(project.canvasSize.width / size.width, project.canvasSize.height / size.height)
        let kept = LayerGeometry.keptRect(of: clip)
        let picture = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        ctx.setInterpolation(.medium)
        guard clip.isStyled else {
            ctx.saveState()
            defer { ctx.restoreState() }
            place(clip, at: .zero, on: ctx, canvas: canvas)
            if clip.crop != nil {
                ctx.clip(to: kept)
            }
            ctx.setAlpha(max(0, clip.transform.opacity))
            AnnotationRenderer.drawUpright(frame, in: picture, ctx: ctx)
            return
        }
        // Styled about the part the crop leaves, as a picture of its own.
        var cut = clip
        cut.size = kept.size
        let scale = CGFloat(clip.transform.scale), opacity = CGFloat(min(max(clip.transform.opacity, 0), 1))
        let look = ClipStyler.Look(cut, scale: scale, fit: fit)
        let needsEdge = clip.style.border?.kind == .hairline || clip.style.shadow?.tint == .object
        let edge = needsEdge ? edges.color(of: clip.id, second: Int((time - clip.start).rounded(.down))) { edgeColor(of: frame) } : nil
        if let shadow = clip.style.shadow, opacity > 0 {
            drawShadow(shadow, of: clip, cut: cut, edge: edge, fit: fit, opacity: opacity, lift: clip.animation.lift(at: time - clip.start), on: ctx, canvas: canvas)
        }
        ctx.saveState()
        defer { ctx.restoreState() }
        place(clip, at: kept.origin, on: ctx, canvas: canvas)
        ctx.scaleBy(x: 1 / (fit * scale), y: 1 / (fit * scale))
        if opacity < 1 {
            ctx.setAlpha(opacity)
            ctx.beginTransparencyLayer()
        }
        // A solid border tucks half a pixel under the picture, so no seam shows between them, and casts the shadow with
        // it; a hairline is a faint rim just outside the edge, light on a dark frame and dark on a light one.
        let border = clip.style.border
        func drawBorder(_ border: Border) {
            let overlap: CGFloat = border.kind == .solid ? 0.5 : 0
            let inset = (look.borderWidth - overlap) / 2
            ctx.setStrokeColor(border.kind == .hairline ? Border.hairlineColor(edge: edge ?? RGBA(0, 0, 0)) : border.paint)
            ctx.setLineWidth(look.borderWidth + overlap)
            ctx.stroke(CanvasPath(roundedRect: look.rect.insetBy(dx: -inset, dy: -inset), cornerRadius: look.radius > 0 ? look.radius + inset : 0))
        }
        if let border, border.castsShadow {
            drawBorder(border)
        }
        ctx.saveState()
        ctx.clip(to: look.radius > 0 ? CanvasPath(roundedRect: look.rect, cornerRadius: look.radius) : CanvasPath(rect: look.rect))
        let unit = fit * scale
        AnnotationRenderer.drawUpright(frame, in: CGRect(x: -kept.minX * unit, y: -kept.minY * unit, width: picture.width * unit, height: picture.height * unit), ctx: ctx)
        ctx.restoreState()
        if let border, !border.castsShadow {
            drawBorder(border)
        }
        if opacity < 1 {
            ctx.endTransparencyLayer()
        }
    }

    /// Turns `ctx` from y up to y down, then maps `clip`'s picture onto it as `LayerGeometry.transform` does, with the
    /// origin moved to `origin` in the picture.
    private func place(_ clip: Clip, at origin: CGPoint, on ctx: any Canvas, canvas: CGSize) {
        let size = clip.size, transform = clip.transform
        let fit = min(project.canvasSize.width / size.width, project.canvasSize.height / size.height) * transform.scale
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: project.canvasSize.width / 2 + transform.offset.width, y: project.canvasSize.height / 2 + transform.offset.height)
        ctx.rotate(by: transform.rotation)
        ctx.scaleBy(x: fit, y: fit)
        ctx.translateBy(x: origin.x - size.width / 2, y: origin.y - size.height / 2)
    }

    /// The shadow `clip` casts: one cached mask per layer, scaled from the scale it was blurred at, moved down by the
    /// layer's offset and tinted. Nothing is blurred unless the clip's scale or lift moved to a new step.
    private func drawShadow(
        _ shadow: Shadow, of clip: Clip, cut: Clip, edge: RGBA?, fit: CGFloat, opacity: CGFloat, lift: Double, on ctx: any Canvas, canvas: CGSize
    ) {
        let scale = CGFloat(clip.transform.scale)
        let (stepped, lifted) = ClipStyler.steps(scale: scale, lift: CGFloat(lift))
        let caster = ClipStyler.Look(cut, scale: stepped, fit: fit)
        var blurred = shadow, shown = shadow
        blurred.elevation *= stepped * lifted
        shown.elevation *= scale * CGFloat(lift)
        // A glow takes the colour of the frame's edge, as an image's does.
        let color = shadow.color(background: nil, object: edge ?? RGBA(1, 1, 1))
        let paint = RGBA(color.r, color.g, color.b, shadow.opacity * opacity)
        let kept = LayerGeometry.keptRect(of: clip)
        for (blur, offset) in zip(blurred.layers.map(\.blur), shown.layers.map(\.offset)) {
            let key = ClipShadowCache.Key(silhouette: caster.silhouette, radius: caster.silhouetteRadius, blur: blur)
            guard let mask = shadows.mask(for: key, make: { shadowMask(key) }) else {
                continue
            }
            ctx.saveState()
            // Lit from above, so it falls down the canvas whichever way the clip is turned.
            ctx.translateBy(x: 0, y: -offset)
            place(clip, at: kept.origin, on: ctx, canvas: canvas)
            ctx.scaleBy(x: 1 / (fit * stepped), y: 1 / (fit * stepped))
            // Upright, as `drawUpright` draws an image, since a mask is drawn like one.
            ctx.translateBy(x: 0, y: mask.frame.maxY)
            ctx.scaleBy(x: 1, y: -1)
            let flipped = CGRect(x: mask.frame.minX, y: 0, width: mask.frame.width, height: mask.frame.height)
            ctx.clip(to: flipped, mask: mask.mask)
            ctx.setFillColor(paint)
            ctx.fill(flipped)
            ctx.restoreState()
        }
    }

    /// The silhouette in `key` blurred, as grey coverage over black, over `ClipStyler.maskArea`, its top row at the
    /// frame's min y.
    private func shadowMask(_ key: ClipShadowCache.Key) -> ClipShadowCache.Value? {
        let (frame, unit) = ClipStyler.maskArea(key)
        let pixels = CGRect(x: frame.minX * unit, y: frame.minY * unit, width: frame.width * unit, height: frame.height * unit).integral
        guard pixels.width >= 1, pixels.height >= 1, let ctx = canvasType.init(width: Int(pixels.width), height: Int(pixels.height), format: .grey) else {
            return nil
        }
        ctx.translateBy(x: 0, y: pixels.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -pixels.minX, y: -pixels.minY)
        let silhouette = CGRect(x: key.silhouette.minX * unit, y: key.silhouette.minY * unit, width: key.silhouette.width * unit, height: key.silhouette.height * unit)
        ctx.setFillColor(RGBA(1, 1, 1))
        ctx.fill(CanvasPath(roundedRect: silhouette, cornerRadius: key.radius * unit))
        guard let shape = ctx.makeImage(), let mask = canvasType.effects.blurredMask(shape, radius: key.blur * unit / 2) else {
            return nil
        }
        return (mask, CGRect(x: pixels.minX / unit, y: pixels.minY / unit, width: pixels.width / unit, height: pixels.height / unit))
    }

    /// The average colour near `frame`'s edge, an eighth of its shorter side deep all round, as an image's is read.
    private func edgeColor(of frame: PlatformImage) -> RGBA? {
        let side = AnnotationRenderer.edgeSampleSide
        guard let ctx = canvasType.init(width: side, height: side, format: .sRGB) else {
            return nil
        }
        ctx.setInterpolation(.medium)
        ctx.draw(frame, in: CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeBitmap().flatMap(AnnotationRenderer.edgeColor(ofSample:))
    }

    // MARK: - Annotations

    /// Draws each item over what's on `ctx`, bottom to top. Runs of plain ones are drawn together.
    private func draw(_ items: [AnnotationFrame.Item], on ctx: any Canvas, canvas: CGSize) {
        var batch: [Annotation] = []
        func flush() {
            if !batch.isEmpty {
                draw(batch, on: ctx, canvas: canvas)
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
            drawSpecial(item, on: ctx, canvas: canvas)
        }
        flush()
    }

    /// Draws `annotations` over what's on `ctx`, in the canvas's own pixels with the origin at the top left.
    private func draw(_ annotations: [Annotation], on ctx: any Canvas, canvas: CGSize) {
        guard annotations.contains(where: AnnotationFrame.needsPicture) else {
            ctx.saveState()
            ctx.translateBy(x: 0, y: canvas.height)
            ctx.scaleBy(x: 1, y: -1)
            for annotation in annotations {
                AnnotationRenderer.draw(annotation, base: canvasType.placeholder, in: ctx)
            }
            ctx.restoreState()
            return
        }
        // The renderer draws what's there so far too, then each annotation over it, with the dim of every spotlight at once.
        guard let picture = ctx.makeImage() else {
            return
        }
        ctx.saveState()
        ctx.setInterpolation(.high)
        AnnotationRenderer.renderLayers(EditorDocument(base: picture, annotations: annotations), into: ctx, shadowBackground: nil)
        ctx.restoreState()
    }

    /// One annotation that's turned or faded. What shows through a blur or highlight can't be turned apart from the frame,
    /// so those only fade, as a blend of the frame with and without them.
    private func drawSpecial(_ item: AnnotationFrame.Item, on ctx: any Canvas, canvas: CGSize) {
        let opacity = CGFloat(min(max(item.opacity, 0), 1))
        if AnnotationFrame.needsPicture(item.annotation) {
            guard let picture = ctx.makeImage(), let with = canvasType.init(width: Int(canvas.width), height: Int(canvas.height), format: .sRGB) else {
                return
            }
            with.setInterpolation(.high)
            AnnotationRenderer.renderLayers(EditorDocument(base: picture, annotations: [item.annotation]), into: with, shadowBackground: nil)
            guard let drawn = with.makeImage() else {
                return
            }
            ctx.saveState()
            ctx.setAlpha(opacity)
            ctx.draw(drawn, in: CGRect(origin: .zero, size: canvas))
            ctx.restoreState()
            return
        }
        ctx.saveState()
        defer { ctx.restoreState() }
        ctx.setAlpha(opacity)
        ctx.beginTransparencyLayer()
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1)
        if abs(item.rotation) > 1e-6 {
            let bounds = item.annotation.bounds(shaper: canvasType.shaper)
            ctx.translateBy(x: bounds.midX, y: bounds.midY)
            ctx.rotate(by: item.rotation)
            ctx.translateBy(x: -bounds.midX, y: -bounds.midY)
        }
        AnnotationRenderer.draw(item.annotation, base: canvasType.placeholder, in: ctx)
        ctx.endTransparencyLayer()
    }
}
