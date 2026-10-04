import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let black = RGBA(0, 0, 0)

/// Columns of alternating colours 1 px wide, `a` at even x and `b` at odd x: any resampling smears them.
private func columns(width: Int, height: Int, _ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat)) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for x in 0..<width {
        let c = x.isMultiple(of: 2) ? a : b
        ctx.setFillColor(CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1))
        ctx.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }
    return ctx.makeImage()!
}

private func image(_ image: CGImage, in rect: CGRect) -> Annotation {
    Annotation(kind: .image(AnnotationImage(image), rect: rect), color: black, lineWidth: 0)
}

/// The pixel at (`x`, `y`), top-left origin, as bytes.
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
    let data = try #require(image.dataProvider?.data as Data?)
    let offset = y * image.bytesPerRow + x * 4
    return Array(data[offset..<offset + 4])
}

private func near(_ p: [UInt8], _ r: UInt8, _ g: UInt8, _ b: UInt8, tolerance: Int = 3) -> Bool {
    abs(Int(p[0]) - Int(r)) <= tolerance && abs(Int(p[1]) - Int(g)) <= tolerance && abs(Int(p[2]) - Int(b)) <= tolerance && p[3] == 255
}

private func storage(_ annotation: Annotation) -> AnnotationImage? {
    if case let .image(stored, _) = annotation.kind {
        return stored
    }
    return nil
}

// MARK: Shape

@Test func anImageIsAFilledBoxThatMoves() {
    let rect = CGRect(x: 10, y: 20, width: 60, height: 30)
    var a = image(solidImage(width: 60, height: 30), in: rect)
    #expect(a.bounds == rect)
    #expect(a.paintedBounds == rect)
    #expect(a.hitTest(CGPoint(x: 40, y: 35), tolerance: 0))
    #expect(!a.hitTest(CGPoint(x: 100, y: 35), tolerance: 0))
    let stored = storage(a)
    a.offset(by: CGVector(dx: 5, dy: -5))
    #expect(a.bounds == CGRect(x: 15, y: 15, width: 60, height: 30))
    // Moving never copies the pixels.
    #expect(storage(a) === stored)
}

@Test func anImageHasHandlesOnItsCornersOnly() {
    let a = image(solidImage(width: 200, height: 100), in: CGRect(x: 100, y: 100, width: 200, height: 100))
    #expect(a.handles.map(\.handle) == [.topLeft, .topRight, .bottomRight, .bottomLeft])
    #expect(a.handles.map(\.point) == [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 300, y: 200), CGPoint(x: 100, y: 200)])
}

@Test func resizingAnImageKeepsItsAspectRatioAndTheOppositeCorner() {
    let start = image(solidImage(width: 200, height: 100), in: CGRect(x: 100, y: 100, width: 200, height: 100))

    // The corner follows whichever axis was dragged further, so the image grows by the larger factor.
    var a = start
    a.resize(.bottomRight, to: CGPoint(x: 500, y: 220))
    #expect(a.bounds == CGRect(x: 100, y: 100, width: 400, height: 200))

    var b = start
    b.resize(.topLeft, to: CGPoint(x: 250, y: 150))
    #expect(b.bounds == CGRect(x: 200, y: 150, width: 100, height: 50))

    var c = start
    c.resize(.bottomLeft, to: CGPoint(x: 0, y: 150))
    #expect(c.bounds == CGRect(x: 0, y: 100, width: 300, height: 150))

    var d = start
    d.resize(.topRight, to: CGPoint(x: 400, y: 0))
    #expect(d.bounds == CGRect(x: 100, y: 0, width: 400, height: 200))
}

@Test func anImageNeverFlipsOrVanishesAndIgnoresEdgeHandles() {
    let start = image(solidImage(width: 200, height: 100), in: CGRect(x: 100, y: 100, width: 200, height: 100))
    var a = start
    a.resize(.bottomRight, to: CGPoint(x: 0, y: 0))
    #expect(a.bounds.origin == CGPoint(x: 100, y: 100))
    #expect(a.bounds.width >= AnnotationImage.minSide && a.bounds.height >= AnnotationImage.minSide)
    #expect(abs(a.bounds.width / a.bounds.height - 2) < 0.001)

    var b = start
    b.resize(.right, to: CGPoint(x: 600, y: 150))
    #expect(b == start)
}

// MARK: Placement

