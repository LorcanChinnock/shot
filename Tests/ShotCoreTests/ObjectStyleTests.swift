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

private func placed(_ rect: CGRect, grey: CGFloat = 0.5) -> Annotation {
    Annotation(kind: .image(AnnotationImage(filled(width: Int(rect.width), height: Int(rect.height), grey: grey)), rect: rect), color: RGBA(0, 0, 0), lineWidth: 0)
}

private let soft = ShadowPreset.soft.shadow(scale: 1)

/// Renders `doc` at `scale` the way the editor view does: a context scaled up from the export.
private func render(_ doc: EditorDocument, scale: CGFloat) throws -> CGImage {
    let size = doc.exportSize
    let ctx = try #require(CGContext(
        data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    ctx.scaleBy(x: scale, y: scale)
    AnnotationRenderer.render(doc, into: ctx)
    return try #require(ctx.makeImage())
}

/// The pixel at (`x`, `y`) of the export, top-left origin, as fractions; the image is `scale` times the export.
private func pixel(_ image: CGImage, _ x: CGFloat, _ y: CGFloat, scale: CGFloat = 1) throws -> [CGFloat] {
    let data = try #require(image.dataProvider?.data as Data?)
    let offset = Int(y * scale) * image.bytesPerRow + Int(x * scale) * 4
    return data[offset..<offset + 4].map { CGFloat($0) / 255 }
}

@Test func anAnnotationSavedBeforeStylesDecodesUnchanged() throws {
    let json = #"{"id":"9F0C1E2A-3B4C-4D5E-8F60-718293A4B5C6","kind":{"arrow":{"from":[0,0],"to":[10,10]}},"color":{"r":1,"g":0,"b":0,"a":1},"lineWidth":4}"#
    let decoded = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
    #expect(decoded.style.isEmpty)
    #expect(decoded.cornerRadius == nil)
    // An unstyled annotation saves as it did before styles, so older versions still read it.
    let saved = try #require(String(data: JSONEncoder().encode(decoded), encoding: .utf8))
    #expect(!saved.contains("objectStyle"))
}

@Test func aStyledImageRoundTripsThroughTheClipboard() throws {
    var image = placed(CGRect(x: 10, y: 10, width: 40, height: 30))
    image.style = ObjectStyle(shadow: ShadowPreset.glow.shadow(scale: 2), border: .hairline)
    image.cornerRadius = 8
    let decoded = try AnnotationClipboard.annotation(from: AnnotationClipboard.data(for: image))
    #expect(decoded == image)
    #expect(decoded.style == image.style)
    #expect(decoded.cornerRadius == 8)
}

@Test func anEmptyStyleIsNotStored() {
    var image = placed(CGRect(x: 0, y: 0, width: 10, height: 10))
    let plain = image
    image.style = ObjectStyle(border: .hairline)
    image.style = ObjectStyle()
    #expect(image == plain)
}

@Test func presetsArePointsInOneSpaceAndASliderMakesThemCustom() {
    for preset in ShadowPreset.allCases {
        #expect(ShadowPreset.matching(preset.shadow(scale: 2), scale: 2) == preset)
    }
    var custom = ShadowPreset.soft.shadow(scale: 2)
    custom.elevation += 1
    #expect(ShadowPreset.matching(custom, scale: 2) == nil)
    #expect(ShadowPreset.glow.shadow(scale: 1).tint == .object)
    #expect(!ShadowPreset.glow.shadow(scale: 1).isOffset)
    // Layers fall and blur twice as far as the one before.
    #expect(soft.layers.map(\.offset) == [3, 6, 12])
    #expect(soft.layers.map(\.blur) == [6, 12, 24])
}

@Test func theShadowTakesItsTintFromTheBackground() {
    #expect(soft.color(background: nil, object: RGBA(1, 0, 0)) == RGBA(0, 0, 0))
    let tinted = soft.color(background: RGBA(0, 0.48, 1), object: RGBA(1, 0, 0))
    // Darker than the background, still leaning to its hue, and greyer.
    #expect(tinted.b > tinted.r && tinted.b < 0.5)
    #expect((tinted.b - tinted.r) / tinted.b < 0.9)
    #expect(ShadowPreset.glow.shadow(scale: 1).color(background: RGBA(1, 1, 1), object: RGBA(1, 0, 0, 0.5)) == RGBA(1, 0, 0))
}

