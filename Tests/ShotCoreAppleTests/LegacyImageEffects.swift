import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
@testable import ShotCore
import ShotCoreApple

// The renderer's Core Image filters as they were before #651 put them behind `ImageEffects`, copied from
// `AnnotationRenderer` unchanged but for being instance methods, for `EffectsGoldenTests`. They go once #651 has landed.

struct LegacyImageEffects: ImageEffects {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    /// Blurs masks as plain coverage values, without converting them through a colour space.
    private static let maskContext = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    // From `softSpotlight`.
    func blurredMask(_ shape: CGImage, radius: CGFloat) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: shape.width, height: shape.height)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = CIImage(cgImage: shape).clampedToExtent()
        filter.radius = Float(radius)
        guard let output = filter.outputImage?.cropped(to: extent),
              let blurred = Self.maskContext.createCGImage(output, from: extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        else {
            return nil
        }
        return blurred
    }

    /// All of `image` blurred by `radius`, its edges kept sharp-cornered rather than fading out.
    func blurred(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = CIImage(cgImage: image).clampedToExtent()
        filter.radius = Float(radius)
        guard let output = filter.outputImage?.cropped(to: extent) else {
            return nil
        }
        return Self.ciContext.createCGImage(output, from: extent)
    }

    // From `outlineMask`.
    func grownMask(of image: CGImage, radius: CGFloat) -> CGImage? {
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
              let mask = Self.maskContext.createCGImage(output, from: grown, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        else {
            return nil
        }
        return mask
    }

    // From `pixelate`, after its region.
    func pixelated(_ base: CGImage, region: CGRect, blockSize scale: CGFloat) -> CGImage? {
        let filter = CIFilter.pixellate()
        filter.inputImage = CIImage(cgImage: base).clampedToExtent()
        filter.center = region.origin
        filter.scale = Float(scale)
        guard let output = filter.outputImage?.cropped(to: region) else {
            return nil
        }
        return Self.ciContext.createCGImage(output, from: region)
    }

    // From `blur`, after its region.
    func blurredBlocks(_ base: CGImage, region: CGRect, radius: CGFloat) -> CGImage? {
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
        return Self.ciContext.createCGImage(output, from: region)
    }
}

/// A `CGCanvas` whose effects are the legacy ones, so the renderer draws through the old filters and everything else as now.
final class LegacyEffectsCanvas: Canvas {
    let inner: CGCanvas

    init(_ inner: CGCanvas) {
        self.inner = inner
    }

    convenience init?(width: Int, height: Int, format: CanvasFormat) {
        guard let inner = CGCanvas(width: width, height: height, format: format) else {
            return nil
        }
        self.init(inner)
    }

    static var effects: any ImageEffects { LegacyImageEffects() }

    func saveState() { inner.saveState() }
    func restoreState() { inner.restoreState() }
    func translateBy(x: CGFloat, y: CGFloat) { inner.translateBy(x: x, y: y) }
    func scaleBy(x: CGFloat, y: CGFloat) { inner.scaleBy(x: x, y: y) }
    var pixelScale: CGFloat { inner.pixelScale }
    var clipBounds: CGRect { inner.clipBounds }
    func clip(to rect: CGRect) { inner.clip(to: rect) }
    func clip(to path: CanvasPath) { inner.clip(to: path) }
    func setFillColor(_ color: RGBA) { inner.setFillColor(color) }
    func setStrokeColor(_ color: RGBA) { inner.setStrokeColor(color) }
    func setLineWidth(_ width: CGFloat) { inner.setLineWidth(width) }
    func setLineCap(_ cap: CanvasLineCap) { inner.setLineCap(cap) }
    func setLineJoin(_ join: CanvasLineJoin) { inner.setLineJoin(join) }
    func setBlendMode(_ mode: CanvasBlendMode) { inner.setBlendMode(mode) }
    func setAlpha(_ alpha: CGFloat) { inner.setAlpha(alpha) }
    func setInterpolation(_ quality: CanvasInterpolation) { inner.setInterpolation(quality) }
    func setShadow(offset: CGSize, blur: CGFloat, color: RGBA) { inner.setShadow(offset: offset, blur: blur, color: color) }
    func beginTransparencyLayer() { inner.beginTransparencyLayer() }
    func endTransparencyLayer() { inner.endTransparencyLayer() }
    func fill(_ rect: CGRect) { inner.fill(rect) }
    func fill(_ path: CanvasPath) { inner.fill(path) }
    func stroke(_ path: CanvasPath) { inner.stroke(path) }
    func draw(_ image: CGImage, in rect: CGRect) { inner.draw(image, in: rect) }
    func clip(to rect: CGRect, mask: CGImage) { inner.clip(to: rect, mask: mask) }
    func makeImage() -> CGImage? { inner.makeImage() }
    func draw(_ line: CTLine, at position: CGPoint, outlined: Bool) { inner.draw(line, at: position, outlined: outlined) }
}
