import Foundation
import Testing
@testable import ShotCoreLinux

// Each Canvas method on small canvases, with exact pixels where antialiasing doesn't reach: fills on whole pixels,
// clips, blend modes, layers and images drawn pixel for pixel. A pixel is read as `Bitmap` reads it, from the top left,
// so the canvas's y up from the bottom is `height - 1 - y` here.

private func makeCanvas(_ width: Int = 4, _ height: Int = 4, format: CanvasFormat = .sRGB) throws -> CairoCanvas {
    try #require(CairoCanvas(width: width, height: height, format: format))
}

/// The premultiplied bytes of the pixel `x` across from the left and `y` up from the bottom.
private func pixel(_ canvas: CairoCanvas, _ x: Int, _ y: Int) throws -> [UInt8] {
    let bitmap = try #require(canvas.makeBitmap())
    let p = bitmap[x, bitmap.height - 1 - y]
    return [p.r, p.g, p.b, p.a]
}

private let red = RGBA(1, 0, 0), blue = RGBA(0, 0, 1), white = RGBA(1, 1, 1), clear: [UInt8] = [0, 0, 0, 0]

@Test func aNewCairoCanvasIsClearOrBlackAndSRGBWhateverItMatches() throws {
    #expect(try pixel(makeCanvas(), 1, 1) == clear)
    #expect(try pixel(makeCanvas(format: .grey), 1, 1) == [0, 0, 0, 255])
    let image = BitmapImage(try #require(Bitmap(width: 1, height: 1, pixels: Data([1, 2, 3, 255]))))
    let matching = try makeCanvas(3, 2, format: .matching(image))
    #expect(matching.makeImage()?.width == 3 && matching.makeImage()?.height == 2)
    #expect(CairoCanvas(width: 0, height: 2, format: .sRGB) == nil)
}

@Test func aCairoCanvasHasItsOriginAtTheBottomLeft() throws {
    let canvas = try makeCanvas(4, 3)
    canvas.setFillColor(red)
    canvas.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
    let bitmap = try #require(canvas.makeBitmap())
    #expect(bitmap[0, 2] == (255, 0, 0, 255) && bitmap[1, 2] == (255, 0, 0, 255))
    #expect(bitmap[2, 2] == (0, 0, 0, 0) && bitmap[0, 1] == (0, 0, 0, 0))
}

@Test func aCairoCanvasReportsItsScaleAndClipInItsOwnCoordinates() throws {
    let canvas = try makeCanvas(20, 20)
    #expect(canvas.pixelScale == 1)
    canvas.scaleBy(x: 2, y: -2)
    #expect(canvas.pixelScale == 2)
    #expect(canvas.clipBounds == CGRect(x: 0, y: -10, width: 10, height: 10))
    canvas.clip(to: CGRect(x: 1, y: -9, width: 4, height: 4))
    #expect(canvas.clipBounds == CGRect(x: 1, y: -9, width: 4, height: 4))
    canvas.clip(to: CGRect(x: 8, y: -2, width: 1, height: 1))
    #expect(canvas.clipBounds.isNull)
}

@Test func fillsAndStrokesOnWholePixelsAreExact() throws {
    let canvas = try makeCanvas(6, 6)
    canvas.setFillColor(RGBA(1, 0, 0, 0.5))
    canvas.fill(CanvasPath(rect: CGRect(x: 0, y: 0, width: 2, height: 2)))
    canvas.setStrokeColor(blue)
    canvas.setLineWidth(2)
    canvas.setLineJoin(.miter)
    // A 2-wide stroke centred on whole pixels covers one pixel either side of each edge.
    canvas.stroke(CanvasPath(rect: CGRect(x: 3, y: 1, width: 2, height: 4)))
    #expect(try pixel(canvas, 1, 1) == [128, 0, 0, 128])
    #expect(try pixel(canvas, 2, 0) == [0, 0, 255, 255])
    #expect(try pixel(canvas, 5, 5) == [0, 0, 255, 255])
    #expect(try pixel(canvas, 2, 3) == [0, 0, 255, 255])
    #expect(try pixel(canvas, 3, 3) == [0, 0, 255, 255])
    #expect(try pixel(canvas, 0, 5) == clear)
}

@Test func theAlphaScalesWhatsDrawnAndCapsShapeTheEnds() throws {
    let canvas = try makeCanvas(8, 3)
    canvas.setAlpha(0.5)
    canvas.setFillColor(white)
    canvas.fill(CGRect(x: 0, y: 2, width: 1, height: 1))
    canvas.setAlpha(1)
    canvas.setStrokeColor(red)
    canvas.setLineWidth(2)
    var line = CanvasPath()
    line.move(to: CGPoint(x: 2, y: 1))
    line.addLine(to: CGPoint(x: 5, y: 1))
    canvas.setLineCap(.butt)
    canvas.stroke(line)
    #expect(try pixel(canvas, 0, 2) == [128, 128, 128, 128])
    #expect(try pixel(canvas, 1, 1) == clear)
    #expect(try pixel(canvas, 4, 1) == [255, 0, 0, 255])
    #expect(try pixel(canvas, 5, 1) == clear)
    canvas.setLineCap(.square)
    canvas.stroke(line)
    #expect(try pixel(canvas, 1, 1) == [255, 0, 0, 255])
    #expect(try pixel(canvas, 5, 1) == [255, 0, 0, 255])
    #expect(try pixel(canvas, 6, 1) == clear)
}

@Test func pathsFillByTheNonzeroWindingRule() throws {
    let canvas = try makeCanvas(6, 6)
    var ring = CanvasPath()
    // Both squares run the same way, so the inner one stays filled.
    ring.addRect(CGRect(x: 0, y: 0, width: 6, height: 6))
    ring.addRect(CGRect(x: 2, y: 2, width: 2, height: 2))
    canvas.setFillColor(red)
    canvas.fill(ring)
    #expect(try pixel(canvas, 3, 3) == [255, 0, 0, 255])
    let other = try makeCanvas(6, 6)
    var hole = CanvasPath()
    hole.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 6, y: 0), CGPoint(x: 6, y: 6), CGPoint(x: 0, y: 6)])
    hole.closeSubpath()
    hole.addLines(between: [CGPoint(x: 2, y: 2), CGPoint(x: 2, y: 4), CGPoint(x: 4, y: 4), CGPoint(x: 4, y: 2)])
    hole.closeSubpath()
    other.setFillColor(red)
    other.fill(hole)
    #expect(try pixel(other, 3, 3) == clear)
    #expect(try pixel(other, 1, 1) == [255, 0, 0, 255])
}