@Test func paintedBoundsIncludeTheShadowAndBorder() {
    var image = placed(CGRect(x: 100, y: 100, width: 50, height: 50))
    #expect(image.paintedBounds == image.bounds)
    image.style = ObjectStyle(border: .hairline)
    #expect(image.paintedBounds == CGRect(x: 99, y: 99, width: 52, height: 52))
    // Soft reaches 12 above, 24 to each side and 36 below, since it falls below the object.
    image.style = ObjectStyle(shadow: soft, border: .hairline)
    #expect(image.paintedBounds == CGRect(x: 76, y: 88, width: 98, height: 98))
    var glow = ShadowPreset.glow.shadow(scale: 1)
    glow.elevation = 10
    image.style = ObjectStyle(shadow: glow)
    #expect(image.paintedBounds == CGRect(x: 80, y: 80, width: 90, height: 90))
}

@Test func aCaptureShadowGrowsTheCanvasJustEnoughAndShrinksBackWithout() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    doc.setStyle(ObjectStyle(shadow: soft), of: .capture, margin: 16)
    #expect(doc.canvasRect == CGRect(x: -24, y: -12, width: 248, height: 148))
    #expect(doc.canvasRect == doc.capturePaintedBounds)
    doc.setStyle(ObjectStyle(border: .hairline), of: .capture, margin: 16)
    #expect(doc.canvasRect == CGRect(x: -1, y: -1, width: 202, height: 102))
    doc.setStyle(ObjectStyle(), of: .capture, margin: 16)
    #expect(doc.canvasRect == doc.fullRect)
}

@Test func aCaptureShadowKeepsACropAndLeavesRoomForAnnotations() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    doc.crop(to: CGRect(x: 20, y: 0, width: 180, height: 100))
    doc.setStyle(ObjectStyle(shadow: soft), of: .capture, margin: 16)
    // The cropped left edge stays; the others grow.
    #expect(doc.canvasRect == CGRect(x: 20, y: -12, width: 204, height: 148))

    var padded = EditorDocument(base: solidImage(width: 200, height: 100))
    padded.paste(placed(CGRect(x: 190, y: 40, width: 100, height: 20)), step: 0, margin: 16)
    let wide = padded.canvasRect
    padded.setStyle(ObjectStyle(shadow: soft), of: .capture, margin: 16)
    #expect(padded.canvasRect.maxX == wide.maxX)
    #expect(padded.canvasRect.minY == -12)
}

@Test func fittingAndTrimmingTheCanvasKeepTheCaptureShadow() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    doc.setStyle(ObjectStyle(shadow: soft), of: .capture, margin: 16)
    doc.trimToImage()
    #expect(doc.canvasRect == doc.capturePaintedBounds)
    doc.canvasRect = doc.fullRect
    doc.fitToContent(margin: 16)
    #expect(doc.canvasRect == doc.capturePaintedBounds)
}

@Test func undoRestoresTheCaptureStyle() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    let before = doc.snapshot
    doc.setStyle(ObjectStyle(shadow: soft), of: .capture, margin: 16)
    doc.setCornerRadius(12, of: .capture)
    #expect(doc.snapshot != before)
    doc.restore(before)
    #expect(doc.captureStyle.isEmpty)
    #expect(doc.captureCornerRadius == 0)
    #expect(doc.canvasRect == doc.fullRect)
}

@Test func onlyImagesTakeAStyle() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [
        Annotation(kind: .shape(.rectangle, rect: CGRect(x: 10, y: 10, width: 20, height: 20)), color: RGBA(1, 0, 0), lineWidth: 2),
        placed(CGRect(x: 40, y: 10, width: 20, height: 20)),
    ])
    let shape = doc.annotations[0].id, image = doc.annotations[1].id
    doc.setStyle(ObjectStyle(border: .hairline), of: .annotation(shape), margin: 16)
    doc.setCornerRadius(4, of: .annotation(shape))
    doc.setStyle(ObjectStyle(border: .hairline), of: .annotation(image), margin: 16)
    doc.setCornerRadius(4, of: .annotation(image))
    #expect(doc.annotations[0].style.isEmpty && doc.annotations[0].cornerRadius == nil)
    #expect(doc.style(of: .annotation(image)) == ObjectStyle(border: .hairline))
    #expect(doc.cornerRadius(of: .annotation(image)) == 4)
    #expect(doc.annotations[1].imageCornerRadius == 4)
}

