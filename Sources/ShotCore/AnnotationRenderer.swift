import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText

public enum AnnotationRenderer {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    /// Blurs masks as plain coverage values, without converting them through a colour space.
    private static let maskContext = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    /// What Core Image made on the last render, so redrawing while editing doesn't filter what hasn't changed again.
    static let cache = RenderCache()

    /// Draws the document into a bottom-left-origin context of size `doc.exportSize`.
    public static func render(_ doc: EditorDocument, into ctx: CGContext) {
        renderLayers(doc, into: ctx, shadowBackground: doc.background)
        cache.sweep()
    }

    /// `render` without sweeping the cache, so a backdrop can be drawn with it partway through a render.
    /// `shadowBackground` tints the shadows, which a backdrop drawn without the background still needs.
    static func renderLayers(_ doc: EditorDocument, into ctx: CGContext, shadowBackground: RGBA?) {
        var doc = doc
        doc.annotations.removeAll(where: \.isHidden)
        let canvas = doc.canvasRect
        ctx.saveGState()
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -canvas.minX, y: -canvas.minY)
        ctx.clip(to: canvas)
        if let background = doc.background {
            ctx.setFillColor(background.cgColor)
            ctx.fill(canvas)
        }
        let dim = doc.spotlightDimPath
        // The dim keeps alpha, so it's composited in a layer of its own to look the same over the editor's backdrop as in the export.
        if dim != nil {
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        let look = CaptureLook(cornerRadius: doc.captureCornerRadius, style: doc.captureStyle, background: shadowBackground)
        drawImage(doc.base, in: doc.fullRect, cornerRadius: doc.clampedCaptureCornerRadius, style: doc.captureStyle, shadowBackground: shadowBackground, ctx: ctx)
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
        if dim != nil {
            ctx.endTransparencyLayer()
        }
        ctx.restoreGState()
    }