@Test func clipsAndStateLastUntilTheRestore() throws {
    let canvas = try makeCanvas(6, 6)
    canvas.saveState()
    canvas.clip(to: CGRect(x: 1, y: 1, width: 4, height: 4))
    canvas.clip(to: CanvasPath(rect: CGRect(x: 0, y: 0, width: 3, height: 6)))
    canvas.translateBy(x: 10, y: 0)
    canvas.setFillColor(red)
    canvas.setAlpha(0.5)
    canvas.restoreState()
    canvas.saveState()
    canvas.clip(to: CGRect(x: 1, y: 1, width: 4, height: 4))
    canvas.clip(to: CanvasPath(rect: CGRect(x: 0, y: 0, width: 3, height: 6)))
    canvas.setFillColor(blue)
    canvas.fill(CGRect(x: 0, y: 0, width: 6, height: 6))
    canvas.restoreState()
    #expect(try pixel(canvas, 2, 2) == [0, 0, 255, 255])
    #expect(try pixel(canvas, 3, 2) == clear)
    #expect(try pixel(canvas, 0, 2) == clear)
    #expect(try pixel(canvas, 2, 5) == clear)
    // After the restore nothing clips, and the fill is the black a canvas starts with.
    canvas.fill(CGRect(x: 5, y: 5, width: 1, height: 1))
    #expect(try pixel(canvas, 5, 5) == [0, 0, 0, 255])
}

