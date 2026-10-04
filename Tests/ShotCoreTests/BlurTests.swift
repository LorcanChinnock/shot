import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let red = RGBA.presets[0]

private func blur(_ rect: CGRect) -> Annotation {
    Annotation(kind: .blur(rect), color: red, lineWidth: 4)
}

/// Black and white stripes 2 px wide: the sharpest detail an image can have.
private func stripes(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    for x in stride(from: 0, to: width, by: 4) {
        ctx.fill(CGRect(x: x, y: 0, width: 2, height: height))
    }
    return ctx.makeImage()!
}

/// Renders as the editor does: into a context zoomed by `scale`.
private func render(_ doc: EditorDocument, scale: CGFloat) throws -> CGImage {
    let size = doc.exportSize
    let ctx = try #require(CGContext(
        data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: scale, y: scale)
    AnnotationRenderer.render(doc, into: ctx)
    return try #require(ctx.makeImage())
}

/// The pixel at image point (`x`, `y`), top-left origin, as 0...1 components.
private func pixel(_ image: CGImage, _ x: CGFloat, _ y: CGFloat, scale: CGFloat = 1) throws -> [CGFloat] {
    let data = try #require(image.dataProvider?.data as Data?)
    let offset = Int(y * scale) * image.bytesPerRow + Int(x * scale) * 4
    return data[offset..<offset + 4].map { CGFloat($0) / 255 }
}

@Test func blurIsAFilledBoxThatMoves() {
    let rect = CGRect(x: 10, y: 10, width: 50, height: 20)
    var a = blur(rect)
    #expect(a.bounds == rect)
    #expect(a.paintedBounds == rect)
    #expect(a.hitTest(CGPoint(x: 30, y: 20), tolerance: 0))
    #expect(!a.hitTest(CGPoint(x: 100, y: 20), tolerance: 0))
    a.offset(by: CGVector(dx: 5, dy: -5))
    #expect(a.kind == .blur(CGRect(x: 15, y: 5, width: 50, height: 20)))
}

@Test(arguments: [1.0, 2.0])
func blurRendersTheSameInTheEditorAndTheExport(scale: CGFloat) throws {
    let region = CGRect(x: 40, y: 20, width: 120, height: 60)
    let doc = EditorDocument(base: stripes(width: 200, height: 100), annotations: [blur(region)])
    let flat = try #require(AnnotationRenderer.flatten(doc))
    let editor = try render(doc, scale: scale)
    for x in stride(from: region.minX + 4, to: region.maxX - 4, by: 7) {
        for y in stride(from: region.minY + 4, to: region.maxY - 4, by: 9) {
            let exported = try pixel(flat, x, y), shown = try pixel(editor, x, y, scale: scale)
            #expect(zip(exported, shown).allSatisfy { abs($0 - $1) < 0.03 }, "at \(x), \(y)")
        }
    }
    // Outside the region the stripes are untouched.
    #expect(try pixel(flat, 8, 50)[0] < 0.05)
    #expect(try pixel(flat, 10, 50)[0] > 0.95)
}

@Test func blurLeavesNoSharpDetail() throws {
    let region = CGRect(x: 40, y: 20, width: 120, height: 60)
    let doc = EditorDocument(base: stripes(width: 200, height: 100), annotations: [blur(region)])
    let flat = try #require(AnnotationRenderer.flatten(doc))
    // The 2 px stripes alternate between 0 and 1; under the blur they're a smooth grey.
    var largestStep: CGFloat = 0
    for x in stride(from: region.minX, to: region.maxX - 1, by: 1) {
        let step = abs(try pixel(flat, x, region.midY)[0] - pixel(flat, x + 1, region.midY)[0])
        largestStep = max(largestStep, step)
    }
    #expect(largestStep < 0.05)
    let middle = try pixel(flat, region.midX, region.midY)
    // Core Image mixes in linear light, so half black and half white is a light grey in sRGB.
    #expect(middle[0] > 0.5 && middle[0] < 0.9)
    #expect(middle[3] == 1)
}

@Test func blurStrengthGrowsWithTheRegionAndHasAFloor() {
    let small = AnnotationRenderer.blurRadius(for: CGRect(x: 0, y: 0, width: 200, height: 20))
    let large = AnnotationRenderer.blurRadius(for: CGRect(x: 0, y: 0, width: 800, height: 400))
    #expect(small >= 12)
    #expect(large > small)
}

@Test func aTinyBlurDrawsNothing() throws {
    let doc = EditorDocument(base: solidImage(width: 100, height: 100), annotations: [blur(CGRect(x: 10, y: 10, width: 0.2, height: 0.2))])
    let image = try #require(AnnotationRenderer.flatten(doc))
    #expect(image.width == 100)
}

@Test func aBlurPastTheImageGrowsTheCanvasAndExportsOpaque() throws {
    var doc = EditorDocument(base: solidImage(width: 100, height: 100))
    let a = blur(CGRect(x: 60, y: 20, width: 80, height: 40))
    doc.annotations.append(a)
    doc.grow(toFit: a, margin: 8)
    #expect(doc.canvasRect.maxX == 148)
    let image = try #require(AnnotationRenderer.flatten(doc))
    #expect(CGSize(width: image.width, height: image.height) == doc.exportSize)
    // Like pixelate, the part over the padding repeats the image's edge rather than leaving a hole.
    #expect(try pixel(image, 120, 40)[3] == 1)
    #expect(try pixel(image, 120, 70)[3] == 0)
}
