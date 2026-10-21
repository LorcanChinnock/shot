import Foundation
import Testing
@testable import ShotCore

/// A `width` × `height` image of opaque grey, with `alpha` at the pixels in `clear`.
private func image(width: Int, height: Int, clear: [(x: Int, y: Int)] = [], alpha: UInt8 = 0) throws -> BitmapImage {
    var pixels = Data(repeating: 255, count: width * height * 4)
    for (x, y) in clear {
        let i = (y * width + x) * 4
        pixels.replaceSubrange(i..<i + 4, with: [alpha, alpha, alpha, alpha])
    }
    return BitmapImage(try #require(Bitmap(width: width, height: height, pixels: pixels)))
}

@Test func aBitmapImageIsTransparentWhenAnyPixelIsntOpaque() throws {
    #expect(try !image(width: 4, height: 3).hasTransparentPixels)
    #expect(try image(width: 4, height: 3, clear: [(3, 2)]).hasTransparentPixels)
    #expect(try image(width: 4, height: 3, clear: [(0, 0)], alpha: 254).hasTransparentPixels)
}

@Test func croppingABitmapImageKeepsThePixelsInTheRectFromTheTopLeft() throws {
    // 4×3, numbered by pixel so each crop shows which it kept.
    let pixels = Data((0..<12).flatMap { [UInt8($0), 0, 0, 255] })
    let whole = BitmapImage(try #require(Bitmap(width: 4, height: 3, scale: 2, pixels: pixels)))
    let cropped = try #require(whole.cropping(to: CGRect(x: 1, y: 1, width: 2, height: 2)))
    #expect(cropped.width == 2 && cropped.height == 2)
    #expect(cropped.bitmap.scale == 2)
    #expect([cropped.bitmap[0, 0].r, cropped.bitmap[1, 0].r, cropped.bitmap[0, 1].r, cropped.bitmap[1, 1].r] == [5, 6, 9, 10])
}

@Test func croppingABitmapImageRoundsOutAndStaysWithinIt() throws {
    let whole = try image(width: 4, height: 3)
    let rounded = try #require(whole.cropping(to: CGRect(x: 0.5, y: 0.5, width: 1, height: 1)))
    #expect(rounded.width == 2 && rounded.height == 2)
    let clipped = try #require(whole.cropping(to: CGRect(x: 2, y: -5, width: 10, height: 6)))
    #expect(clipped.width == 2 && clipped.height == 1)
    #expect(whole.cropping(to: CGRect(x: 5, y: 0, width: 2, height: 2)) == nil)
    #expect(whole.cropping(to: CGRect(x: 1, y: 1, width: 0, height: 2)) == nil)
}

@Test func aCropKeepsTransparencyOnlyWhereItKeepsTheClearPixels() throws {
    let whole = try image(width: 4, height: 3, clear: [(3, 2)])
    #expect(try #require(whole.cropping(to: CGRect(x: 0, y: 0, width: 3, height: 3))).hasTransparentPixels == false)
    #expect(try #require(whole.cropping(to: CGRect(x: 2, y: 1, width: 2, height: 2))).hasTransparentPixels)
}
