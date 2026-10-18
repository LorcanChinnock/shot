import CoreGraphics
import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

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
    let codec = ImageIOCodec()
    let file = try #require(ImageCodec.data(from: gradient(width: 33, height: 17), scale: scale))
    let decoded = try #require(codec.decode(file))
    #expect(decoded.width == 33 && decoded.height == 17 && decoded.scale == scale)
    let encoded = try #require(codec.encode(decoded, as: .png, quality: 1, metadata: ImageMetadata()))
    let again = try #require(codec.decode(encoded))
    #expect(again == decoded)
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
func whatABitmapIsEncodedWithReadsBackFromTheFile(format: ImageFormat) throws {
    let codec = ImageIOCodec()
    let record = CaptureRecord(original: "Shot.png", kind: "image", created: Date(timeIntervalSince1970: 1_791_640_992), size: .init(width: 20, height: 10), scale: 2)
    let bitmap = try #require(Bitmap(try gradient(width: 20, height: 10), scale: 2))
    let data = try #require(codec.encode(bitmap, as: format, quality: 0.9, metadata: ImageMetadata(windowShadow: true, record: record, projectID: "ID-1")))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("codec-\(UUID().uuidString).\(format.fileExtension)")
    defer { try? FileManager.default.removeItem(at: url) }
    try data.write(to: url)
    #expect(codec.info(ofFileAt: url) == ImageFileInfo(isGIF: false, frames: 1, size: CaptureRecord.Size(width: 20, height: 10)))
    #expect(codec.info(of: data) == codec.info(ofFileAt: url))
    #expect(codec.scale(ofFileAt: url) == 2)
    #expect(codec.record(ofFileAt: url) == record)
    #expect(codec.projectID(ofFileAt: url) == "ID-1")
    #expect(codec.hasWindowShadow(ofFileAt: url))
    let read = try #require(codec.decode(fileAt: url))
    #expect(read.width == 20 && read.height == 10 && read.scale == 2)
}

@Test func aFileThatIsntAnImageHasNoInfo() {
    #expect(ImageIOCodec().info(of: Data("not an image".utf8)) == nil)
    #expect(ImageIOCodec().decode(Data("not an image".utf8)) == nil)
}

@Test func aLowerJPEGQualityGivesASmallerFile() throws {
    let codec = ImageIOCodec()
    let bitmap = try #require(Bitmap(try gradient(width: 64, height: 64)))
    let high = try #require(codec.encode(bitmap, as: .jpeg, quality: 0.95, metadata: ImageMetadata()))
    let low = try #require(codec.encode(bitmap, as: .jpeg, quality: 0.2, metadata: ImageMetadata()))
    #expect(low.count < high.count)
}
