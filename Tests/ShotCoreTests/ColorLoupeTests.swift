import CoreGraphics
import Testing
@testable import ShotCore

private let screen = CGRect(x: 0, y: 0, width: 1280, height: 800)
private let label = CGSize(width: 96, height: 24)
private let hint = CGSize(width: 180, height: 19)

// MARK: Layout

@Test func theLoupeIsCentredOnThePointer() {
    let layout = ColorLoupe.layout(pointer: CGPoint(x: 640, y: 400), side: 121, outset: 4.5, label: label, hint: hint, in: screen)
    #expect(layout.loupe.width == 121)
    #expect(abs(layout.loupe.midX - 640) <= 0.5)
    #expect(abs(layout.loupe.midY - 400) <= 0.5)
}

@Test func theLabelAndHintSitBelowTheLoupeAGapApart() {
    let layout = ColorLoupe.layout(pointer: CGPoint(x: 640, y: 400), side: 121, outset: 4.5, label: label, hint: hint, in: screen)
    #expect(layout.label.maxY == layout.loupe.minY - 4.5 - ColorLoupe.gap)
    #expect(layout.hint.maxY == layout.label.minY - ColorLoupe.gap)
    #expect(abs(layout.label.midX - 640) <= 0.5)
    #expect(abs(layout.hint.midX - 640) <= 0.5)
}

@Test func theLabelAndHintGoAboveTheLoupeAtTheBottomOfTheScreen() {
    let layout = ColorLoupe.layout(pointer: CGPoint(x: 640, y: 60), side: 121, outset: 4.5, label: label, hint: hint, in: screen)
    #expect(layout.hint.minY == layout.loupe.maxY + 4.5 + ColorLoupe.gap)
    #expect(layout.label.minY == layout.hint.maxY + ColorLoupe.gap)
}

@Test func theLabelAndHintStayOnScreenAtItsSides() {
    let left = ColorLoupe.layout(pointer: CGPoint(x: 4, y: 400), side: 121, outset: 4.5, label: label, hint: hint, in: screen)
    #expect(left.label.minX == ColorLoupe.margin)
    #expect(left.hint.minX == ColorLoupe.margin)
    let right = ColorLoupe.layout(pointer: CGPoint(x: 1278, y: 400), side: 121, outset: 4.5, label: label, hint: hint, in: screen)
    #expect(right.hint.maxX == screen.maxX - ColorLoupe.margin)
    // The loupe itself follows the pointer off the edge, so its middle cell stays the pixel picked.
    #expect(right.loupe.maxX > screen.maxX)
}

@Test func cellsAreWholePoints() {
    #expect(ColorLoupe.cell(side: 120) == 11)
    #expect(ColorLoupe.cell(side: 150) == 14)
    #expect(ColorLoupe.cell(side: 4) == 1)
}

// MARK: Pixel colour

private func image(_ colors: [[UInt8]], space: CGColorSpace) -> CGImage {
    var bytes = colors.flatMap { $0 }
    let width = colors.count
    return bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}

@Test func anSRGBPixelKeepsItsHex() throws {
    let srgb = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let picture = image([[0x1E, 0x90, 0xFF, 0xFF], [0xF4, 0xF6, 0xFA, 0xFF]], space: srgb)
    #expect(PixelColor.sRGB(of: picture, x: 0, y: 0)?.hex == "#1E90FF")
    #expect(PixelColor.sRGB(of: picture, x: 1, y: 0)?.hex == "#F4F6FA")
}

@Test func aDisplayP3PixelIsConvertedToSRGB() throws {
    let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
    // P3's pure red is outside sRGB, so it clips to sRGB's red; P3 white is white in both.
    let picture = image([[0xFF, 0x00, 0x00, 0xFF], [0xFF, 0xFF, 0xFF, 0xFF]], space: p3)
    #expect(PixelColor.sRGB(of: picture, x: 0, y: 0)?.hex == "#FF0000")
    #expect(PixelColor.sRGB(of: picture, x: 1, y: 0)?.hex == "#FFFFFF")
    // A P3 mid green lands on a different sRGB value, so the colour is converted, not just relabelled.
    let green = image([[0x40, 0xA0, 0x40, 0xFF]], space: p3)
    #expect(PixelColor.sRGB(of: green, x: 0, y: 0)?.hex != "#40A040")
}

@Test func aPixelOffTheImageHasNoColour() throws {
    let srgb = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let picture = image([[0, 0, 0, 0xFF]], space: srgb)
    #expect(PixelColor.sRGB(of: picture, x: 1, y: 0) == nil)
    #expect(PixelColor.sRGB(of: picture, x: 0, y: -1) == nil)
}