    /// Darkens or blurs `dim`, everything under the lowest spotlight outside every spotlight, faded where `softSpotlights` light it.
    private static func drawSpotlightDim(
        _ dim: CGPath, style: SpotlightStyle, softSpotlights: [(rect: CGRect, style: SpotlightStyle, cornerRadius: CGFloat?)],
        base: CGImage, below: ArraySlice<Annotation>, look: CaptureLook, reading read: CGRect, in ctx: CGContext
    ) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let area = dim.boundingBoxOfPath.integral
        let spotlights = softSpotlights.map { SoftSpotlight(rect: $0.rect, style: $0.style, cornerRadius: $0.cornerRadius) }
        if !spotlights.isEmpty, let mask = softSpotlightMask(spotlights, in: area) {
            ctx.clip(to: area, mask: mask)
        }
        switch style.effect {
        case .darken:
            // Source-atop darkens what's painted and leaves transparent pixels, such as a window's shadow, clear.
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(CGColor(gray: 0, alpha: style.dimAlpha))
            ctx.addPath(dim)
            ctx.fillPath()
        case .blur:
            let radius = style.blurRadius(forImageLength: longerSide(of: base))
            let area = dim.boundingBoxOfPath.intersection(read)
            guard !area.isEmpty else {
                return
            }
            let backdrop = Backdrop(base, below: below, around: area, outset: 0, look: look)
            let blurred = cache.value(for: .dimBlur(backdrop, radius: radius)) {
                let source = backdrop.draw()
                return blurredWhole(source.image, radius: radius).map { ($0, CGRect(origin: source.origin, size: CGSize(width: $0.width, height: $0.height))) }
            }
            guard let blurred else {
                return
            }
            ctx.addPath(dim)
            ctx.clip()
            drawUpright(blurred.image, in: blurred.frame, ctx: ctx)
        }
    }

    /// A greyscale mask of `area`: white where the dim shows, black inside the spotlights, with each spotlight's edge
    /// blurred by its soft-edge radius. Having only blurry edges, it's drawn at a lower resolution the softer they are.
    private static func softSpotlightMask(_ spotlights: [SoftSpotlight], in area: CGRect) -> CGImage? {
        cache.value(for: .softSpotlightMask(spotlights, area: area)) {
            drawSoftSpotlightMask(spotlights, in: area).map { ($0, area) }
        }?.image
    }

    private static func drawSoftSpotlightMask(_ spotlights: [SoftSpotlight], in area: CGRect) -> CGImage? {
        let sharpest = spotlights.map { $0.style.softEdgeRadius(in: $0.rect) }.min() ?? 0
        let scale = min(1, 8 / sharpest)
        let size = CGSize(width: ceil(area.width * scale), height: ceil(area.height * scale))
        guard let ctx = greyContext(size: size) else {
            return nil
        }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.scaleBy(x: size.width / area.width, y: size.height / area.height)
        ctx.translateBy(x: -area.minX, y: -area.minY)
        ctx.interpolationQuality = .high
        // Darken keeps the lower of the two, so overlapping spotlights light their union.
        ctx.setBlendMode(.darken)
        for spotlight in spotlights {
            if let lit = cache.value(for: .softSpotlight(spotlight), make: { softSpotlight(spotlight.rect, style: spotlight.style, cornerRadius: spotlight.cornerRadius) }) {
                ctx.draw(lit.image, in: lit.frame)
            }
        }
        return ctx.makeImage()
    }

    /// One spotlight's shape, black on white, blurred by its soft-edge radius and drawn at a resolution to match;
    /// `frame` is where it goes, at full size.
    private static func softSpotlight(_ rect: CGRect, style: SpotlightStyle, cornerRadius: CGFloat?) -> (image: CGImage, frame: CGRect)? {
        let radius = style.softEdgeRadius(in: rect)
        let frame = rect.insetBy(dx: -3 * radius, dy: -3 * radius).integral
        let scale = min(1, 8 / radius)
        let extent = CGRect(x: 0, y: 0, width: ceil(frame.width * scale), height: ceil(frame.height * scale))
        guard let ctx = greyContext(size: extent.size) else {
            return nil
        }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(extent)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -frame.minX, y: -frame.minY)
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.addPath(style.shape.path(in: rect, cornerRadius: cornerRadius))
        ctx.fillPath()
        guard let shape = ctx.makeImage() else {
            return nil
        }
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = CIImage(cgImage: shape).clampedToExtent()
        filter.radius = Float(radius * scale)
        guard let output = filter.outputImage?.cropped(to: extent),
              let blurred = maskContext.createCGImage(output, from: extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        else {
            return nil
        }
        return (blurred, CGRect(x: frame.minX, y: frame.minY, width: extent.width / scale, height: extent.height / scale))
    }

    private static func greyContext(size: CGSize) -> CGContext? {
        CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
    }

    /// All of `image` blurred by `radius`, its edges kept sharp-cornered rather than fading out.
    static func blurredWhole(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = CIImage(cgImage: image).clampedToExtent()
        filter.radius = Float(radius)
        guard let output = filter.outputImage?.cropped(to: extent) else {
            return nil
        }
        return ciContext.createCGImage(output, from: extent)
    }

    public static func flatten(_ doc: EditorDocument) -> CGImage? {
        let size = doc.exportSize
        guard let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: doc.base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        // A placed image of lower density than the screenshot is scaled up; the rest are drawn pixel for pixel.
        ctx.interpolationQuality = .high
        render(doc, into: ctx)
        return ctx.makeImage()
    }

    /// Draws in a top-left-origin context. `below` are the annotations drawn before it, which a pixelate or blur
    /// covers along with the screenshot. `background` is the canvas's, which tints a shadow.
    public static func draw(_ annotation: Annotation, base: CGImage, over below: ArraySlice<Annotation> = [], background: RGBA? = nil, in ctx: CGContext) {
        draw(annotation, base: base, over: below, look: CaptureLook(background: background), in: ctx)
    }

    /// `look` is how the screenshot under it is drawn, which a pixelate or blur covers too. A mark or text with a shadow
    /// casts it first; a placed image draws its own.
    static func draw(_ annotation: Annotation, base: CGImage, over below: ArraySlice<Annotation>, look: CaptureLook, in ctx: CGContext) {
        if let shadow = annotation.style.shadow, let kind = annotation.styleKind, kind != .image {
            let color = shadow.color(background: look.background, object: annotation.color)
            drawCachedShadow(shadow, color: color, of: annotation.bounds, area: annotation.paintedBounds, caster: .annotation(annotation), ctx: ctx) {
                drawPlain(annotation, base: base, over: below, look: look, in: $0)
            }
        }
        drawPlain(annotation, base: base, over: below, look: look, in: ctx)
    }

    /// Draws `annotation` without its shadow.
    private static func drawPlain(_ annotation: Annotation, base: CGImage, over below: ArraySlice<Annotation>, look: CaptureLook, in ctx: CGContext) {
        let color = annotation.color.cgColor
        let width = annotation.lineWidth
        ctx.saveGState()
        defer { ctx.restoreGState() }
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
            ctx.move(to: from)
            if let control {
                ctx.addQuadCurve(to: base, control: control)
            } else {
                ctx.addLine(to: base)
            }
            ctx.strokePath()
            ctx.move(to: to)
            ctx.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
            ctx.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
            ctx.closePath()
            ctx.fillPath()
        case let .line(from, to):
            ctx.move(to: from)
            if let control = annotation.curve?.control {
                ctx.addQuadCurve(to: to, control: control)
            } else {
                ctx.addLine(to: to)
            }
            ctx.strokePath()
        case let .shape(shape, rect):
            let path = shape.path(in: rect, cornerRadius: annotation.cornerRadius)
            if let fill = annotation.fill {
                ctx.setFillColor(fill.cgColor)
                ctx.addPath(path)
                ctx.fillPath()
            }
            ctx.addPath(path)
            ctx.strokePath()
        case let .highlight(rect):
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.92, blue: 0.2, alpha: 1))
            ctx.fill(rect)
        case .spotlight:
            // `render` draws every spotlight's dim at once.
            break
        case let .pixelate(rect, _):
            let scale = redactionSize(annotation, base: base)
            let backdrop = Backdrop(base, below: below, around: rect, outset: annotation.backdropReach(base: base) ?? 0, look: look)
            let pixelated = cache.value(for: .pixelate(backdrop, rect: rect, scale: scale)) {
                let source = backdrop.draw()
                return pixelate(source.image, rect: rect.offsetBy(dx: -source.origin.x, dy: -source.origin.y), scale: scale).map { ($0, rect.integral) }
            }
            if let pixelated {
                drawUpright(pixelated.image, in: pixelated.frame, ctx: ctx)
            }
        case let .blur(rect, _):
            let radius = redactionSize(annotation, base: base)
            let backdrop = Backdrop(base, below: below, around: rect, outset: annotation.backdropReach(base: base) ?? 0, look: look)
            let blurred = cache.value(for: .blur(backdrop, rect: rect, radius: radius)) {
                let source = backdrop.draw()
                return blur(source.image, rect: rect.offsetBy(dx: -source.origin.x, dy: -source.origin.y), radius: radius).map { ($0, rect.integral) }
            }
            if let blurred {
                drawUpright(blurred.image, in: blurred.frame, ctx: ctx)
            }
        case let .image(image, rect):
            drawImage(image.image, in: pixelAligned(rect), cornerRadius: annotation.imageCornerRadius, style: annotation.style, shadowBackground: look.background, ctx: ctx)
        case let .text(string, origin, fontSize):
            let layout = TextLayout(string: string, fontSize: fontSize, color: annotation.color)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            func drawLines(_ lines: [CTLine]) {
                for (index, line) in lines.enumerated() {
                    let x = origin.x + annotation.alignment.offset(of: line, in: layout.size.width)
                    ctx.textPosition = CGPoint(x: x, y: origin.y + layout.ascent + CGFloat(index) * layout.lineHeight)
                    CTLineDraw(line, ctx)
                }
            }
            if let outline = annotation.style.border, outline.kind == .outline {
                // Each letter is stroked twice as wide as the outline in its colour, and the fill covers the inner half.
                ctx.saveGState()
                ctx.setTextDrawingMode(.stroke)
                ctx.setLineWidth(outline.width * 2)
                ctx.setStrokeColor(outline.paint.cgColor)
                drawLines(TextLayout(string: string, fontSize: fontSize, color: outline.paint).lines)
                ctx.restoreGState()
            }
            drawLines(layout.lines)
        case let .counter(number, center):
            let radius = annotation.counterRadius
            ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            let layout = TextLayout(string: "\(number)", fontSize: radius * 1.1, color: RGBA(1, 1, 1))
            guard let line = layout.lines.first else {
                return
            }
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = CGPoint(x: center.x - lineWidth / 2, y: center.y + (ascent - descent) / 2)
            CTLineDraw(line, ctx)
        case let .freehand(points):
            ctx.addPath(Freehand.path(through: points))
            ctx.strokePath()
        case let .marker(points):
            ctx.setBlendMode(.multiply)
            ctx.setAlpha(0.6)
            ctx.setLineWidth(annotation.markerWidth)
            ctx.setLineCap(.butt)
            ctx.addPath(Freehand.path(through: points))
            ctx.strokePath()
        case .note:
            guard let layout = annotation.noteLayout else {
                return
            }
            // Shadows ignore the CTM, so map the offset and blur through it to look the same at any zoom.
            let ctm = ctx.ctm
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: layout.shadowOffset).applying(ctm), blur: layout.shadowBlur * hypot(ctm.a, ctm.b), color: CGColor(gray: 0, alpha: 0.3))
            ctx.setFillColor(layout.fill.cgColor)
            ctx.addPath(CGPath(roundedRect: layout.frame, cornerWidth: layout.cornerRadius, cornerHeight: layout.cornerRadius, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
            let text = layout.textRect
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            for (index, line) in layout.lines.enumerated() {
                let x = text.minX + annotation.alignment.offset(of: line, in: text.width)
                ctx.textPosition = CGPoint(x: x, y: text.minY + layout.ascent + CGFloat(index) * layout.lineHeight)
                CTLineDraw(line, ctx)
            }
        }
    }

    /// Draws `image` right side up into `rect` of a top-left-origin context, its corners rounded by `cornerRadius`,
    /// with `style`'s shadow under it and border around it. A plain image is drawn as it is.
    static func drawImage(_ image: CGImage, in rect: CGRect, cornerRadius: CGFloat, style: ObjectStyle, shadowBackground: RGBA?, ctx: CGContext) {
        let needsEdge = style.border?.kind == .hairline || style.shadow?.tint == .object
        let edge = needsEdge ? edgeColor(of: image) : nil
        // A solid border or outline goes under the image and casts the shadow with it; a hairline goes over its edge.
        func drawSilhouette(_ ctx: CGContext) {
            if let border = style.border, border.castsShadow {
                drawBorder(border, around: image, in: rect, cornerRadius: cornerRadius, edge: edge, ctx: ctx)
            }
            ctx.saveGState()
            if cornerRadius > 0 {
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
                ctx.clip()
            }
            drawUpright(image, in: rect, ctx: ctx)
            ctx.restoreGState()
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
    private static func drawBorder(_ border: Border, around image: CGImage, in rect: CGRect, cornerRadius: CGFloat, edge: RGBA?, ctx: CGContext) {
        let width = border.width
        ctx.saveGState()
        defer { ctx.restoreGState() }
        switch border.kind {
        case .hairline, .solid:
            // Centred just outside the edge, its corners concentric with the image's, so it hugs them evenly. A solid one
            // reaches half a pixel under the image too, so no seam shows between them.
            let overlap: CGFloat = border.kind == .solid ? 0.5 : 0
            let stroke = width + overlap
            let inset = (width - overlap) / 2
            let radius = cornerRadius > 0 ? cornerRadius + inset : 0
            ctx.setStrokeColor(border.kind == .hairline ? Border.hairlineColor(edge: edge).cgColor : border.paint.cgColor)
            ctx.setLineWidth(stroke)
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: -inset, dy: -inset), cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.strokePath()
        case .outline:
            guard width > 0, rect.width > 0, rect.height > 0 else {
                return
            }
            // The mask is made at the image's own size, so the width is grown in its pixels.
            let scale = CGSize(width: rect.width / CGFloat(image.width), height: rect.height / CGFloat(image.height))
            guard let mask = outlineMask(of: image, radius: width / max(scale.width, scale.height)) else {
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
            ctx.setFillColor(border.paint.cgColor)
            ctx.fill(flipped)
        }
    }

    /// The shape of `image`'s opaque pixels grown by `radius` of its pixels, white on black, made with Core Image and kept
    /// while the image is drawn. Its frame is where it goes in the image's pixels, reaching `radius` past each edge.
    private static func outlineMask(of image: CGImage, radius: CGFloat) -> RenderCache.Value? {
        cache.value(for: .outlineMask(SampledImage(image: image), radius: radius)) {
            let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let grown = extent.insetBy(dx: -radius.rounded(.up), dy: -radius.rounded(.up))
            let dilate = CIFilter.morphologyMaximum()
            dilate.inputImage = CIImage(cgImage: image)
            dilate.radius = Float(radius)
            // Grey from the grown alpha, over opaque black.
            let grey = CIFilter.colorMatrix()
            grey.inputImage = dilate.outputImage
            grey.rVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            grey.gVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            grey.bVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            grey.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            grey.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            guard let output = grey.outputImage?.cropped(to: grown),
                  let mask = maskContext.createCGImage(output, from: grown, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
            else {
                return nil
            }
            // Core Image counts up from the bottom, but the grown frame is the same distance past every edge.
            return (mask, grown)
        }
    }

    /// Draws the shadow `silhouette` casts from `rect`, which reaches no further than `area`. It's drawn into a bitmap of
    /// `area` at the context's resolution, but no finer than the image's pixels, and coarser the softer its sharpest layer,
    /// as a soft spotlight's mask is, since a blurry shadow has no detail to lose. It's kept while `caster` and the
    /// resolution stay the same, so redrawing while editing draws an image rather than blurring again, and a shadow that
    /// does change blurs only its own area, not the whole canvas.
    private static func drawCachedShadow(
        _ shadow: Shadow, color: RGBA, of rect: CGRect, area: CGRect, caster: ShadowCaster, ctx: CGContext, silhouette: (CGContext) -> Void
    ) {
        let ctm = ctx.ctm
        let sharpest = shadow.layers.map(\.blur).min() ?? 0
        let unit = min(1, hypot(ctm.a, ctm.b), sharpest > 0 ? 8 / sharpest : 1)
        let area = area.integral
        let size = CGSize(width: (area.width * unit).rounded(.up), height: (area.height * unit).rounded(.up))
        guard size.width >= 1, size.height >= 1 else {
            return
        }
        let cached = cache.value(for: .shadow(caster, color: color, unit: unit)) {
            guard let bitmap = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }
            bitmap.translateBy(x: 0, y: size.height)
            bitmap.scaleBy(x: unit, y: -unit)
            bitmap.translateBy(x: -area.minX, y: -area.minY)
            drawShadow(shadow, color: color, of: rect, ctx: bitmap) { silhouette(bitmap) }
            return bitmap.makeImage().map { ($0, CGRect(origin: area.origin, size: CGSize(width: size.width / unit, height: size.height / unit))) }
        }
        if let cached {
            drawUpright(cached.image, in: cached.frame, ctx: ctx)
        }
    }

    /// Draws only the shadow `silhouette` casts from `rect`, one pass per layer of `shadow`. Each pass draws the silhouette
    /// well clear of what's shown, with the shadow offset back under it, so no copy of the object is left to show through it.
    private static func drawShadow(_ shadow: Shadow, color: RGBA, of rect: CGRect, ctx: CGContext, silhouette: () -> Void) {
        // Shadows ignore the CTM, so map the offset and blur through it to look the same at any zoom, as a note's do.
        let ctm = ctx.ctm
        let unit = hypot(ctm.a, ctm.b)
        let shown = ctx.boundingBoxOfClipPath
        let clear = (shown.isNull || shown.isInfinite ? rect.width : max(shown.maxX - rect.minX, rect.width)) + shadow.reach.side * 2 + 1
        for layer in shadow.layers {
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: -clear, height: layer.offset).applying(ctm),
                blur: layer.blur * unit,
                color: RGBA(color.r, color.g, color.b, shadow.opacity).cgColor
            )
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.translateBy(x: clear, y: 0)
            silhouette()
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }

    /// The average colour near `image`'s edge, each pixel weighed by its alpha; `nil` if it's clear all round.
    /// It's read from a small copy, kept while the image is drawn.
    static func edgeColor(of image: CGImage) -> RGBA? {
        let side = 16
        let sample = cache.value(for: .edgeSample(SampledImage(image: image))) {
            guard let ctx = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return ctx.makeImage().map { ($0, .zero) }
        }
        guard let sample, let data = sample.image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        let bytesPerRow = sample.image.bytesPerRow
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        for y in 0..<side {
            for x in 0..<side where x < 2 || y < 2 || x >= side - 2 || y >= side - 2 {
                let offset = y * bytesPerRow + x * 4
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

    /// Draws `image` right side up into `rect` of a top-left-origin context.
    static func drawUpright(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    static func pixelate(_ base: CGImage, rect: CGRect, scale: CGFloat) -> CGImage? {
        let region = CGRect(x: rect.minX, y: CGFloat(base.height) - rect.maxY, width: rect.width, height: rect.height).integral
        guard region.width >= 1, region.height >= 1 else {
            return nil
        }
        let filter = CIFilter.pixellate()
        filter.inputImage = CIImage(cgImage: base).clampedToExtent()
        filter.center = region.origin
        filter.scale = Float(scale)
        guard let output = filter.outputImage?.cropped(to: region) else {
            return nil
        }
        return ciContext.createCGImage(output, from: region)
    }

    static func longerSide(of image: CGImage) -> CGFloat {
        CGFloat(max(image.width, image.height))
    }

    /// A pixelate's block size or a blur's radius in pixels of `base`.
    static func redactionSize(_ annotation: Annotation, base: CGImage) -> CGFloat {
        let length = longerSide(of: base)
        return Redaction.size(amount: annotation.redactionAmount(imageLength: length) ?? Redaction.defaultAmount, imageLength: length)
    }

    static func blur(_ base: CGImage, rect: CGRect, radius: CGFloat) -> CGImage? {
        let region = CGRect(x: rect.minX, y: CGFloat(base.height) - rect.maxY, width: rect.width, height: rect.height).integral
        guard region.width >= 1, region.height >= 1 else {
            return nil
        }
        // A blur alone can be partly undone, so average the region into blocks first, which can't, then blur the blocks smooth.
        let blocks = CIFilter.pixellate()
        blocks.inputImage = CIImage(cgImage: base).clampedToExtent()
        blocks.center = region.origin
        blocks.scale = Float(radius)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = blocks.outputImage
        filter.radius = Float(radius)
        guard let output = filter.outputImage?.cropped(to: region) else {
            return nil
        }
        return ciContext.createCGImage(output, from: region)
    }
}
