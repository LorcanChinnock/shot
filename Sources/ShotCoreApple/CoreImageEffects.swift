import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// The Mac's `ImageEffects`: Core Image filters, run on two contexts every render shares.
public final class CoreImageEffects: ImageEffects {
    public static let shared = CoreImageEffects()

    private let context = CIContext(options: [.cacheIntermediates: false])
    /// Blurs masks as plain coverage values, without converting them through a colour space.
    private let maskContext = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    private init() {}

    public func blurred(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = CIImage(cgImage: image).clampedToExtent()
        filter.radius = Float(radius)
        guard let output = filter.outputImage?.cropped(to: extent) else {
            return nil
        }
        return context.createCGImage(output, from: extent)
    }

    public func blurredMask(_ mask: CGImage, radius: CGFloat) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: mask.width, height: mask.height)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = CIImage(cgImage: mask).clampedToExtent()
        filter.radius = Float(radius)
        guard let output = filter.outputImage?.cropped(to: extent) else {
            return nil
        }
        return maskContext.createCGImage(output, from: extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
    }

    public func grownMask(of image: CGImage, radius: CGFloat) -> CGImage? {
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
        guard let output = grey.outputImage?.cropped(to: grown) else {
            return nil
        }
        return maskContext.createCGImage(output, from: grown, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
    }

    public func pixelated(_ image: CGImage, region: CGRect, blockSize: CGFloat) -> CGImage? {
        let filter = CIFilter.pixellate()
        filter.inputImage = CIImage(cgImage: image).clampedToExtent()
        filter.center = region.origin
        filter.scale = Float(blockSize)
        guard let output = filter.outputImage?.cropped(to: region) else {
            return nil
        }
        return context.createCGImage(output, from: region)
    }

    public func blurredBlocks(_ image: CGImage, region: CGRect, radius: CGFloat) -> CGImage? {
        let blocks = CIFilter.pixellate()
        blocks.inputImage = CIImage(cgImage: image).clampedToExtent()
        blocks.center = region.origin
        blocks.scale = Float(radius)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = blocks.outputImage
        filter.radius = Float(radius)
        guard let output = filter.outputImage?.cropped(to: region) else {
            return nil
        }
        return context.createCGImage(output, from: region)
    }
}