@Test func pasteAndDuplicateKeepTheStyle() throws {
    var image = placed(CGRect(x: 10, y: 10, width: 40, height: 30))
    image.style = ObjectStyle(shadow: ShadowPreset.float.shadow(scale: 1), border: .hairline)
    image.cornerRadius = 6
    var doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [image])
    // Duplicating pastes a copy of the annotation in the document; pasting one from the clipboard decodes it first.
    let duplicate = doc.paste(image, step: 10, margin: 16)
    let pasted = doc.paste(try AnnotationClipboard.annotation(from: AnnotationClipboard.data(for: image)), step: 10, margin: 16)
    for id in [duplicate, pasted] {
        let copy = try #require(doc.annotations.first { $0.id == id })
        #expect(copy.style == image.style)
        #expect(copy.cornerRadius == 6)
    }
}

@Test(arguments: [1.0, 2.0])
func aShadowFallsBelowTheObjectAndNotAbove(scale: CGFloat) throws {
    let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
    var image = placed(rect, grey: 0.5)
    image.style = ObjectStyle(shadow: soft)
    let doc = EditorDocument(base: filled(width: 300, height: 300, grey: 1), annotations: [image])
    let rendered = try render(doc, scale: scale)
    // Past the top of its reach there's no shadow at all, while as far below it's still there.
    let above = try pixel(rendered, 150, rect.minY - 20, scale: scale)
    let below = try pixel(rendered, 150, rect.maxY + 20, scale: scale)
    #expect(above[0] > 0.99)
    #expect(below[0] < 0.99)
    // Just outside the sides, it's lighter than below.
    let side = try pixel(rendered, rect.maxX + 4, 150, scale: scale), justBelow = try pixel(rendered, 150, rect.maxY + 4, scale: scale)
    #expect(side[0] > justBelow[0])
    // The object itself is drawn once, unchanged, over its shadow.
    let inside = try pixel(rendered, 150, 150, scale: scale)
    #expect(abs(inside[0] - 0.5) < 0.01 && inside[3] == 1)
    if scale == 1 {
        let flat = try #require(AnnotationRenderer.flatten(doc))
        #expect(try pixel(flat, 150, rect.maxY + 20) == below)
    }
}

@Test func aCaptureShadowIsBakedIntoATransparentExport() throws {
    var doc = EditorDocument(base: filled(width: 100, height: 60, grey: 1))
    doc.setStyle(ObjectStyle(shadow: soft), of: .capture, margin: 16)
    doc.setCornerRadius(10, of: .capture)
    let flat = try #require(AnnotationRenderer.flatten(doc))
    #expect(flat.width == 148 && flat.height == 108)
    let origin = doc.canvasRect.origin
    func at(_ x: CGFloat, _ y: CGFloat) throws -> [CGFloat] { try pixel(flat, x - origin.x, y - origin.y) }
    // Black shadow on a clear canvas, deeper below the image than above it.
    let below = try at(50, 66)
    #expect(below[3] > 0.02 && below[0] < 0.01)
    #expect(try at(50, -6)[3] < below[3])
    // A rounded corner is cut away, with only shadow behind it.
    let corner = try at(0.5, 0.5)
    #expect(corner[3] < 0.5)
    #expect(try at(50, 30) == [1, 1, 1, 1])
}

@Test func theHairlineFlipsWithTheContent() throws {
    func rim(grey: CGFloat) throws -> [CGFloat] {
        var doc = EditorDocument(base: filled(width: 60, height: 40, grey: grey))
        doc.setStyle(ObjectStyle(border: .hairline), of: .capture, margin: 16)
        let flat = try #require(AnnotationRenderer.flatten(doc))
        #expect(flat.width == 62 && flat.height == 42)
        // The rim is the pixel just outside the left edge, over the clear canvas.
        return try pixel(flat, 0, 20)
    }
    let onLight = try rim(grey: 0.95), onDark = try rim(grey: 0.1)
    #expect(onLight[3] > 0.05 && onDark[3] > 0.05)
    // Premultiplied: a dark rim has no colour, a light one has as much as its alpha.
    #expect(onLight[0] < 0.01)
    #expect(onDark[0] > onDark[3] * 0.8)
}

@Test func aBlurOverARoundedCornerDoesNotBringTheCornerBack() throws {
    var doc = EditorDocument(base: filled(width: 400, height: 400, grey: 0))
    doc.setCornerRadius(100, of: .capture)
    doc.annotations = [Annotation(kind: .blur(CGRect(x: 0, y: 0, width: 200, height: 200), amount: Redaction.amounts.upperBound), color: RGBA(0, 0, 0), lineWidth: 4)]
    let flat = try #require(AnnotationRenderer.flatten(doc))
    let corner = try pixel(flat, 3, 3)
    #expect(corner[3] < 0.05)
    #expect(try pixel(flat, 150, 150)[3] == 1)
}