@Test func placementKeepsEverySourcePixel() {
    let image = solidImage(width: 300, height: 200)
    // The same density as the screenshot: one source pixel per canvas pixel.
    #expect(EditorDocument.placementSize(of: image, scale: 2, documentScale: 2) == CGSize(width: 300, height: 200))
    // A 1× image on a 2× screenshot shows at the same size in points, so each pixel covers 2 × 2.
    #expect(EditorDocument.placementSize(of: image, scale: 1, documentScale: 2) == CGSize(width: 600, height: 400))
    // A 2× image on a 1× screenshot isn't shrunk to match, which would throw pixels away.
    #expect(EditorDocument.placementSize(of: image, scale: 2, documentScale: 1) == CGSize(width: 300, height: 200))
}

@Test func aPastedImageGoesBesideTheCanvasTopAligned() {
    var doc = EditorDocument(base: solidImage(width: 400, height: 300))
    #expect(doc.rectBesideCanvas(CGSize(width: 100, height: 50), gap: 16) == CGRect(x: 416, y: 0, width: 100, height: 50))

    // Padding on the left and top moves the canvas; the next image still lines up with it.
    doc.canvasRect = CGRect(x: -20, y: -10, width: 500, height: 320)
    #expect(doc.rectBesideCanvas(CGSize(width: 100, height: 50), gap: 16) == CGRect(x: 496, y: -10, width: 100, height: 50))
}

@Test func aPastedImageAvoidsACroppedEdge() {
    var doc = EditorDocument(base: solidImage(width: 400, height: 300))
    // The right edge is a crop, which never grows, so the image goes below.
    doc.crop(to: CGRect(x: 0, y: 0, width: 300, height: 300))
    #expect(doc.rectBesideCanvas(CGSize(width: 100, height: 50), gap: 16) == CGRect(x: 0, y: 316, width: 100, height: 50))
    // Cropped on both, it's centred on the canvas.
    doc.crop(to: CGRect(x: 0, y: 0, width: 300, height: 200))
    #expect(doc.rectBesideCanvas(CGSize(width: 100, height: 50), gap: 16) == CGRect(x: 100, y: 75, width: 100, height: 50))
}

@Test func addingAnImageBesideTheCanvasGrowsItToFit() throws {
    var doc = EditorDocument(base: solidImage(width: 400, height: 300))
    let id = doc.addImage(solidImage(width: 300, height: 500), scale: 2, documentScale: 2, centeredAt: nil, margin: 16)
    let added = try #require(doc.annotations.last)
    #expect(added.id == id)
    #expect(added.bounds == CGRect(x: 416, y: 0, width: 300, height: 500))
    #expect(doc.canvasRect == CGRect(x: 0, y: 0, width: 732, height: 516))
}

@Test func aDroppedImageIsCentredOnTheDropOnWholePixels() throws {
    var doc = EditorDocument(base: solidImage(width: 400, height: 300))
    doc.addImage(solidImage(width: 101, height: 51), scale: 1, documentScale: 1, centeredAt: CGPoint(x: 200.3, y: 150.2), margin: 16)
    let added = try #require(doc.annotations.last)
    #expect(added.bounds == CGRect(x: 150, y: 125, width: 101, height: 51))
    // Inside the screenshot, the canvas stays as it was.
    #expect(doc.canvasRect == doc.fullRect)

    doc.addImage(solidImage(width: 100, height: 100), scale: 1, documentScale: 1, centeredAt: CGPoint(x: 390, y: 150), margin: 16)
    #expect(doc.canvasRect == CGRect(x: 0, y: 0, width: 456, height: 300))
}

// MARK: Memory

@Test func copiesAndUndoStepsShareTheImageRatherThanCopyingIt() throws {
    var doc = EditorDocument(base: solidImage(width: 400, height: 300))
    doc.addImage(solidImage(width: 300, height: 200), scale: 1, documentScale: 1, centeredAt: nil, margin: 16)
    let original = try #require(doc.annotations.last)
    let snapshot = doc.snapshot
    doc.paste(original, step: 10, margin: 16)
    let copy = try #require(doc.annotations.last)
    #expect(copy.id != original.id)
    #expect(storage(copy) === storage(original))
    #expect(storage(snapshot.annotations[0]) === storage(original))
    // Comparing snapshots, as every edit does, doesn't read the pixels: the same image is equal by identity.
    #expect(doc.snapshot != snapshot)
    doc.restore(snapshot)
    #expect(doc.snapshot == snapshot)
}

