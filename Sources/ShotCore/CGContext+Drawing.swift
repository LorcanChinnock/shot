import CoreGraphics
import CoreText

/// The pixels a new bitmap context holds.
public enum BitmapFormat {
    /// 8-bit grey, without alpha.
    case grey
    /// 8-bit premultiplied RGBA in sRGB.
    case sRGB
    /// 8-bit premultiplied RGBA in `image`'s colour space, or sRGB if it has none, so drawing it loses nothing.
    case matching(CGImage)
}

/// A clear 1×1 image, the base the renderer is given when it draws annotations that don't read what's under them. It's
/// made once, so caches that compare bases by identity keep hitting.
let placeholderImage: CGImage = CGContext.bitmap(width: 1, height: 1, format: .sRGB)!.makeImage()!

extension CGContext {
    /// A blank bitmap context `width` by `height` pixels, its origin at the bottom left, one unit to a pixel: clear where
    /// it has alpha and black where it doesn't; `nil` if it can't be made.
    public static func bitmap(width: Int, height: Int, format: BitmapFormat) -> CGContext? {
        let space: CGColorSpace, alpha: CGImageAlphaInfo
        switch format {
        case .grey:
            (space, alpha) = (CGColorSpaceCreateDeviceGray(), .none)
        case .sRGB:
            (space, alpha) = (CGColorSpace(name: CGColorSpace.sRGB)!, .premultipliedLast)
        case let .matching(image):
            (space, alpha) = (image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, .premultipliedLast)
        }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue)
    }

    /// Pixels per unit along the current x axis.
    var pixelScale: CGFloat {
        hypot(ctm.a, ctm.b)
    }

    /// Gives what's drawn next a shadow, its offset and blur in the current coordinates, so it looks the same at any
    /// scale. Core Graphics shadows ignore the CTM, so the offset and blur are mapped through it.
    func setShadow(offset: CGSize, blur: CGFloat, color: RGBA) {
        setShadow(offset: offset.applying(ctm), blur: blur * pixelScale, color: color.cgColor)
    }

    /// Fills `path` by the nonzero winding rule.
    func fill(_ path: CGPath) {
        addPath(path)
        fillPath()
    }

    func clip(to path: CGPath) {
        addPath(path)
        clip()
    }

    /// Fills `path` by the nonzero winding rule.
    func fill(_ path: CanvasPath) {
        addPath(path.cgPath)
        fillPath()
    }

    func stroke(_ path: CanvasPath) {
        addPath(path.cgPath)
        strokePath()
    }

    func clip(to path: CanvasPath) {
        addPath(path.cgPath)
        clip()
    }

    /// Draws `line` upright in a top-left-origin context, its baseline starting at `position`. `outlined` strokes each
    /// glyph with the stroke colour and line width instead of filling it.
    func draw(_ line: CoreTextLine, at position: CGPoint, outlined: Bool) {
        textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        textPosition = position
        if outlined {
            setTextDrawingMode(.stroke)
        }
        CTLineDraw(line.line, self)
        if outlined {
            setTextDrawingMode(.fill)
        }
    }

    /// What's drawn so far, as a `Bitmap` in sRGB; `nil` if it can't be read.
    func makeBitmap() -> Bitmap? {
        makeImage().flatMap { Bitmap($0) }
    }
}
