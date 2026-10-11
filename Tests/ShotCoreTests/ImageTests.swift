import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

func solidImage(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

@Test(arguments: [1.0, 2.0])
func pngDPIMatchesScale(scale: CGFloat) throws {
    let data = try #require(ImageCodec.data(from: solidImage(width: 20, height: 10), scale: scale))
    #expect(ImageCodec.scale(of: data) == scale)
}

@Test func thumbnailFitsLongEdgeAndKeepsAspect() throws {
    let data = try #require(ImageCodec.data(from: solidImage(width: 1200, height: 300), scale: 2))
    let thumbnail = try #require(ImageCodec.thumbnail(from: data, maxPixelSize: 480))
    #expect(thumbnail.width == 480)
    #expect(thumbnail.height == 120)
    let small = try #require(ImageCodec.data(from: solidImage(width: 40, height: 20), scale: 1))
    #expect(try #require(ImageCodec.thumbnail(from: small, maxPixelSize: 480)).width == 40)
}

@Test func trimTransparentEdges() throws {
    let ctx = try #require(CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.2)
    ctx.fill(CGRect(x: 10, y: 5, width: 60, height: 50))
    let trimmed = ImageTrim.trimTransparentEdges(try #require(ctx.makeImage()))
    #expect(trimmed.width == 60)
    #expect(trimmed.height == 50)
}

@Test func jpegEncodingAndDownscale() throws {
    let image = solidImage(width: 40, height: 20)
    let jpeg = try #require(ImageCodec.data(from: image, scale: 2, format: .jpeg))
    #expect(jpeg.starts(with: [0xFF, 0xD8]))
    #expect(ImageCodec.scale(of: jpeg) == 2)
    let small = ImageCodec.downscaled(image, scale: 2)
    #expect(small.width == 20)
    #expect(small.height == 10)
    #expect(ImageCodec.downscaled(image, scale: 1).width == 40)
    #expect(ImageFormat(fileExtension: "JPG") == .jpeg)
    #expect(ImageFormat(fileExtension: "png") == .png)
}

/// Random pixels, which compress about as badly as any capture can.
private func noiseImage(width: Int, height: Int) throws -> CGImage {
    let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    let words = try #require(ctx.data).bindMemory(to: UInt32.self, capacity: width * height)
    var state: UInt32 = 2_463_534_242
    for index in 0..<width * height {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        words[index] = state
    }
    return try #require(ctx.makeImage())
}

private func jpegSize(_ data: Data) throws -> (width: Int, height: Int) {
    let image = try #require(ImageCodec.image(from: data))
    return (image.width, image.height)
}

@Test func previewJPEGFitsTheLongEdgeAndKeepsAspect() throws {
    let url = try temporaryFolder().appendingPathComponent("wide.png")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try #require(ImageCodec.data(from: solidImage(width: 3200, height: 800), scale: 2)).write(to: url)
    let preview = try #require(ImageCodec.previewJPEG(at: url))
    #expect(preview.starts(with: [0xFF, 0xD8]))
    let size = try jpegSize(preview)
    #expect(size.width == 1568 && size.height == 392)
}

@Test func previewJPEGNeverEnlarges() throws {
    let url = try temporaryFolder().appendingPathComponent("small.png")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try #require(ImageCodec.data(from: solidImage(width: 300, height: 200), scale: 1)).write(to: url)
    let size = try jpegSize(try #require(ImageCodec.previewJPEG(at: url)))
    #expect(size.width == 300 && size.height == 200)
}

@Test(arguments: [1_000_000, 150_000])
func previewJPEGStaysUnderTheByteCapForNoise(_ maxBytes: Int) throws {
    let noise = try noiseImage(width: 2000, height: 1500)
    let preview = try #require(ImageCodec.previewJPEG(of: noise, maxBytes: maxBytes))
    #expect(preview.count <= maxBytes)
    let size = try jpegSize(preview)
    #expect(max(size.width, size.height) <= 1568)
}

@Test func previewJPEGTurnsTransparencyWhite() throws {
    let ctx = try #require(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let clear = try #require(ctx.makeImage())
    let preview = try #require(ImageCodec.previewJPEG(of: clear))
    let decoded = try #require(ImageCodec.image(from: preview))
    #expect(try grayLevel(of: decoded) > 245)
}
