import CoreGraphics
import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

// Golden tests for #717: the diff, a downscale, a trim and the renderer's placeholder come out the same through `Canvas`
// and `Bitmap` as through the CGContexts ShotCore made before, `LegacyContexts`. Both go in #717's PR 2.

private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!, displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
/// How a screen capture comes: BGRA, premultiplied, little-endian.
private let captureLayout = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

/// A different colour and alpha in every pixel, clear within `margin` of each edge, so any change in how it's read or
/// resampled changes the bytes.
private func pattern(width: Int, height: Int, space: CGColorSpace = sRGB, layout: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue, margin: Int = 0) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: layout)!
    for x in margin..<width - margin {
        for y in margin..<height - margin {
            let alpha = CGFloat((x + 3 * y) % 11) / 10
            ctx.setFillColor(CGColor(colorSpace: space, components: [CGFloat(x % 17) / 16, CGFloat(y % 13) / 12, CGFloat((x * y) % 7) / 6, alpha])!)
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    return ctx.makeImage()!
}

/// A window with the macOS shadow around it, as a window capture with its shadow is before the trim.
private func shadowedWindow(space: CGColorSpace = displayP3) -> CGImage {
    let ctx = CGContext(data: nil, width: 301, height: 223, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: captureLayout)!
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: CGColor(gray: 0, alpha: 0.5))
    ctx.setFillColor(CGColor(colorSpace: space, components: [0.9, 0.4, 0.2, 1])!)
    ctx.fill(CGRect(x: 70, y: 81, width: 140, height: 90))
    return ctx.makeImage()!
}

/// Clear but for one barely visible pixel at (`x`, `y`), top-left origin.
private func faintPixel(x: Int, y: Int, space: CGColorSpace) -> CGImage {
    let ctx = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: captureLayout)!
    ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1.0 / 255])!)
    ctx.fill(CGRect(x: x, y: 48 - y - 1, width: 1, height: 1))
    return ctx.makeImage()!
}

/// White, with a black box `box` in it, top-left origin, in `space`.
private func whiteWithBox(width: Int, height: Int, box: CGRect?, space: CGColorSpace = sRGB) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    if let box {
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: box.minX, y: CGFloat(height) - box.maxY, width: box.width, height: box.height))
    }
    return ctx.makeImage()!
}

/// The pixels and the layout of `image`, which two images match in only if they're the same bitmap.
private func bitmap(_ image: CGImage?) -> (size: [Int], space: String?, bytes: Data)? {
    guard let image, let data = image.dataProvider?.data as Data? else {
        return nil
    }
    return ([image.width, image.height, image.bitsPerPixel, image.bytesPerRow], image.colorSpace?.name as String?, data)
}

private func expectSame(_ legacy: CGImage?, _ new: CGImage?, _ comment: Comment) throws {
    let old = try #require(bitmap(legacy), comment), new = try #require(bitmap(new), comment)
    #expect(old.size == new.size, comment)
    #expect(old.space == new.space, comment)
    #expect(old.bytes == new.bytes, comment)
}

@Test func theRenderersPlaceholderIsTheSameClearPixelOnACanvas() throws {
    try expectSame(LegacyContexts.placeholder, CGCanvas.placeholder, "placeholder")
    #expect(CGCanvas.placeholder === CGCanvas.placeholder)
}

@Test func aDownscaleDrawsTheSamePixelsOnACanvas() throws {
    let images = [
        ("sRGB", pattern(width: 241, height: 179)),
        ("Display P3", pattern(width: 240, height: 180, space: displayP3)),
        ("capture layout", pattern(width: 199, height: 101, space: displayP3, layout: captureLayout)),
        ("shadowed window", shadowedWindow()),
    ]
    for (name, image) in images {
        for scale in [1, 1.5, 2, 3] as [CGFloat] {
            try expectSame(LegacyContexts.downscaled(image, scale: scale), ImageCodec.downscaled(image, scale: scale), "\(name) at \(scale)×")
        }
    }
}

@Test func aTrimCropsTheSameEdgesThroughABitmap() throws {
    let images = [
        ("sRGB", pattern(width: 241, height: 179, margin: 9)),
        ("Display P3", pattern(width: 120, height: 90, space: displayP3, margin: 1)),
        ("capture layout", pattern(width: 99, height: 77, space: displayP3, layout: captureLayout, margin: 13)),
        ("no clear edges", pattern(width: 64, height: 40)),
        ("shadowed window", shadowedWindow()),
        ("shadowed sRGB window", shadowedWindow(space: sRGB)),
        ("faint pixel near the top left", faintPixel(x: 3, y: 2, space: sRGB)),
        ("faint pixel near the bottom right", faintPixel(x: 60, y: 45, space: displayP3)),
        ("all clear", pattern(width: 20, height: 20, margin: 10)),
    ]
    for (name, image) in images {
        try expectSame(LegacyContexts.trimTransparentEdges(image), ImageTrim.trimTransparentEdges(image), "\(name)")
    }
}

@Test func aDiffReadsAndDrawsTheSamePixelsOnCanvases() throws {
    let pairs = [
        ("one change", whiteWithBox(width: 200, height: 120, box: nil), whiteWithBox(width: 200, height: 120, box: CGRect(x: 40, y: 40, width: 30, height: 20))),
        ("a scaled up", whiteWithBox(width: 100, height: 60, box: nil), whiteWithBox(width: 201, height: 119, box: CGRect(x: 0, y: 90, width: 50, height: 29))),
        ("a scaled down", pattern(width: 300, height: 200), pattern(width: 150, height: 100, space: displayP3)),
        ("colour spaces", pattern(width: 160, height: 90, space: displayP3, layout: captureLayout), pattern(width: 160, height: 90, margin: 20)),
    ]
    for (name, before, after) in pairs {
        let width = after.width, height = after.height
        let legacyOld = try #require(LegacyContexts.pixels(of: before, width: width, height: height), "\(name)")
        let legacyNew = try #require(LegacyContexts.pixels(of: after, width: width, height: height), "\(name)")
        let old = try #require(ShotCommands.pixels(of: before, width: width, height: height, canvasType: CGCanvas.self), "\(name)")
        let new = try #require(ShotCommands.pixels(of: after, width: width, height: height, canvasType: CGCanvas.self), "\(name)")
        #expect(old == legacyOld, "\(name): a's pixels")
        #expect(new == legacyNew, "\(name): b's pixels")

        let mask = ImageDiff.changes(old, new, width: width, height: height, bytesPerRow: width * 4)
        let regions = ImageDiff.regions(in: mask, width: width, height: height)
        for lineWidth in [2, 3, 4] as [CGFloat] {
            try expectSame(
                LegacyContexts.highlight(after, mask: mask, regions: regions, lineWidth: lineWidth),
                ShotCommands.highlight(after, mask: mask, regions: regions, lineWidth: lineWidth, canvasType: CGCanvas.self),
                "\(name), \(lineWidth)-pixel boxes"
            )
        }
    }
}
