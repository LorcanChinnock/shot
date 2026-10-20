import CoreGraphics
import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

// Bitmap+Effects, Linux's image effects, compared with CoreImageEffects on the same pictures. Each test prints how far
// apart they are; the limits are what was measured, with a little room.

/// 120 × 90, opaque: a gradient with sharp-edged dark and light bars on it, like text and windows in a screenshot.
private func scene() throws -> Bitmap {
    var pixels = Data()
    for y in 0..<90 {
        for x in 0..<120 {
            let bar = (20..<26).contains(y % 30) && (10..<110).contains(x) && x % 9 < 6
            let window = (40..<70).contains(x) && (35..<60).contains(y)
            let rgb: [Double] = bar ? [0.05, 0.05, 0.1] : window ? [1, 1, 1] : [Double(x) / 119, Double(y) / 89, 0.6]
            pixels += rgb.map { UInt8(($0 * 255).rounded()) } + [255]
        }
    }
    return try #require(Bitmap(width: 120, height: 90, pixels: pixels))
}

/// A `width` × `height` greyscale picture from `level(x, y)`, top row first: for Core Image a grey `CGImage`, and for
/// the portable effects a `Bitmap` with the level in red, green and blue.
private func greyPicture(width: Int, height: Int, _ level: (Int, Int) -> UInt8) throws -> (CGImage, Bitmap) {
    var levels = [UInt8]()
    var pixels = Data()
    for y in 0..<height {
        for x in 0..<width {
            let l = level(x, y)
            levels.append(l)
            pixels += [l, l, l, 255]
        }
    }
    let provider = try #require(CGDataProvider(data: Data(levels) as CFData))
    let image = try #require(CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    ))
    return (image, try #require(Bitmap(width: width, height: height, pixels: pixels)))
}

/// A greyscale image's levels, top row first, read without converting them through a colour space.
private func levels(of image: CGImage) throws -> [UInt8] {
    var levels = [UInt8](repeating: 0, count: image.width * image.height)
    let ctx = try #require(CGContext(
        data: &levels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
    ))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return levels
}

/// How many of `a`'s and `b`'s values differ by more than `tolerance`, as a share, and the most any differs by.
private func difference(_ a: [UInt8], _ b: [UInt8], tolerance: Int, _ label: String) -> (share: Double, worst: Int) {
    let gaps = zip(a, b).map { abs(Int($0) - Int($1)) }
    let share = Double(gaps.filter { $0 > tolerance }.count) / Double(max(gaps.count, 1))
    let worst = gaps.max() ?? 0
    print("\(label): \(String(format: "%.2f", share * 100))% of values differ by more than \(tolerance), the most by \(worst)")
    return (share, worst)
}

