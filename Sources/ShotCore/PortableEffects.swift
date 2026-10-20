import Foundation

#if !canImport(CoreGraphics)
/// The `ImageEffects` where there's no Core Image: `Bitmap`'s own filters, in plain Swift, which match Core Image's
/// output within a few levels.
public struct PortableEffects: ImageEffects {
    public init() {}

    public func blurred(_ image: PlatformImage, radius: CGFloat) -> PlatformImage? {
        BitmapImage(image.bitmap.blurred(radius: radius))
    }

    public func blurredMask(_ mask: PlatformImage, radius: CGFloat) -> PlatformImage? {
        BitmapImage(mask.bitmap.blurredMask(radius: radius))
    }

    public func grownMask(of image: PlatformImage, radius: CGFloat) -> PlatformImage? {
        BitmapImage(image.bitmap.grownMask(radius: radius))
    }

    public func pixelated(_ image: PlatformImage, region: CGRect, blockSize: CGFloat) -> PlatformImage? {
        image.bitmap.pixelated(region: region, blockSize: blockSize).map(BitmapImage.init)
    }

    public func blurredBlocks(_ image: PlatformImage, region: CGRect, radius: CGFloat) -> PlatformImage? {
        image.bitmap.blurredBlocks(region: region, radius: radius).map(BitmapImage.init)
    }
}
#endif
