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
        drawUpright(doc.base, in: doc.fullRect, ctx: ctx)
        // The spotlights share one dim, at the lowest one's layer: what's under it dims with the image, what's over it doesn't.
        let dimIndex = doc.annotations.firstIndex { if case .spotlight = $0.kind { true } else { false } }
        for (index, annotation) in doc.annotations.enumerated() {
            if index == dimIndex, let dim, let style = doc.spotlightStyle {
                drawSpotlightDim(dim, style: style, softSpotlights: doc.softSpotlights, base: doc.base, below: doc.annotations[..<index], in: ctx)
            }
            draw(annotation, base: doc.base, over: doc.annotations[..<index], in: ctx)
        }
        if dim != nil {
            ctx.endTransparencyLayer()
        }
        ctx.restoreGState()
        cache.sweep()
    }

    /// Darkens or blurs `dim`, the image outside every spotlight, faded where `softSpotlights` light it.
    private static func drawSpotlightDim(
        _ dim: CGPath, style: SpotlightStyle, softSpotlights: [(rect: CGRect, style: SpotlightStyle, cornerRadius: CGFloat?)], base: CGImage, below: ArraySlice<Annotation>, in ctx: CGContext
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
            let backdrop = Backdrop(base, images: below, around: dim.boundingBoxOfPath, outset: 0)
            let radius = style.blurRadius(forImageLength: longerSide(of: base))
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

    /// Draws in a top-left-origin context. `below` are the annotations drawn before it, whose placed images
    /// a pixelate or blur covers along with the screenshot.
    public static func draw(_ annotation: Annotation, base: CGImage, over below: ArraySlice<Annotation> = [], in ctx: CGContext) {
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
            let backdrop = Backdrop(base, images: below, around: rect, outset: scale)
            let pixelated = cache.value(for: .pixelate(backdrop, rect: rect, scale: scale)) {
                let source = backdrop.draw()
                return pixelate(source.image, rect: rect.offsetBy(dx: -source.origin.x, dy: -source.origin.y), scale: scale).map { ($0, rect.integral) }
            }
            if let pixelated {
                drawUpright(pixelated.image, in: pixelated.frame, ctx: ctx)
            }
        case let .blur(rect, _):
            let radius = redactionSize(annotation, base: base)
            let backdrop = Backdrop(base, images: below, around: rect, outset: radius * 4)
            let blurred = cache.value(for: .blur(backdrop, rect: rect, radius: radius)) {
                let source = backdrop.draw()
                return blur(source.image, rect: rect.offsetBy(dx: -source.origin.x, dy: -source.origin.y), radius: radius).map { ($0, rect.integral) }
            }
            if let blurred {
                drawUpright(blurred.image, in: blurred.frame, ctx: ctx)
            }
        case let .image(image, rect):
            drawUpright(image.image, in: pixelAligned(rect), ctx: ctx)
        case let .text(string, origin, fontSize):
            let layout = TextLayout(string: string, fontSize: fontSize, color: annotation.color)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            for (index, line) in layout.lines.enumerated() {
                let x = origin.x + annotation.alignment.offset(of: line, in: layout.size.width)
                ctx.textPosition = CGPoint(x: x, y: origin.y + layout.ascent + CGFloat(index) * layout.lineHeight)
                CTLineDraw(line, ctx)
            }
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
