import Foundation

/// The filters the annotation renderer runs over images, so it can filter with whichever library the platform has. Each
/// canvas type names the effects that go with its images, as `Canvas.effects`. Regions are in an image's pixels with the
/// origin at the bottom left, as a new canvas has it. Edges are clamped: pixels past an image's edge repeat the nearest
/// edge pixel, so a blur doesn't darken toward the edge. Safe to use from any thread.
public protocol ImageEffects: Sendable {
    /// All of `image` given a gaussian blur of `radius` pixels.
    func blurred(_ image: PlatformImage, radius: CGFloat) -> PlatformImage?
    /// A greyscale mask given a gaussian blur of `radius` pixels, its levels blurred as plain coverage values rather than
    /// through a colour space.
    func blurredMask(_ mask: PlatformImage, radius: CGFloat) -> PlatformImage?
    /// The shape of `image`'s opaque pixels grown by `radius` pixels, white on black, as a greyscale mask reaching `radius`
    /// rounded up past each edge of the image.
    func grownMask(of image: PlatformImage, radius: CGFloat) -> PlatformImage?
    /// `region` of `image` in square blocks `blockSize` pixels wide, lined up with the region's origin, each the colour at
    /// its middle.
    func pixelated(_ image: PlatformImage, region: CGRect, blockSize: CGFloat) -> PlatformImage?
    /// `region` of `image` in blocks `radius` pixels wide, as `pixelated` makes them, then given a gaussian blur of
    /// `radius` that reaches across the region's edge into the blocks beyond it.
    func blurredBlocks(_ image: PlatformImage, region: CGRect, radius: CGFloat) -> PlatformImage?
}