@Test func eachBlendModeHasItsCairoOperator() throws {
    func blended(_ mode: CanvasBlendMode, under: RGBA?, over: RGBA) throws -> [UInt8] {
        let canvas = try makeCanvas(1, 1)
        if let under {
            canvas.setFillColor(under)
            canvas.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        canvas.setBlendMode(mode)
        canvas.setFillColor(over)
        canvas.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return try pixel(canvas, 0, 0)
    }
    let yellow = RGBA(1, 1, 0), grey = RGBA(0.5, 0.5, 0.5)
    // Half is 128 of 255, so 127 of what's under it shows through.
    #expect(try blended(.normal, under: yellow, over: RGBA(0, 0, 1, 0.5)) == [127, 127, 128, 255])
    #expect(try blended(.multiply, under: yellow, over: grey) == [128, 128, 0, 255])
    #expect(try blended(.darken, under: yellow, over: grey) == [128, 128, 0, 255])
    #expect(try blended(.sourceAtop, under: yellow, over: blue) == [0, 0, 255, 255])
    // Atop draws only where there's something already.
    #expect(try blended(.sourceAtop, under: nil, over: blue) == clear)
}

@Test func aTransparencyLayerCompositesAsOneWithTheAlphaSetWhenItBegan() throws {
    let canvas = try makeCanvas(3, 1)
    canvas.setAlpha(0.5)
    canvas.beginTransparencyLayer()
    canvas.setFillColor(red)
    // Overlapping in the middle pixel, which a layer keeps from doubling up.
    canvas.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
    canvas.fill(CGRect(x: 1, y: 0, width: 2, height: 1))
    canvas.endTransparencyLayer()
    #expect(try pixel(canvas, 0, 0) == [128, 0, 0, 128])
    #expect(try pixel(canvas, 1, 0) == [128, 0, 0, 128])
    #expect(try pixel(canvas, 2, 0) == [128, 0, 0, 128])
    let plain = try makeCanvas(3, 1)
    plain.setAlpha(0.5)
    plain.setFillColor(red)
    plain.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
    plain.fill(CGRect(x: 1, y: 0, width: 2, height: 1))
    #expect(try pixel(plain, 1, 0) == [192, 0, 0, 192])
}

@Test func aLayersTransformAndStateEndWithIt() throws {
    let canvas = try makeCanvas(4, 1)
    canvas.setFillColor(red)
    canvas.beginTransparencyLayer()
    // Inside it the colour carries on, and the alpha and blend mode start over.
    canvas.translateBy(x: 2, y: 0)
    canvas.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    canvas.setFillColor(blue)
    canvas.endTransparencyLayer()
    canvas.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    #expect(try pixel(canvas, 0, 0) == [255, 0, 0, 255])
    #expect(try pixel(canvas, 2, 0) == [255, 0, 0, 255])
    #expect(try pixel(canvas, 1, 0) == clear)
}

/// A 2×2 image: red and green on the top row, blue and half-clear white below.
private func quad() throws -> BitmapImage {
    BitmapImage(try #require(Bitmap(width: 2, height: 2, pixels: Data([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 128, 128, 128, 128]))))
}

@Test func anImageDrawsPixelForPixelWithItsFirstRowAtTheTop() throws {
    let canvas = try makeCanvas(3, 3)
    canvas.draw(try quad(), in: CGRect(x: 1, y: 1, width: 2, height: 2))
    #expect(try pixel(canvas, 1, 2) == [255, 0, 0, 255])
    #expect(try pixel(canvas, 2, 2) == [0, 255, 0, 255])
    #expect(try pixel(canvas, 1, 1) == [0, 0, 255, 255])
    #expect(try pixel(canvas, 2, 1) == [128, 128, 128, 128])
    #expect(try pixel(canvas, 0, 0) == clear)
}

@Test func anImageStretchedAtLowQualityRepeatsItsPixels() throws {
    let canvas = try makeCanvas(4, 4)
    canvas.setInterpolation(.low)
    canvas.setAlpha(0.5)
    canvas.draw(try quad(), in: CGRect(x: 0, y: 0, width: 4, height: 4))
    #expect(try pixel(canvas, 0, 3) == [128, 0, 0, 128])
    #expect(try pixel(canvas, 1, 2) == [128, 0, 0, 128])
    #expect(try pixel(canvas, 3, 3) == [0, 128, 0, 128])
    #expect(try pixel(canvas, 3, 0) == [64, 64, 64, 64])
}

@Test func aMaskClipLetsThroughAsMuchAsItIsLight() throws {
    let canvas = try makeCanvas(4, 2)
    // White, half grey and black on the top row; black below.
    let levels: [UInt8] = [255, 128, 0, 0]
    let mask = BitmapImage(try #require(Bitmap(width: 2, height: 2, pixels: Data(levels.flatMap { [$0, $0, $0, 255] }))))
    canvas.clip(to: CGRect(x: 0, y: 0, width: 2, height: 2), mask: mask)
    canvas.setInterpolation(.low)
    canvas.setFillColor(red)
    canvas.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
    #expect(try pixel(canvas, 0, 1) == [255, 0, 0, 255])
    #expect(try pixel(canvas, 1, 1) == [128, 0, 0, 128])
    #expect(try pixel(canvas, 0, 0) == clear)
    // Outside the mask's rect nothing gets through.
    #expect(try pixel(canvas, 3, 1) == clear)
    #expect(canvas.clipBounds == CGRect(x: 0, y: 0, width: 2, height: 2))
}

@Test func masksMultiplyAndLeaveWithTheRestore() throws {
    let canvas = try makeCanvas(2, 1)
    let half = BitmapImage(try #require(Bitmap(width: 1, height: 1, pixels: Data([128, 128, 128, 255]))))
    canvas.saveState()
    canvas.clip(to: CGRect(x: 0, y: 0, width: 2, height: 1), mask: half)
    canvas.clip(to: CGRect(x: 0, y: 0, width: 1, height: 1), mask: half)
    canvas.setFillColor(white)
    canvas.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
    canvas.restoreState()
    #expect(try pixel(canvas, 0, 0) == [64, 64, 64, 64])
    canvas.setFillColor(red)
    canvas.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
    #expect(try pixel(canvas, 1, 0) == [255, 0, 0, 255])
}

@Test func aGreyCanvasKeepsLevelsInOpaqueGreyPixels() throws {
    let canvas = try makeCanvas(3, 1, format: .grey)
    canvas.setFillColor(white)
    canvas.fill(CGRect(x: 0, y: 0, width: 3, height: 1))
    canvas.setFillColor(RGBA(0, 0, 0))
    canvas.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
    canvas.setFillColor(RGBA(1, 1, 1, 0.5))
    canvas.fill(CGRect(x: 1, y: 0, width: 2, height: 1))
    #expect(try pixel(canvas, 0, 0) == [255, 255, 255, 255])
    #expect(try pixel(canvas, 1, 0) == [128, 128, 128, 255])
    #expect(try pixel(canvas, 2, 0) == [255, 255, 255, 255])
}

/// The alpha along the middle row of a shadow from a square edge at x = 48, blur 8, cast from well to the right as the
/// renderer casts it.
private func shadowRow(blur: CGFloat, scale: CGFloat = 1) throws -> [Int] {
    let canvas = try makeCanvas(96, 4)
    canvas.scaleBy(x: scale, y: scale)
    canvas.setShadow(offset: CGSize(width: -1000 / scale, height: 0), blur: blur / scale, color: RGBA(0, 0, 0))
    canvas.setFillColor(red)
    canvas.fill(CGRect(x: 1048 / scale, y: -100, width: 5000, height: 300))
    let bitmap = try #require(canvas.makeBitmap())
    return (0..<96).map { Int(bitmap[$0, 1].a) }
}

@Test func aShadowIsBlurredAsCoreGraphicsBlursIt() throws {
    // CoreGraphics' alpha for x = 40 to 56, from the same drawing on macOS.
    let mac = [4, 9, 18, 30, 46, 66, 89, 114, 141, 166, 189, 209, 225, 237, 246, 251, 255]
    let row = try shadowRow(blur: 8)
    for (index, expected) in mac.enumerated() {
        #expect(abs(row[40 + index] - expected) <= 12, "x = \(40 + index): \(row[40 + index]), CoreGraphics \(expected)")
    }
    #expect(row[30] == 0 && row[70] == 255)
    // Mapped through the scale, as CoreGraphics maps it, the shadow is the same.
    #expect(try shadowRow(blur: 8, scale: 2) == row)
}

@Test func aShadowFallsWhereItsOffsetSaysAndTheShapeStaysClear() throws {
    let canvas = try makeCanvas(20, 20)
    canvas.setShadow(offset: CGSize(width: 0, height: -6), blur: 0, color: RGBA(0, 0, 1, 0.5))
    canvas.setFillColor(red)
    canvas.fill(CGRect(x: 4, y: 10, width: 4, height: 4))
    // y up, so the shadow is below, half blue, and the shape over it is opaque.
    #expect(try pixel(canvas, 5, 5) == [0, 0, 128, 128])
    #expect(try pixel(canvas, 5, 11) == [255, 0, 0, 255])
    #expect(try pixel(canvas, 5, 2) == clear)
    #expect(try pixel(canvas, 10, 5) == clear)
}

@Test func aFractionalShadowOffsetLeavesTheShapeCrisp() throws {
    let canvas = try makeCanvas(20, 20)
    // A note's shadow, 3.6 below it at 24 pt.
    canvas.setShadow(offset: CGSize(width: 0.4, height: -3.6), blur: 0, color: RGBA(0, 0, 1, 0.5))
    canvas.setFillColor(red)
    canvas.fill(CGRect(x: 4, y: 10, width: 4, height: 4))
    for (x, y) in [(4, 10), (7, 13), (5, 10), (5, 13), (4, 12), (7, 11)] {
        #expect(try pixel(canvas, x, y) == [255, 0, 0, 255], "(\(x), \(y))")
    }
    #expect(try pixel(canvas, 5, 14) == clear && pixel(canvas, 8, 12) == clear)
}

@Test func aCairoCanvasImageRoundTripsThroughThePNGCodec() throws {
    let canvas = try makeCanvas(5, 3)
    canvas.setFillColor(RGBA(0.2, 0.4, 0.6, 0.8))
    canvas.fill(CanvasPath(ellipseIn: CGRect(x: 0, y: 0, width: 5, height: 3)))
    let bitmap = try #require(canvas.makeBitmap())
    let codec = PNGJPEGCodec()
    let png = try #require(codec.encode(bitmap, as: .png, quality: 1, metadata: ImageMetadata()))
    #expect(codec.decode(png) == bitmap)
}
