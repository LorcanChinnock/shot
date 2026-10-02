import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText

public enum AnnotationRenderer {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Draws the document into a bottom-left-origin context of size `doc.exportSize`.
    public static func render(_ doc: EditorDocument, into ctx: CGContext) {
        let canvas = doc.canvasRect
        ctx.saveGState()
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -canvas.minX, y: -canvas.minY)
        ctx.clip(to: canvas)
        drawUpright(doc.base, in: doc.fullRect, ctx: ctx)
        for annotation in doc.annotations {
            draw(annotation, base: doc.base, in: ctx)
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
        render(doc, into: ctx)
        return ctx.makeImage()
    }

    /// Draws in a top-left-origin context.
    public static func draw(_ annotation: Annotation, base: CGImage, in ctx: CGContext) {
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
        case let .pixelate(rect):
            if let pixelated = pixelate(base, rect: rect) {
                drawUpright(pixelated, in: rect.integral, ctx: ctx)
            }
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
        }
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
        filter.scale = Float(max(8, rect.width / 20))
        guard let output = filter.outputImage?.cropped(to: region) else {
            return nil
        }
        return ciContext.createCGImage(output, from: region)
    }
}
