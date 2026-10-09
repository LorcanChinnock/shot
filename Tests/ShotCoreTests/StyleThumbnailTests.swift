import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private func filled(width: Int, height: Int, grey: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: grey, green: grey, blue: grey, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

/// The pixel at (`x`, `y`), top-left origin, from 0 to 255.
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
    let data = try #require(image.dataProvider?.data as Data?)
    let offset = y * image.bytesPerRow + x * 4
    return Array(data[offset..<offset + 4])
}

private let tile = CGSize(width: 48, height: 28)

@Test func aTileShowsTheScreenshotItselfShrunkToFit() throws {
    let capture = filled(width: 3000, height: 2000, grey: 0.5)
    let plain = try #require(StyleThumbnail.render(.image(capture), style: ObjectStyle(), cornerRadius: 0, size: tile, pixelsPerPoint: 2))
    #expect(plain.width == 96 && plain.height == 56)
    // The middle is the screenshot's grey, and the corners, outside the picture, are clear.
    #expect(try pixel(plain, 48, 26) == [128, 128, 128, 255])
    #expect(try pixel(plain, 0, 0)[3] == 0)
}

@Test func aTilesShadowAndBorderShowAroundThePicture() throws {
    let capture = filled(width: 300, height: 200, grey: 0.5)
    let plain = try #require(StyleThumbnail.render(.image(capture), style: ObjectStyle(), cornerRadius: 0, size: tile, pixelsPerPoint: 2))
    let shadow = try #require(StyleThumbnail.render(.image(capture), style: ObjectStyle(shadow: ShadowPreset.float.shadow(scale: 1)), cornerRadius: 0, size: tile, pixelsPerPoint: 2))
    // Below the picture, which ends about 40 pixels down, only the shadow paints.
    #expect(try pixel(plain, 48, 46)[3] == 0)
    #expect(try pixel(shadow, 48, 46)[3] > 0)
    let border = Border(kind: .solid, lineWidth: EditorStyle.widths[2], color: RGBA(1, 0, 0))
    let bordered = try #require(StyleThumbnail.render(.image(capture), style: ObjectStyle(border: border), cornerRadius: 0, size: tile, pixelsPerPoint: 2))
    // The picture is 52 pixels wide from x = 22, and the large border 3.2 pixels at this size, so just left of it is red.
    let edge = try pixel(bordered, 20, 26)
    #expect(edge[0] > 200 && edge[1] < 40 && edge[3] == 255)
}

@Test func aTileFitsAMarkAndDrawsItsShadowAtTileSize() throws {
    var arrow = Annotation(kind: .arrow(from: CGPoint(x: 400, y: 300), to: CGPoint(x: 900, y: 500)), color: RGBA(1, 0, 0), lineWidth: 12)
    let plain = try #require(StyleThumbnail.render(.annotation(arrow), style: ObjectStyle(), cornerRadius: 0, size: tile, pixelsPerPoint: 2))
    arrow.style = ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 2))
    let shadowed = try #require(StyleThumbnail.render(.annotation(arrow), style: ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 1)), cornerRadius: 0, size: tile, pixelsPerPoint: 2))
    let a = try #require(plain.dataProvider?.data as Data?), b = try #require(shadowed.dataProvider?.data as Data?)
    // The arrow is in the tile, and the shadow adds to it without the annotation's own style.
    #expect(a.enumerated().contains { $0.offset % 4 == 3 && $0.element > 0 })
    #expect(a != b)
}
