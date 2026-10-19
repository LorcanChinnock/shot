#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public enum AnnotationRenderer {
    /// What the canvas's effects made on the last render, so redrawing while editing doesn't filter what hasn't changed again.
    static let cache = RenderCache()

    /// Lets go of the images kept for redrawing, so a closed editor's capture doesn't stay in memory.
    public static func releaseCaches() {
        cache.removeAll()
        EditorDocument.forgetCaptureTransparency()
    }

    /// Draws the document into a bottom-left-origin canvas of size `doc.exportSize`.
    public static func render(_ doc: EditorDocument, into ctx: any Canvas) {
        renderLayers(doc, into: ctx, shadowBackground: doc.background)
        cache.sweep()
    }

    /// `render` without sweeping the cache, so a backdrop can be drawn with it partway through a render.
    /// `shadowBackground` tints the shadows, which a backdrop drawn without the background still needs.
    /// `canvas` draws that region of the image's own layers instead, ignoring the frame crop, as a backdrop needs.
    static func renderLayers(_ doc: EditorDocument, into ctx: any Canvas, shadowBackground: RGBA?, canvas exact: CGRect? = nil) {
        var doc = doc
        doc.annotations.removeAll(where: \.isHidden)
        if exact != nil {
            doc.resetCrop()
        }
        let canvas = exact ?? doc.canvasRect
        ctx.saveState()
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -canvas.minX, y: -canvas.minY)
        ctx.clip(to: canvas)
        if let background = doc.background {
            ctx.setFillColor(background)
            ctx.fill(canvas)
        }
        let dim = SpotlightDim(doc, on: ctx)
        // The dim keeps alpha, so it's composited in a layer of its own to look the same over the editor's backdrop as in the export.
        if dim != nil {
            ctx.beginTransparencyLayer()
        }
        let look = CaptureLook(cornerRadius: doc.captureCornerRadius, style: doc.captureStyle, background: shadowBackground)
        // The screenshot's shadow, border and corners go around what the frame crop leaves of it.
        if !doc.captureRect.isEmpty {
            drawImage(doc.capturePicture, in: doc.captureRect, cornerRadius: doc.clampedCaptureCornerRadius, style: doc.captureStyle, shadowBackground: shadowBackground, ctx: ctx)
        }
        // The frame crop hides the annotations outside it, even where the screenshot's shadow widens the canvas past it.
        ctx.saveState()
        if let crop = doc.visibleCrop {
            ctx.clip(to: crop)
        }
        // Each layer acts on everything under it and nothing over it. The spotlights share one dim, at the lowest one's layer.
        let dimIndex = doc.annotations.firstIndex { if case .spotlight = $0.kind { true } else { false } }
        for (index, annotation) in doc.annotations.enumerated() {
            if index == dimIndex, let dim, let style = doc.spotlightStyle {
                // Only what's within the dim's reach of the canvas shows in it.
                let reach = annotation.backdropReach(base: doc.base) ?? 0
                let read = canvas.insetBy(dx: -reach, dy: -reach)
                drawSpotlightDim(dim, style: style, softSpotlights: doc.softSpotlights, base: doc.base, below: doc.annotations[..<index], look: look, reading: read, in: ctx)
            }
            draw(annotation, base: doc.base, over: doc.annotations[..<index], look: look, in: ctx)
        }
        ctx.restoreState()
        if dim != nil {
            ctx.endTransparencyLayer()
        }
        ctx.restoreState()
    }

    /// Darkens or blurs `dim`, everything under the lowest spotlight outside every spotlight, faded where `softSpotlights` light it.
    private static func drawSpotlightDim(
        _ dim: SpotlightDim, style: SpotlightStyle, softSpotlights: [(rect: CGRect, style: SpotlightStyle, cornerRadius: CGFloat?)],
        base: PlatformImage, below: ArraySlice<Annotation>, look: CaptureLook, reading read: CGRect, in ctx: any Canvas
    ) {
        ctx.saveState()
        defer { ctx.restoreState() }
        let area = dim.bounds.integral
        let spotlights = softSpotlights.map { SoftSpotlight(rect: $0.rect, style: $0.style, cornerRadius: $0.cornerRadius) }
        if !spotlights.isEmpty, let mask = softSpotlightMask(spotlights, in: area, canvasType: type(of: ctx)) {
            ctx.clip(to: area, mask: mask)
        }
        switch style.effect {
        case .darken:
            // Source-atop darkens what's painted and leaves transparent pixels, such as a window's shadow, clear.
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(RGBA(0, 0, 0, style.dimAlpha))
            dim.fill(ctx)
        case .blur:
            let radius = style.blurRadius(forImageLength: longerSide(of: base))
            let area = dim.bounds.intersection(read)
            guard !area.isEmpty else {
                return
            }
            let backdrop = Backdrop(base, below: below, around: area, outset: 0, look: look, shaper: type(of: ctx).shaper)
            let blurred = cache.value(for: .dimBlur(backdrop, radius: radius)) {
                let source = backdrop.draw(canvasType: type(of: ctx))
                // Its edges are kept sharp-cornered rather than fading out.
                return type(of: ctx).effects.blurred(source.image, radius: radius).map { ($0, CGRect(origin: source.origin, size: CGSize(width: $0.width, height: $0.height))) }
            }
            guard let blurred else {
                return
            }
            dim.clip(ctx)
            drawUpright(blurred.image, in: blurred.frame, ctx: ctx)
        }
    }

    /// A greyscale mask of `area`: white where the dim shows, black inside the spotlights, with each spotlight's edge
    /// blurred by its soft-edge radius. Having only blurry edges, it's drawn at a lower resolution the softer they are.
    private static func softSpotlightMask(_ spotlights: [SoftSpotlight], in area: CGRect, canvasType: any Canvas.Type) -> PlatformImage? {
        cache.value(for: .softSpotlightMask(spotlights, area: area)) {
            drawSoftSpotlightMask(spotlights, in: area, canvasType: canvasType).map { ($0, area) }
        }?.image
    }

    private static func drawSoftSpotlightMask(_ spotlights: [SoftSpotlight], in area: CGRect, canvasType: any Canvas.Type) -> PlatformImage? {
        let sharpest = spotlights.map { $0.style.softEdgeRadius(in: $0.rect) }.min() ?? 0
        let scale = min(1, 8 / sharpest)
        let size = CGSize(width: ceil(area.width * scale), height: ceil(area.height * scale))
        guard let ctx = canvasType.init(width: Int(size.width), height: Int(size.height), format: .grey) else {
            return nil
        }
        ctx.setFillColor(RGBA(1, 1, 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.scaleBy(x: size.width / area.width, y: size.height / area.height)
        ctx.translateBy(x: -area.minX, y: -area.minY)
        ctx.setInterpolation(.high)
        // Darken keeps the lower of the two, so overlapping spotlights light their union.
        ctx.setBlendMode(.darken)
        for spotlight in spotlights {
            if let lit = cache.value(for: .softSpotlight(spotlight), make: { softSpotlight(spotlight.rect, style: spotlight.style, cornerRadius: spotlight.cornerRadius, canvasType: canvasType) }) {
                ctx.draw(lit.image, in: lit.frame)
            }
        }
        return ctx.makeImage()
    }

    /// One spotlight's shape, black on white, blurred by its soft-edge radius and drawn at a resolution to match;
    /// `frame` is where it goes, at full size.
    private static func softSpotlight(_ rect: CGRect, style: SpotlightStyle, cornerRadius: CGFloat?, canvasType: any Canvas.Type) -> (image: PlatformImage, frame: CGRect)? {
        let radius = style.softEdgeRadius(in: rect)
        let frame = rect.insetBy(dx: -3 * radius, dy: -3 * radius).integral
        let scale = min(1, 8 / radius)
        let extent = CGRect(x: 0, y: 0, width: ceil(frame.width * scale), height: ceil(frame.height * scale))
        guard let ctx = canvasType.init(width: Int(extent.width), height: Int(extent.height), format: .grey) else {
            return nil
        }
        ctx.setFillColor(RGBA(1, 1, 1))
        ctx.fill(extent)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -frame.minX, y: -frame.minY)
        ctx.setFillColor(RGBA(0, 0, 0))
        ctx.fill(style.shape.path(in: rect, cornerRadius: cornerRadius))
        guard let shape = ctx.makeImage() else {
            return nil
        }
        guard let blurred = canvasType.effects.blurredMask(shape, radius: radius * scale) else {
            return nil
        }
        return (blurred, CGRect(x: frame.minX, y: frame.minY, width: extent.width / scale, height: extent.height / scale))
    }

    /// The document drawn on a new `canvasType` canvas in the screenshot's colour space.
    public static func flatten(_ doc: EditorDocument, canvasType: any Canvas.Type) -> PlatformImage? {
        let size = doc.exportSize
        guard let ctx = canvasType.init(width: Int(size.width), height: Int(size.height), format: .matching(doc.base)) else {
            return nil
        }
        // A placed image of lower density than the screenshot is scaled up; the rest are drawn pixel for pixel.
        ctx.setInterpolation(.high)
        render(doc, into: ctx)
        return ctx.makeImage()
    }

    /// Draws in a top-left-origin canvas. `below` are the annotations drawn before it, which a pixelate or blur
    /// covers along with the screenshot. `background` is the canvas's, which tints a shadow.
    public static func draw(_ annotation: Annotation, base: PlatformImage, over below: ArraySlice<Annotation> = [], background: RGBA? = nil, in ctx: any Canvas) {
        draw(annotation, base: base, over: below, look: CaptureLook(background: background), in: ctx)
    }

    /// `look` is how the screenshot under it is drawn, which a pixelate or blur covers too. A mark or text with a shadow
    /// casts it first; a placed image draws its own.
    static func draw(_ annotation: Annotation, base: PlatformImage, over below: ArraySlice<Annotation>, look: CaptureLook, in ctx: any Canvas) {
        if let shadow = annotation.style.shadow, let kind = annotation.styleKind, kind != .image {
            let color = shadow.color(background: look.background, object: annotation.color)
            drawCachedShadow(shadow, color: color, of: annotation.bounds(shaper: type(of: ctx).shaper), area: annotation.paintedBounds(shaper: type(of: ctx).shaper), caster: .annotation(annotation), ctx: ctx) {
                drawPlain(annotation, base: base, over: below, look: look, in: $0)
            }
        }
        drawPlain(annotation, base: base, over: below, look: look, in: ctx)
    }

    /// Draws `annotation` without its shadow.
    private static func drawPlain(_ annotation: Annotation, base: PlatformImage, over below: ArraySlice<Annotation>, look: CaptureLook, in ctx: any Canvas) {
        let color = annotation.color
        let width = annotation.lineWidth
        ctx.saveState()
        defer { ctx.restoreState() }
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch annotation.kind {
        case let .arrow(from, to):
            let control = annotation.curve?.control
            let tangentFrom = control ?? from
            let length = hypot(to.x - from.x, to.y - from.y)
            let tangentLength = hypot(to.x - tangentFrom.x, to.y - tangentFrom.y)
            guard length > 0, tangentLength > 0 else {
                return
            }
            let head = min(max(12, width * 4), length)
            let ux = (to.x - tangentFrom.x) / tangentLength, uy = (to.y - tangentFrom.y) / tangentLength
            let base = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
            let half = head * 0.45
            var shaft = CanvasPath()
            shaft.move(to: from)
            if let control {
                shaft.addQuadCurve(to: base, control: control)
            } else {
                shaft.addLine(to: base)
            }
            ctx.stroke(shaft)
            var tip = CanvasPath()
            tip.move(to: to)
            tip.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
            tip.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
            tip.closeSubpath()
            ctx.fill(tip)
        case let .line(from, to):
            var line = CanvasPath()
            line.move(to: from)
            if let control = annotation.curve?.control {
                line.addQuadCurve(to: to, control: control)
            } else {
                line.addLine(to: to)
            }
            ctx.stroke(line)
        case let .shape(shape, rect):
            let path = shape.path(in: rect, cornerRadius: annotation.cornerRadius)
            if let fill = annotation.fill {
                ctx.setFillColor(fill)
                ctx.fill(path)
            }
            ctx.stroke(path)
        case let .highlight(rect):
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(RGBA(1, 0.92, 0.2))
            ctx.fill(rect)
        case .spotlight:
            // `render` draws every spotlight's dim at once.
            break
        case let .pixelate(rect, _):
            let scale = redactionSize(annotation, base: base)
            let backdrop = Backdrop(base, below: below, around: rect, outset: annotation.backdropReach(base: base) ?? 0, look: look, shaper: type(of: ctx).shaper)
            let pixelated = cache.value(for: .pixelate(backdrop, rect: rect, scale: scale)) {
                let source = backdrop.draw(canvasType: type(of: ctx))
                return pixelate(source.image, rect: rect.offsetBy(dx: -source.origin.x, dy: -source.origin.y), scale: scale, effects: type(of: ctx).effects).map { ($0, rect.integral) }
            }
            if let pixelated {
                drawUpright(pixelated.image, in: pixelated.frame, ctx: ctx)
            }
        case let .blur(rect, _):
            let radius = redactionSize(annotation, base: base)
            let backdrop = Backdrop(base, below: below, around: rect, outset: annotation.backdropReach(base: base) ?? 0, look: look, shaper: type(of: ctx).shaper)
            let blurred = cache.value(for: .blur(backdrop, rect: rect, radius: radius)) {
                let source = backdrop.draw(canvasType: type(of: ctx))
                return blur(source.image, rect: rect.offsetBy(dx: -source.origin.x, dy: -source.origin.y), radius: radius, effects: type(of: ctx).effects).map { ($0, rect.integral) }
            }
            if let blurred {
                drawUpright(blurred.image, in: blurred.frame, ctx: ctx)
            }
        case let .image(image, rect):
            drawImage(image.cropped(annotation.imageCrop), in: pixelAligned(rect), cornerRadius: annotation.imageCornerRadius, style: annotation.style, shadowBackground: look.background, ctx: ctx)
        case let .text(string, origin, fontSize):
            let layout = TextLayout(string: string, fontSize: fontSize, color: annotation.color, shaper: type(of: ctx).shaper)
            func drawLines(_ lines: [any ShapedLine], outlined: Bool = false) {
                for (index, line) in lines.enumerated() {
                    let x = origin.x + annotation.alignment.offset(of: line, in: layout.size.width)
                    ctx.draw(line, at: CGPoint(x: x, y: origin.y + layout.ascent + CGFloat(index) * layout.lineHeight), outlined: outlined)
                }
            }
            if let outline = annotation.style.border, outline.kind == .outline {
                // Each letter is stroked twice as wide as the outline in its colour, and the fill covers the inner half.
                ctx.saveState()
                ctx.setLineWidth(outline.width * 2)
                ctx.setStrokeColor(outline.paint)
                drawLines(TextLayout(string: string, fontSize: fontSize, color: outline.paint, shaper: type(of: ctx).shaper).lines, outlined: true)
                ctx.restoreState()
            }
            drawLines(layout.lines)
        case let .counter(number, center):
            let radius = annotation.counterRadius
            ctx.fill(CanvasPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)))
            let layout = TextLayout(string: "\(number)", fontSize: radius * 1.1, color: RGBA(1, 1, 1), shaper: type(of: ctx).shaper)
            guard let line = layout.lines.first else {
                return
            }
            ctx.draw(line, at: CGPoint(x: center.x - line.width / 2, y: center.y + (line.ascent - line.descent) / 2), outlined: false)
        case let .freehand(points):
            ctx.stroke(Freehand.path(through: points))
        case let .marker(points):
            ctx.setBlendMode(.multiply)
            ctx.setAlpha(0.6)
            ctx.setLineWidth(annotation.markerWidth)
            ctx.setLineCap(.butt)
            ctx.stroke(Freehand.path(through: points))
        case .note:
            guard let layout = annotation.noteLayout(shaper: type(of: ctx).shaper) else {
                return
            }
            ctx.saveState()
            ctx.setShadow(offset: CGSize(width: 0, height: layout.shadowOffset), blur: layout.shadowBlur, color: RGBA(0, 0, 0, 0.3))
            ctx.setFillColor(layout.fill)
            ctx.fill(CanvasPath(roundedRect: layout.frame, cornerRadius: layout.cornerRadius))
            ctx.restoreState()
            let text = layout.textRect
            for (index, line) in layout.lines.enumerated() {
                let x = text.minX + annotation.alignment.offset(of: line, in: text.width)
                ctx.draw(line, at: CGPoint(x: x, y: text.minY + layout.ascent + CGFloat(index) * layout.lineHeight), outlined: false)
            }
        }
    }

    /// Draws `image` right side up into `rect` of a top-left-origin canvas, its corners rounded by `cornerRadius`,
    /// with `style`'s shadow under it and border around it. A plain image is drawn as it is.
    static func drawImage(_ image: PlatformImage, in rect: CGRect, cornerRadius: CGFloat, style: ObjectStyle, shadowBackground: RGBA?, ctx: any Canvas) {
        let needsEdge = style.border?.kind == .hairline || style.shadow?.tint == .object
        let edge = needsEdge ? edgeColor(of: image, canvasType: type(of: ctx)) : nil
        // A solid border or outline goes under the image and casts the shadow with it; a hairline goes over its edge.
        func drawSilhouette(_ ctx: any Canvas) {
            if let border = style.border, border.castsShadow {
                drawBorder(border, around: image, in: rect, cornerRadius: cornerRadius, edge: edge, ctx: ctx)
            }
            ctx.saveState()
            if cornerRadius > 0 {
                ctx.clip(to: CanvasPath(roundedRect: rect, cornerRadius: cornerRadius))
            }
            drawUpright(image, in: rect, ctx: ctx)
            ctx.restoreState()
        }
        if let shadow = style.shadow {
            let color = shadow.color(background: shadowBackground, object: edge ?? RGBA(0, 0, 0))
            let caster = ShadowCaster.image(SampledImage(image: image), rect: rect, cornerRadius: cornerRadius, style: style)
            drawCachedShadow(shadow, color: color, of: rect, area: style.paintedRect(around: rect), caster: caster, ctx: ctx, silhouette: drawSilhouette)
        }
        drawSilhouette(ctx)
        if let border = style.border, !border.castsShadow {
            drawBorder(border, around: image, in: rect, cornerRadius: cornerRadius, edge: edge, ctx: ctx)
        }
    }

    /// Draws `border` around `image`, drawn in `rect` with its corners rounded by `cornerRadius`. `edge` is the average
    /// colour near the image's edge, which picks a hairline's.
    private static func drawBorder(_ border: Border, around image: PlatformImage, in rect: CGRect, cornerRadius: CGFloat, edge: RGBA?, ctx: any Canvas) {
        let width = border.width
        ctx.saveState()
        defer { ctx.restoreState() }
        switch border.kind {
        case .hairline, .solid:
            // Centred just outside the edge, its corners concentric with the image's, so it hugs them evenly. A solid one
            // reaches half a pixel under the image too, so no seam shows between them.
            let overlap: CGFloat = border.kind == .solid ? 0.5 : 0
            let stroke = width + overlap
            let inset = (width - overlap) / 2
            let radius = cornerRadius > 0 ? cornerRadius + inset : 0
            ctx.setStrokeColor(border.kind == .hairline ? Border.hairlineColor(edge: edge) : border.paint)
            ctx.setLineWidth(stroke)
            ctx.stroke(CanvasPath(roundedRect: rect.insetBy(dx: -inset, dy: -inset), cornerRadius: radius))
        case .outline:
            guard width > 0, rect.width > 0, rect.height > 0 else {
                return
            }
            // The mask is made at the image's own size, so the width is grown in its pixels.
            let scale = CGSize(width: rect.width / CGFloat(image.width), height: rect.height / CGFloat(image.height))
            guard let mask = outlineMask(of: image, radius: width / max(scale.width, scale.height), effects: type(of: ctx).effects) else {
                return
            }
            let frame = CGRect(
                x: rect.minX + mask.frame.minX * scale.width, y: rect.minY + mask.frame.minY * scale.height,
                width: mask.frame.width * scale.width, height: mask.frame.height * scale.height
            )
            // Upright, as `drawUpright` draws an image, since a mask is drawn like one.
            ctx.translateBy(x: 0, y: frame.maxY)
            ctx.scaleBy(x: 1, y: -1)
            let flipped = CGRect(x: frame.minX, y: 0, width: frame.width, height: frame.height)
            ctx.clip(to: flipped, mask: mask.image)
            ctx.setFillColor(border.paint)
            ctx.fill(flipped)
        }
    }

    /// The shape of `image`'s opaque pixels grown by `radius` of its pixels, white on black, made with `effects` and kept
    /// while the image is drawn. Its frame is where it goes in the image's pixels, reaching `radius` past each edge.
    private static func outlineMask(of image: PlatformImage, radius: CGFloat, effects: any ImageEffects) -> RenderCache.Value? {
        cache.value(for: .outlineMask(SampledImage(image: image), radius: radius)) {
            let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let grown = extent.insetBy(dx: -radius.rounded(.up), dy: -radius.rounded(.up))
            // The mask counts up from the bottom, but the grown frame is the same distance past every edge.
            return effects.grownMask(of: image, radius: radius).map { ($0, grown) }
        }
    }

    /// Draws the shadow `silhouette` casts from `rect`, which reaches no further than `area`. It's drawn into a bitmap of
    /// `area` at the canvas's resolution, but no finer than the image's pixels, and coarser the softer its sharpest layer,
    /// as a soft spotlight's mask is, since a blurry shadow has no detail to lose. It's kept while `caster` and the
    /// resolution stay the same, wherever the caster moves, so redrawing while editing or moving an annotation clip
    /// draws an image rather than blurring again, and a shadow that does change blurs only its own area, not the whole canvas.
    private static func drawCachedShadow(
        _ shadow: Shadow, color: RGBA, of rect: CGRect, area: CGRect, caster: ShadowCaster, ctx: any Canvas, silhouette: (any Canvas) -> Void
    ) {
        let sharpest = shadow.layers.map(\.blur).min() ?? 0
        let unit = min(1, ctx.pixelScale, sharpest > 0 ? 8 / sharpest : 1)
        let size = CGSize(width: (area.width * unit).rounded(.up), height: (area.height * unit).rounded(.up))
        guard size.width >= 1, size.height >= 1 else {
            return
        }
        // Kept relative to where the shadow starts, which is where it's drawn back.
        let cached = cache.value(for: .shadow(caster.relative(to: area.origin), color: color, unit: unit)) {
            guard let bitmap = type(of: ctx).init(width: Int(size.width), height: Int(size.height), format: .sRGB) else {
                return nil
            }
            bitmap.translateBy(x: 0, y: size.height)
            bitmap.scaleBy(x: unit, y: -unit)
            bitmap.translateBy(x: -area.minX, y: -area.minY)
            drawShadow(shadow, color: color, of: rect, ctx: bitmap) { silhouette(bitmap) }
            return bitmap.makeImage().map { ($0, CGRect(origin: .zero, size: CGSize(width: size.width / unit, height: size.height / unit))) }
        }
        if let cached {
            drawUpright(cached.image, in: cached.frame.offsetBy(dx: area.minX, dy: area.minY), ctx: ctx)
        }
    }

    /// Draws only the shadow `silhouette` casts from `rect`, one pass per layer of `shadow`. Each pass draws the silhouette
    /// well clear of what's shown, with the shadow offset back under it, so no copy of the object is left to show through it.
    private static func drawShadow(_ shadow: Shadow, color: RGBA, of rect: CGRect, ctx: any Canvas, silhouette: () -> Void) {
        let shown = ctx.clipBounds
        let clear = (shown.isNull || shown.isInfinite ? rect.width : max(shown.maxX - rect.minX, rect.width)) + shadow.reach.side * 2 + 1
        for layer in shadow.layers {
            ctx.saveState()
            ctx.setShadow(offset: CGSize(width: -clear, height: layer.offset), blur: layer.blur, color: RGBA(color.r, color.g, color.b, shadow.opacity))
            ctx.beginTransparencyLayer()
            ctx.translateBy(x: clear, y: 0)
            silhouette()
            ctx.endTransparencyLayer()
            ctx.restoreState()
        }
    }

    /// The average colour near `image`'s edge, each pixel weighed by its alpha; `nil` if it's clear all round.
    /// It's read from a small copy, kept while the image is drawn.
    static func edgeColor(of image: PlatformImage, canvasType: any Canvas.Type) -> RGBA? {
        let side = 16
        let sample = cache.value(for: .edgeSample(SampledImage(image: image))) {
            guard let ctx = canvasType.init(width: side, height: side, format: .sRGB) else {
                return nil
            }
            ctx.setInterpolation(.medium)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return ctx.makeImage().map { ($0, .zero) }
        }
        // Read back through a canvas of its own size, which copies it pixel for pixel.
        guard let sample, let ctx = canvasType.init(width: side, height: side, format: .sRGB) else {
            return nil
        }
        ctx.draw(sample.image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let bitmap = ctx.makeBitmap() else {
            return nil
        }
        let bytes = bitmap.pixels, bytesPerRow = bitmap.bytesPerRow
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        for y in 0..<side {
            for x in 0..<side where x < 2 || y < 2 || x >= side - 2 || y >= side - 2 {
                let offset = bytes.startIndex + y * bytesPerRow + x * 4
                // Premultiplied, so the sums weigh each pixel by its alpha.
                r += CGFloat(bytes[offset])
                g += CGFloat(bytes[offset + 1])
                b += CGFloat(bytes[offset + 2])
                a += CGFloat(bytes[offset + 3])
            }
        }
        guard a > 0 else {
            return nil
        }
        return RGBA(r / a, g / a, b / a)
    }

    /// `rect` on whole pixels, so an image dragged by a fraction of a pixel still exports pixel for pixel.
    static func pixelAligned(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
    }

    /// Draws `image` right side up into `rect` of a top-left-origin canvas.
    static func drawUpright(_ image: PlatformImage, in rect: CGRect, ctx: any Canvas) {
        ctx.saveState()
        ctx.translateBy(x: 0, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
        ctx.restoreState()
    }

    static func pixelate(_ base: PlatformImage, rect: CGRect, scale: CGFloat, effects: any ImageEffects) -> PlatformImage? {
        let region = CGRect(x: rect.minX, y: CGFloat(base.height) - rect.maxY, width: rect.width, height: rect.height).integral
        guard region.width >= 1, region.height >= 1 else {
            return nil
        }
        return effects.pixelated(base, region: region, blockSize: scale)
    }

    static func longerSide(of image: PlatformImage) -> CGFloat {
        CGFloat(max(image.width, image.height))
    }

    /// A pixelate's block size or a blur's radius in pixels of `base`.
    static func redactionSize(_ annotation: Annotation, base: PlatformImage) -> CGFloat {
        let length = longerSide(of: base)
        return Redaction.size(amount: annotation.redactionAmount(imageLength: length) ?? Redaction.defaultAmount, imageLength: length)
    }

    static func blur(_ base: PlatformImage, rect: CGRect, radius: CGFloat, effects: any ImageEffects) -> PlatformImage? {
        let region = CGRect(x: rect.minX, y: CGFloat(base.height) - rect.maxY, width: rect.width, height: rect.height).integral
        guard region.width >= 1, region.height >= 1 else {
            return nil
        }
        // A blur alone can be partly undone, so average the region into blocks first, which can't, then blur the blocks smooth.
        return effects.blurredBlocks(base, region: region, radius: radius)
    }
}

/// What the spotlights dim, as `EditorDocument` gives it: a path on a Mac, where the app reads it too, and elsewhere a mask,
/// since a `CanvasPath` can't be added to or subtracted from another.
enum SpotlightDim {
    #if canImport(CoreGraphics)
    case path(CGPath)
    #endif
    /// White where it dims, covering `frame`, its top row at the frame's min y.
    case mask(PlatformImage, frame: CGRect)

    /// `doc`'s dim, made for drawing on `ctx`; `nil` when there are no spotlights.
    init?(_ doc: EditorDocument, on ctx: any Canvas) {
        #if canImport(CoreGraphics)
        guard let path = doc.spotlightDimPath(shaper: type(of: ctx).shaper) else {
            return nil
        }
        self = .path(path)
        #else
        guard let (mask, frame) = doc.spotlightDimMask(shaper: type(of: ctx).shaper, canvasType: type(of: ctx), scale: ctx.pixelScale) else {
            return nil
        }
        self = .mask(mask, frame: frame)
        #endif
    }

    /// The smallest rect holding it.
    var bounds: CGRect {
        switch self {
        #if canImport(CoreGraphics)
        case let .path(path): path.boundingBoxOfPath
        #endif
        case let .mask(_, frame): frame
        }
    }

    /// Fills it in a top-left-origin canvas with the fill colour, alpha and blend mode set.
    func fill(_ ctx: any Canvas) {
        switch self {
        #if canImport(CoreGraphics)
        case let .path(path):
            ctx.fill(CanvasPath(path))
        #endif
        case let .mask(_, frame):
            ctx.saveState()
            clip(ctx)
            ctx.fill(frame)
            ctx.restoreState()
        }
    }

    /// Clips a top-left-origin canvas to it.
    func clip(_ ctx: any Canvas) {
        switch self {
        #if canImport(CoreGraphics)
        case let .path(path):
            ctx.clip(to: CanvasPath(path))
        #endif
        case let .mask(mask, frame):
            // Upright, as `drawUpright` draws an image, since a mask is drawn like one.
            ctx.translateBy(x: 0, y: frame.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.clip(to: CGRect(x: frame.minX, y: 0, width: frame.width, height: frame.height), mask: mask)
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: 0, y: -frame.maxY)
        }
    }
}
