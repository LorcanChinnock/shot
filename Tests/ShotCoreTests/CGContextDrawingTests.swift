import CoreGraphics
import Testing
@testable import ShotCore

@Test func aNewBitmapContextHasTheFormatItWasMadeIn() throws {
    let grey = try #require(CGContext.bitmap(width: 3, height: 2, format: .grey))
    #expect(grey.colorSpace?.model == .monochrome)
    #expect(grey.alphaInfo == .none)
    let sRGB = try #require(CGContext.bitmap(width: 3, height: 2, format: .sRGB))
    #expect(sRGB.colorSpace?.name == CGColorSpace.sRGB)
    #expect(sRGB.alphaInfo == .premultipliedLast)
    let p3 = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
    let matching = try #require(CGContext.bitmap(width: 3, height: 2, format: .matching(p3)))
    #expect(matching.colorSpace?.name == CGColorSpace.displayP3)
    #expect(matching.makeImage()?.width == 3)
    #expect(CGContext.bitmap(width: 0, height: 2, format: .sRGB) == nil)
}

@Test func aBitmapContextReportsItsScaleAndClipInItsOwnCoordinates() throws {
    let context = try #require(CGContext.bitmap(width: 20, height: 20, format: .sRGB))
    #expect(context.pixelScale == 1)
    context.scaleBy(x: 2, y: -2)
    #expect(context.pixelScale == 2)
    #expect(context.boundingBoxOfClipPath == CGRect(x: 0, y: -10, width: 10, height: 10))
    context.clip(to: CGRect(x: 1, y: -9, width: 4, height: 4))
    #expect(context.boundingBoxOfClipPath == CGRect(x: 1, y: -9, width: 4, height: 4))
}