@Test func anImageSurvivesTheClipboard() throws {
    let source = columns(width: 30, height: 20, (1, 0, 0), (0, 0, 1))
    let a = image(source, in: CGRect(x: 5, y: 6, width: 30, height: 20))
    let decoded = try AnnotationClipboard.annotation(from: AnnotationClipboard.data(for: a))
    #expect(decoded == a)
    let stored = try #require(storage(decoded))
    #expect(stored.image.width == 30 && stored.image.height == 20)
    #expect(near(try pixel(stored.image, 0, 0), 255, 0, 0))
    #expect(near(try pixel(stored.image, 1, 0), 0, 0, 255))
}

@Test func imageDataDecodesWithItsScale() throws {
    let data = try #require(ImageCodec.data(from: solidImage(width: 30, height: 20), scale: 2))
    let decoded = try #require(ImageCodec.image(from: data))
    #expect(decoded.width == 30 && decoded.height == 20)
    #expect(ImageCodec.scale(of: data) == 2)
    #expect(ImageCodec.image(from: Data("not an image".utf8)) == nil)
}

// MARK: Export

@Test func twoScreenshotsExportAsOnePNGAtFullResolution() throws {
    // Two 2× screenshots, as from a Retina display. The second's 1 px columns show any resampling.
    var doc = EditorDocument(base: solidImage(width: 400, height: 300))
    let second = columns(width: 300, height: 200, (0, 0, 1), (0, 1, 0))
    doc.addImage(second, scale: 2, documentScale: 2, centeredAt: nil, margin: 16)

    let flat = try #require(AnnotationRenderer.flatten(doc))
    let png = try #require(ImageCodec.data(from: flat, scale: 2))
    let exported = try #require(ImageCodec.image(from: png))
    #expect(ImageCodec.scale(of: png) == 2)
    #expect(exported.width == 400 + 16 + 300 + 16)
    #expect(exported.height == 300)

    // The first screenshot, untouched.
    #expect(near(try pixel(exported, 0, 0), 255, 0, 0))
    #expect(near(try pixel(exported, 399, 299), 255, 0, 0))
    // The second, pixel for pixel, at its top-left, its far corner and in between.
    for (x, y) in [(0, 0), (1, 0), (2, 100), (151, 100), (298, 199), (299, 199)] {
        let p = try pixel(exported, 416 + x, y)
        #expect(x.isMultiple(of: 2) ? near(p, 0, 0, 255) : near(p, 0, 255, 0), "(\(x), \(y)): \(p)")
    }
    // The gap beside it and the padding below it are transparent.
    #expect(try pixel(exported, 408, 10)[3] == 0)
    #expect(try pixel(exported, 500, 250)[3] == 0)
}

@Test func aMovedImageStillExportsPixelForPixel() throws {
    var doc = EditorDocument(base: solidImage(width: 100, height: 100))
    let id = doc.addImage(columns(width: 40, height: 40, (0, 0, 1), (0, 1, 0)), scale: 1, documentScale: 1, centeredAt: CGPoint(x: 50, y: 50), margin: 16)
    // A drag at a zoom below 100% moves by fractions of a pixel.
    doc.move(id, by: CGVector(dx: 0.4, dy: 0.3), margin: 16)
    let flat = try #require(AnnotationRenderer.flatten(doc))
    #expect(near(try pixel(flat, 30, 30), 0, 0, 255))
    #expect(near(try pixel(flat, 31, 30), 0, 255, 0))
}

@Test func aLowerDensityImageIsScaledUpToMatch() throws {
    var doc = EditorDocument(base: solidImage(width: 400, height: 300))
    let blue = columns(width: 50, height: 50, (0, 0, 1), (0, 0, 1))
    doc.addImage(blue, scale: 1, documentScale: 2, centeredAt: nil, margin: 16)
    let flat = try #require(AnnotationRenderer.flatten(doc))
    #expect(flat.width == 400 + 16 + 100 + 16)
    #expect(near(try pixel(flat, 416 + 99, 99), 0, 0, 255))
}