private func bytes(_ image: CGImage?) throws -> [UInt8] {
    [UInt8](try #require(image.flatMap { Bitmap($0) }).pixels)
}

// A blur that's the gaussian itself, below 3, rounds a little differently at the steepest edges; one of three box blurs
// above it matches as closely. Core Image's fits a gaussian of 0.98 times the radius, so this one hides a little more.
@Test(arguments: [1.0, 2, 3, 6, 16, 40])
func theBlurIsCoreImagesGaussian(radius: CGFloat) throws {
    let scene = try scene()
    let core = try bytes(CoreImageEffects.shared.blurred(try #require(scene.cgImage), radius: radius))
    let portable = [UInt8](scene.blurred(radius: radius).pixels)
    let (share, worst) = difference(core, portable, tolerance: 4, "blur \(radius)")
    #expect(share <= 0.01 && worst <= 8)
}

@Test(arguments: [1.0, 2, 5, 12, 30])
func theMaskBlurIsCoreImagesGaussianOfTheLevels(radius: CGFloat) throws {
    // A hard-edged rectangle, white on black, as a soft spotlight's mask is before it's blurred.
    let (image, bitmap) = try greyPicture(width: 80, height: 60) { x, y in (20..<60).contains(x) && (15..<45).contains(y) ? 255 : 0 }
    let core = try levels(of: try #require(CoreImageEffects.shared.blurredMask(image, radius: radius)))
    let portable = bitmap.blurredMask(radius: radius).pixels.enumerated().filter { $0.offset % 4 == 0 }.map(\.element)
    let (share, worst) = difference(core, portable, tolerance: 4, "mask blur \(radius)")
    #expect(share == 0 && worst <= 4)
}

// Up to 4, Core Image grows by a disc of the radius rounded down, as Bitmap does. Past it, it grows by a few smaller
// steps, whose shape is a little squarer than a disc, so its outline is up to a pixel wider on the diagonals.
@Test(arguments: [(0.5, 0), (1, 0), (2.5, 0), (4, 0), (7, 0.02), (12, 0.04)] as [(CGFloat, Double)])
func theGrownMaskIsCoreImagesMorphologyMaximum(radius: CGFloat, differing: Double) throws {
    // A ring and a dot, with a half-clear edge, so the disc's shape and the levels both show.
    var pixels = Data()
    for y in 0..<40 {
        for x in 0..<50 {
            let d = hypot(Double(x) - 20, Double(y) - 20)
            let alpha: UInt8 = (x == 42 && y == 8) ? 255 : d < 12 && d > 8 ? 255 : d < 13 && d > 7 ? 128 : 0
            pixels += [alpha / 2, alpha / 4, alpha, alpha]
        }
    }
    let bitmap = try #require(Bitmap(width: 50, height: 40, pixels: pixels))
    let image = try #require(bitmap.cgImage)
    let core = try levels(of: try #require(CoreImageEffects.shared.grownMask(of: image, radius: radius)))
    let grown = bitmap.grownMask(radius: radius)
    #expect(grown.width * grown.height == core.count)
    let portable = grown.pixels.enumerated().filter { $0.offset % 4 == 0 }.map(\.element)
    let (share, _) = difference(core, portable, tolerance: 0, "grown mask \(radius)")
    #expect(share <= differing)
}

private let regions: [(CGRect, CGFloat)] = [
    (CGRect(x: 10, y: 8, width: 90, height: 60), 6),
    (CGRect(x: 0, y: 0, width: 120, height: 90), 10),
    (CGRect(x: 33, y: 21, width: 41, height: 37), 7.5),
    // Reaching past the image's edges, where the edge pixels repeat.
    (CGRect(x: -7, y: 80, width: 30, height: 20), 9),
]

@Test(arguments: regions)
func pixelateIsCoreImagesPixellate(region: CGRect, blockSize: CGFloat) throws {
    let scene = try scene()
    let core = try bytes(CoreImageEffects.shared.pixelated(try #require(scene.cgImage), region: region, blockSize: blockSize))
    let portable = [UInt8](try #require(scene.pixelated(region: region, blockSize: blockSize)).pixels)
    #expect(core.count == portable.count)
    let (share, _) = difference(core, portable, tolerance: 1, "pixelate \(blockSize)")
    #expect(share == 0)
}

@Test(arguments: [(CGRect(x: 10, y: 8, width: 90, height: 60), 6.0), (CGRect(x: 33, y: 21, width: 41, height: 37), 12)] as [(CGRect, CGFloat)])
func blurredBlocksAreCoreImagesBlurredPixellate(region: CGRect, radius: CGFloat) throws {
    let scene = try scene()
    let core = try bytes(CoreImageEffects.shared.blurredBlocks(try #require(scene.cgImage), region: region, radius: radius))
    let portable = [UInt8](try #require(scene.blurredBlocks(region: region, radius: radius)).pixels)
    #expect(core.count == portable.count)
    let (share, worst) = difference(core, portable, tolerance: 4, "blurred blocks \(radius)")
    #expect(share <= 0.01 && worst <= 8)
}
