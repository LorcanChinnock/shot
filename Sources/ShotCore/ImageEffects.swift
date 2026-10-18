#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// The filters the annotation renderer runs over images, so it can filter with whichever library the platform has. Each
/// canvas type names the effects that go with its images, as `Canvas.effects`. Regions are in an image's pixels with the
/// origin at the bottom left, as a new canvas has it. Edges are clamped: pixels past an image's edge repeat the nearest
/// edge pixel, so a blur doesn't darken toward the edge. Safe to use from any thread.
public protocol ImageEffects: Sendable {
    #if canImport(CoreGraphics)
    // Images stay CGImage while the canvas's do, until the annotations hold `Bitmap`s.

    /// All of `image` given a gaussian blur of `radius` pixels.
    func blurred(_ image: CGImage, radius: CGFloat) -> CGImage?
    /// A greyscale mask given a gaussian blur of `radius` pixels, its levels blurred as plain coverage values rather than
    /// through a colour space.
    func blurredMask(_ mask: CGImage, radius: CGFloat) -> CGImage?
    /// The shape of `image`'s opaque pixels grown by `radius` pixels, white on black, as a greyscale mask reaching `radius`
    /// rounded up past each edge of the image.
    func grownMask(of image: CGImage, radius: CGFloat) -> CGImage?
    /// `region` of `image` averaged into square blocks `blockSize` pixels wide, lined up with the region's origin.
    func pixelated(_ image: CGImage, region: CGRect, blockSize: CGFloat) -> CGImage?
    /// `region` of `image` averaged into blocks `radius` pixels wide, lined up with the region's origin, then given a
    /// gaussian blur of `radius` that reaches across the region's edge into the blocks beyond it.
    func blurredBlocks(_ image: CGImage, region: CGRect, radius: CGFloat) -> CGImage?
    #endif
}
