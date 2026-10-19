import CoreGraphics
import CoreText

/// The Mac's `Canvas`: a `CGContext`, drawn into as the renderer drew into one before it had a canvas.
public final class CGCanvas: Canvas {
    public let context: CGContext

    public init(_ context: CGContext) {
        self.context = context
    }

    public convenience init?(width: Int, height: Int, format: CanvasFormat) {
        let space: CGColorSpace, alpha: CGImageAlphaInfo
        switch format {
        case .grey:
            (space, alpha) = (CGColorSpaceCreateDeviceGray(), .none)
        case .sRGB:
            (space, alpha) = (CGColorSpace(name: CGColorSpace.sRGB)!, .premultipliedLast)
        case let .matching(image):
            (space, alpha) = (image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, .premultipliedLast)
        }
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue
        ) else {
            return nil
        }
        self.init(context)
    }

    public static var effects: any ImageEffects { CoreImageEffects.shared }
    public static var shaper: any TextShaper { CoreTextShaper() }

    public func saveState() { context.saveGState() }
    public func restoreState() { context.restoreGState() }
    public func translateBy(x: CGFloat, y: CGFloat) { context.translateBy(x: x, y: y) }
    public func scaleBy(x: CGFloat, y: CGFloat) { context.scaleBy(x: x, y: y) }

    public var pixelScale: CGFloat {
        let ctm = context.ctm
        return hypot(ctm.a, ctm.b)
    }

    public var clipBounds: CGRect { context.boundingBoxOfClipPath }

    public func clip(to rect: CGRect) { context.clip(to: rect) }

    public func clip(to path: CanvasPath) {
        context.addPath(path.cgPath)
        context.clip()
    }

    public func setFillColor(_ color: RGBA) { context.setFillColor(color.cgColor) }
    public func setStrokeColor(_ color: RGBA) { context.setStrokeColor(color.cgColor) }
    public func setLineWidth(_ width: CGFloat) { context.setLineWidth(width) }

    public func setLineCap(_ cap: CanvasLineCap) {
        switch cap {
        case .butt: context.setLineCap(.butt)
        case .round: context.setLineCap(.round)
        case .square: context.setLineCap(.square)
        }
    }

    public func setLineJoin(_ join: CanvasLineJoin) {
        switch join {
        case .miter: context.setLineJoin(.miter)
        case .round: context.setLineJoin(.round)
        case .bevel: context.setLineJoin(.bevel)
        }
    }

    public func setBlendMode(_ mode: CanvasBlendMode) {
        switch mode {
        case .normal: context.setBlendMode(.normal)
        case .multiply: context.setBlendMode(.multiply)
        case .darken: context.setBlendMode(.darken)
        case .sourceAtop: context.setBlendMode(.sourceAtop)
        }
    }

    public func setAlpha(_ alpha: CGFloat) { context.setAlpha(alpha) }

    public func setInterpolation(_ quality: CanvasInterpolation) {
        switch quality {
        case .medium: context.interpolationQuality = .medium
        case .high: context.interpolationQuality = .high
        }
    }

    public func setShadow(offset: CGSize, blur: CGFloat, color: RGBA) {
        // Core Graphics shadows ignore the CTM, so map the offset and blur through it.
        let ctm = context.ctm
        context.setShadow(offset: offset.applying(ctm), blur: blur * hypot(ctm.a, ctm.b), color: color.cgColor)
    }

    public func beginTransparencyLayer() { context.beginTransparencyLayer(auxiliaryInfo: nil) }
    public func endTransparencyLayer() { context.endTransparencyLayer() }

    public func fill(_ rect: CGRect) { context.fill(rect) }

    public func fill(_ path: CanvasPath) {
        context.addPath(path.cgPath)
        context.fillPath()
    }

    public func stroke(_ path: CanvasPath) {
        context.addPath(path.cgPath)
        context.strokePath()
    }

    public func draw(_ image: CGImage, in rect: CGRect) { context.draw(image, in: rect) }
    public func clip(to rect: CGRect, mask: CGImage) { context.clip(to: rect, mask: mask) }
    public func makeImage() -> CGImage? { context.makeImage() }
    public func makeBitmap() -> Bitmap? { context.makeImage().flatMap { Bitmap($0) } }

    public func draw(_ line: any ShapedLine, at position: CGPoint, outlined: Bool) {
        guard let line = line as? CoreTextLine else {
            preconditionFailure("CGCanvas draws only the lines CoreTextShaper makes")
        }
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = position
        if outlined {
            context.setTextDrawingMode(.stroke)
        }
        CTLineDraw(line.line, context)
        if outlined {
            context.setTextDrawingMode(.fill)
        }
    }
}
