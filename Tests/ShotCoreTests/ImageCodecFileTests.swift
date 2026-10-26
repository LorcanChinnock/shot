import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

/// A `width` by `height` image whose every pixel differs, with alpha from opaque at the top to almost clear at the
/// bottom, so a round trip that loses any pixel, its colour or its transparency shows.
private func gradient(width: Int, height: Int) throws -> CGImage {
    let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    for y in 0 ..< height {
        for x in 0 ..< width {
            ctx.setFillColor(red: CGFloat(x) / CGFloat(width), green: CGFloat(y) / CGFloat(height), blue: 0.5, alpha: 1 - CGFloat(y) / CGFloat(height + 1))
            ctx.fill(CGRect(x: x, y: height - 1 - y, width: 1, height: 1))
        }
    }
    return try #require(ctx.makeImage())
}

@Test(arguments: [CGFloat(1), 2])
func aDecodedPNGEncodesAndDecodesToTheSamePixels(scale: CGFloat) throws {
    let file = try #require(ImageCodec.data(from: gradient(width: 33, height: 17), scale: scale))
    let decoded = try #require(ImageCodec.image(from: file))
    #expect(decoded.width == 33 && decoded.height == 17 && ImageCodec.scale(of: file) == scale)
    let encoded = try #require(ImageCodec.data(from: decoded, scale: scale))
    let again = try #require(ImageCodec.image(from: encoded))
    #expect(ImageCodec.scale(of: encoded) == scale)
    #expect(Bitmap(again) == Bitmap(decoded))
}

@Test func aBitmapGoesToACGImageAndBackUnchanged() throws {
    let bitmap = try #require(Bitmap(try gradient(width: 20, height: 10), scale: 2))
    let image = try #require(bitmap.cgImage)
    #expect(image.width == 20 && image.height == 10)
    #expect(Bitmap(image, scale: 2) == bitmap)
}

@Test func aBitmapIsTopRowFirst() throws {
    let ctx = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    // CoreGraphics' origin is at the bottom left, so this is the top row.
    ctx.fill(CGRect(x: 0, y: 1, width: 2, height: 1))
    let image = try #require(ctx.makeImage())
    let bitmap = try #require(Bitmap(image))
    #expect(bitmap[0, 0] == (255, 0, 0, 255))
    #expect(bitmap[0, 1] == (0, 0, 0, 0))
}

@Test(arguments: [ImageFormat.png, .jpeg])
func whatAnImageIsEncodedWithReadsBackFromTheFile(format: ImageFormat) throws {
    let data = try #require(ImageCodec.data(from: gradient(width: 20, height: 10), scale: 2, format: format, windowShadow: true, projectID: "ID-1"))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("codec-\(UUID().uuidString).\(format.fileExtension)")
    defer { try? FileManager.default.removeItem(at: url) }
    try data.write(to: url)
    #expect(ImageCodec.scale(ofFileAt: url) == 2)
    #expect(ImageCodec.projectID(ofFileAt: url) == "ID-1")
    #expect(ImageCodec.hasWindowShadow(ofFileAt: url))
    let read = try #require(ImageCodec.image(at: url))
    #expect(read.width == 20 && read.height == 10)
}

@Test func aFileThatIsntAnImageHasNoImage() {
    #expect(ImageCodec.image(from: Data("not an image".utf8)) == nil)
}

@Test func aLowerJPEGQualityGivesASmallerFile() throws {
    let image = try gradient(width: 64, height: 64)
    let high = try #require(ImageCodec.data(from: image, scale: 1, format: .jpeg, quality: 0.95))
    let low = try #require(ImageCodec.data(from: image, scale: 1, format: .jpeg, quality: 0.2))
    #expect(low.count < high.count)
}
