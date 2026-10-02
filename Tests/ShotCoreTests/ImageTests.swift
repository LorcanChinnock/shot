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
    let data = try #require(PNG.data(from: solidImage(width: 20, height: 10), scale: scale))
    #expect(PNG.scale(of: data) == scale)
}
