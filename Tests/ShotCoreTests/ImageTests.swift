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