@Test func laterImagesDrawOverEarlierOnes() throws {
    var doc = EditorDocument(base: solidImage(width: 100, height: 100))
    doc.annotations = [
        image(columns(width: 40, height: 40, (0, 0, 1), (0, 0, 1)), in: CGRect(x: 10, y: 10, width: 40, height: 40)),
        image(columns(width: 40, height: 40, (0, 1, 0), (0, 1, 0)), in: CGRect(x: 30, y: 30, width: 40, height: 40)),
    ]
    let flat = try #require(AnnotationRenderer.flatten(doc))
    #expect(near(try pixel(flat, 20, 20), 0, 0, 255))
    #expect(near(try pixel(flat, 40, 40), 0, 255, 0))
}

@Test(arguments: [Annotation.Kind.pixelate(CGRect(x: 120, y: 10, width: 60, height: 40)), .blur(CGRect(x: 120, y: 10, width: 60, height: 40))])
func redactingOverAPlacedImageHidesItsDetail(kind: Annotation.Kind) throws {
    // The image sits in the padding, where the screenshot has no pixels to sample.
    var doc = EditorDocument(base: solidImage(width: 100, height: 100))
    doc.addImage(columns(width: 100, height: 60, (0, 0, 0), (1, 1, 1)), scale: 1, documentScale: 1, centeredAt: nil, margin: 16)
    doc.annotations.append(Annotation(kind: kind, color: black, lineWidth: 4))
    let flat = try #require(AnnotationRenderer.flatten(doc))
    // Outside the redaction, the columns are sharp.
    #expect(near(try pixel(flat, 116, 55), 0, 0, 0))
    #expect(near(try pixel(flat, 117, 55), 255, 255, 255))
    // Inside it, neighbouring columns run together, and the image is still there rather than the empty padding.
    for x in [140, 150, 160] {
        let p = try pixel(flat, x, 30), q = try pixel(flat, x + 1, 30)
        #expect(p[3] == 255 && q[3] == 255, "\(x): \(p) \(q)")
        #expect(abs(Int(p[0]) - Int(q[0])) < 40, "\(x): \(p) \(q)")
        // Grey, from the image's black and white, not the red screenshot's edge stretched out.
        #expect(abs(Int(p[0]) - Int(p[1])) < 10 && abs(Int(p[1]) - Int(p[2])) < 10, "\(x): \(p)")
    }
}

@Test func autoRedactReadsThePlacedImagesToo() throws {
    var doc = EditorDocument(base: solidImage(width: 100, height: 100))
    #expect(doc.redactionSource.image === doc.base)
    #expect(doc.redactionSource.origin == .zero)

    // One image beside the screenshot and one over its top-left corner, reaching past it.
    doc.addImage(columns(width: 50, height: 120, (0, 0, 1), (0, 0, 1)), scale: 1, documentScale: 1, centeredAt: nil, margin: 16)
    doc.addImage(columns(width: 40, height: 40, (0, 1, 0), (0, 1, 0)), scale: 1, documentScale: 1, centeredAt: CGPoint(x: 0, y: 0), margin: 16)
    let source = doc.redactionSource
    #expect(source.origin == CGPoint(x: -20, y: -20))
    #expect(source.image.width == 186 && source.image.height == 140)
    // The screenshot, each image, and the screenshot hidden under the second image.
    #expect(near(try pixel(source.image, 70, 70), 255, 0, 0))
    #expect(near(try pixel(source.image, 140, 70), 0, 0, 255))
    #expect(near(try pixel(source.image, 25, 25), 0, 255, 0))
}

@Test func aSpotlightDimsAPlacedImageOutsideIt() throws {
    var doc = EditorDocument(base: solidImage(width: 100, height: 100))
    doc.addImage(columns(width: 100, height: 100, (1, 1, 1), (1, 1, 1)), scale: 1, documentScale: 1, centeredAt: nil, margin: 16)
    doc.annotations.append(Annotation(kind: .spotlight(CGRect(x: 120, y: 0, width: 40, height: 40)), color: black, lineWidth: 4))
    let dim = try #require(doc.spotlightDimPath)
    #expect(dim.contains(CGPoint(x: 180, y: 80)))
    #expect(!dim.contains(CGPoint(x: 130, y: 20)))
    // The gap between the screenshot and the image isn't dimmed.
    #expect(!dim.contains(CGPoint(x: 108, y: 50)))
    let flat = try #require(AnnotationRenderer.flatten(doc))
    #expect(near(try pixel(flat, 130, 20), 255, 255, 255))
    #expect(near(try pixel(flat, 180, 80), 128, 128, 128, tolerance: 8))
}
