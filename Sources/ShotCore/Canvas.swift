#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(CoreText)
import CoreText
#endif
import Foundation
#if canImport(CoreGraphics)
import Synchronization
#endif

/// A surface the annotation renderer draws on, so it can draw with whichever library the platform has. A new canvas has
/// its origin at the bottom left, one unit to a pixel. Each call works as its namesake on a `CGContext` does: state set
/// between `saveState` and `restoreState` is undone by the restore, and paths, rects and points are in the current
/// coordinates. A canvas is drawn on by one thread at a time, but its type can be handed to any thread to make one.
public protocol Canvas: AnyObject, SendableMetatype {
    /// A blank canvas `width` by `height` pixels, clear where it has alpha and black where it doesn't; `nil` if it can't
    /// be made.
    init?(width: Int, height: Int, format: CanvasFormat)
    /// The filters for the images this type of canvas makes and draws.
    static var effects: any ImageEffects { get }

    func saveState()
    func restoreState()
    func translateBy(x: CGFloat, y: CGFloat)
    func scaleBy(x: CGFloat, y: CGFloat)
    /// Pixels per unit along the current x axis.
    var pixelScale: CGFloat { get }
    /// The smallest rect holding the clip, in the current coordinates; infinite or null when nothing clips.
    var clipBounds: CGRect { get }
    func clip(to rect: CGRect)
    func clip(to path: CanvasPath)

    func setFillColor(_ color: RGBA)
    func setStrokeColor(_ color: RGBA)
    func setLineWidth(_ width: CGFloat)
    func setLineCap(_ cap: CanvasLineCap)
    func setLineJoin(_ join: CanvasLineJoin)
    func setBlendMode(_ mode: CanvasBlendMode)
    func setAlpha(_ alpha: CGFloat)
    func setInterpolation(_ quality: CanvasInterpolation)
    /// Gives what's drawn next a shadow, its offset and blur in the current coordinates, so it looks the same at any scale.
    func setShadow(offset: CGSize, blur: CGFloat, color: RGBA)

    /// Draws what follows into a layer of its own, composited as one with the alpha, blend mode and shadow set now.
    func beginTransparencyLayer()
    func endTransparencyLayer()

    func fill(_ rect: CGRect)
    /// Fills by the nonzero winding rule.
    func fill(_ path: CanvasPath)
    func stroke(_ path: CanvasPath)
    /// What's drawn so far, as a `Bitmap` in sRGB; `nil` if it can't be read.
    func makeBitmap() -> Bitmap?

    #if canImport(CoreGraphics)
    // Images stay CGImage until the annotations hold `Bitmap`s, so a capture keeps its own colour space, such as Display P3.

    /// Draws `image` into `rect` with its first row at the rect's max y, as `CGContext.draw` does.
    func draw(_ image: CGImage, in rect: CGRect)
    /// Clips to `rect`, letting through as much as the greyscale `mask` stretched over it is light.
    func clip(to rect: CGRect, mask: CGImage)
    func makeImage() -> CGImage?
    #endif

    #if canImport(CoreText)
    // Text goes through a protocol of its own in #650.

    /// Draws `line` upright in a top-left-origin canvas, its baseline starting at `position`. `outlined` strokes each glyph
    /// with the stroke colour and line width instead of filling it.
    func draw(_ line: CTLine, at position: CGPoint, outlined: Bool)
    #endif
}

#if canImport(CoreGraphics)
private let placeholders = Mutex<[ObjectIdentifier: CGImage]>([:])

extension Canvas {
    /// A clear 1×1 image, the base the renderer is given when it draws annotations that don't read what's under them.
    /// Each canvas type makes one and keeps it, so caches that compare bases by identity keep hitting.
    static var placeholder: CGImage {
        placeholders.withLock { made in
            if let known = made[ObjectIdentifier(self)] {
                return known
            }
            let image = Self(width: 1, height: 1, format: .sRGB)!.makeImage()!
            made[ObjectIdentifier(self)] = image
            return image
        }
    }
}
#endif

/// The pixels a new canvas holds.
public enum CanvasFormat {
    /// 8-bit grey, without alpha.
    case grey
    /// 8-bit premultiplied RGBA in sRGB.
    case sRGB
    #if canImport(CoreGraphics)
    /// 8-bit premultiplied RGBA in `image`'s colour space, or sRGB if it has none, so drawing it loses nothing.
    case matching(CGImage)
    #endif
}

public enum CanvasLineCap: Sendable {
    case butt, round, square
}

public enum CanvasLineJoin: Sendable {
    case miter, round, bevel
}

public enum CanvasBlendMode: Sendable {
    case normal, multiply, darken, sourceAtop
}

/// How smoothly an image drawn at another size is resampled.
public enum CanvasInterpolation: Sendable {
    case medium, high
}
