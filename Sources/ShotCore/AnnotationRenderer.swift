import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText

public enum AnnotationRenderer {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    /// How dark a spotlight makes the image outside it.
    static let spotlightDim: CGFloat = 0.5

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
            if index == dimIndex, let dim {
                ctx.saveGState()
                // Source-atop darkens what's painted and leaves transparent pixels, such as a window's shadow, clear.
                ctx.setBlendMode(.sourceAtop)
                ctx.setFillColor(CGColor(gray: 0, alpha: spotlightDim))
                ctx.addPath(dim)
                ctx.fillPath()
                ctx.restoreGState()
            }
            draw(annotation, base: doc.base, over: doc.annotations[..<index], in: ctx)
        }
        if dim != nil {
            ctx.endTransparencyLayer()
        }
        ctx.restoreGState()
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
            let length = hypot(to.x - from.x, to.y - from.y)
            guard length > 0 else {
                return
            }
            let head = min(max(12, width * 4), length)
            let ux = (to.x - from.x) / length, uy = (to.y - from.y) / length
            let base = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
            let half = head * 0.45
            ctx.move(to: from)
            ctx.addLine(to: base)
            ctx.strokePath()
            ctx.move(to: to)
            ctx.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
            ctx.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
            ctx.closePath()
            ctx.fillPath()
        case let .line(from, to):
            ctx.move(to: from)
            ctx.addLine(to: to)
            ctx.strokePath()
        case let .rect(rect):
            ctx.stroke(rect)
        case let .ellipse(rect):
            ctx.strokeEllipse(in: rect)
        case let .highlight(rect):
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.92, blue: 0.2, alpha: 1))
            ctx.fill(rect)
        case .spotlight:
            // `render` draws every spotlight's dim at once.
            break
        case let .pixelate(rect):
            let source = backdrop(base, images: below, around: rect, outset: pixelScale(for: rect))
            if let pixelated = pixelate(source.image, rect: rect.offsetBy(dx: -source.origin.x, dy: -source.origin.y)) {
                drawUpright(pixelated, in: rect.integral, ctx: ctx)
            }
        case let .blur(rect):
            let source = backdrop(base, images: below, around: rect, outset: blurRadius(for: rect) * 4)
            if let blurred = blur(source.image, rect: rect.offsetBy(dx: -source.origin.x, dy: -source.origin.y)) {
                drawUpright(blurred, in: rect.integral, ctx: ctx)
            }
        case let .image(image, rect):
            drawUpright(image.image, in: pixelAligned(rect), ctx: ctx)
        case let .text(string, origin, fontSize):
            let layout = TextLayout(string: string, fontSize: fontSize, color: annotation.color)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            for (index, line) in layout.lines.enumerated() {
                ctx.textPosition = CGPoint(x: origin.x, y: origin.y + layout.ascent + CGFloat(index) * layout.lineHeight)
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
                ctx.textPosition = CGPoint(x: text.minX, y: text.minY + layout.ascent + CGFloat(index) * layout.lineHeight)
                CTLineDraw(line, ctx)
            }
        }
    }

    /// `rect` on whole pixels, so an image dragged by a fraction of a pixel still exports pixel for pixel.
    static func pixelAligned(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
    }

    /// What a pixelate or blur at `rect` hides: the screenshot, with the images placed under it drawn over it,
    /// as an image whose top-left pixel sits at `origin`. It reaches `outset` past `rect`, so the filter's
    /// edges sample what's really there. With no placed image under it, that's the screenshot itself.
    static func backdrop(_ base: CGImage, images below: ArraySlice<Annotation>, around rect: CGRect, outset: CGFloat) -> (image: CGImage, origin: CGPoint) {
        let area = rect.insetBy(dx: -outset, dy: -outset).integral
        let images = below.compactMap { annotation -> (CGImage, CGRect)? in
            guard case let .image(image, imageRect) = annotation.kind, imageRect.intersects(area) else {
                return nil
            }
            return (image.image, pixelAligned(imageRect))
        }
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
        drawUpright(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height), ctx: ctx)
        for (image, imageRect) in images {
            drawUpright(image, in: imageRect, ctx: ctx)
        }
        guard let image = ctx.makeImage() else {
            return (base, .zero)
        }
        return (image, area.origin)
    }

    /// Draws `image` right side up into `rect` of a top-left-origin context.
    static func drawUpright(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    static func pixelate(_ base: CGImage, rect: CGRect) -> CGImage? {
        let region = CGRect(x: rect.minX, y: CGFloat(base.height) - rect.maxY, width: rect.width, height: rect.height).integral
        guard region.width >= 1, region.height >= 1 else {
            return nil
        }
        let filter = CIFilter.pixellate()
        filter.inputImage = CIImage(cgImage: base).clampedToExtent()
        filter.center = region.origin
        filter.scale = Float(pixelScale(for: rect))
        guard let output = filter.outputImage?.cropped(to: region) else {
            return nil
        }
        return ciContext.createCGImage(output, from: region)
    }

    /// The pixelate's block size in image pixels.
    static func pixelScale(for rect: CGRect) -> CGFloat {
        max(8, rect.width / 20)
    }

    /// The blur's radius in image pixels: at least 12, so a line of text is gone, and more for bigger regions.
    static func blurRadius(for rect: CGRect) -> CGFloat {
        max(12, min(rect.width, rect.height) / 4)
    }

    static func blur(_ base: CGImage, rect: CGRect) -> CGImage? {
        let region = CGRect(x: rect.minX, y: CGFloat(base.height) - rect.maxY, width: rect.width, height: rect.height).integral
        guard region.width >= 1, region.height >= 1 else {
            return nil
        }
        let radius = Float(blurRadius(for: rect))
        // A blur alone can be partly undone, so average the region into blocks first, which can't, then blur the blocks smooth.
        let blocks = CIFilter.pixellate()
        blocks.inputImage = CIImage(cgImage: base).clampedToExtent()
        blocks.center = region.origin
        blocks.scale = radius
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = blocks.outputImage
        filter.radius = radius
        guard let output = filter.outputImage?.cropped(to: region) else {
            return nil
        }
        return ciContext.createCGImage(output, from: region)
    }
}
