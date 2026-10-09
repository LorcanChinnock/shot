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

/// A clear square with an opaque disc in the middle, like a cut-out sticker.
private func disc(side: Int, radius: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    let centre = CGFloat(side) / 2
    ctx.fillEllipse(in: CGRect(x: centre - radius, y: centre - radius, width: radius * 2, height: radius * 2))
    return ctx.makeImage()!
}

private func sticker(_ rect: CGRect, radius: CGFloat) -> Annotation {
    Annotation(kind: .image(AnnotationImage(disc(side: Int(rect.width), radius: radius)), rect: rect), color: RGBA(0, 0, 0), lineWidth: 0)
}

private func arrow(from: CGPoint, to: CGPoint, color: RGBA = RGBA(1, 0, 0)) -> Annotation {
    Annotation(kind: .arrow(from: from, to: to), color: color, lineWidth: 4)
}

private func text(_ string: String, at origin: CGPoint, color: RGBA = RGBA(1, 0, 0)) -> Annotation {
    Annotation(kind: .text(string, origin: origin, fontSize: 40), color: color, lineWidth: 4)
}

/// How many pixels of `image` `matches` picks.
private func count(_ image: CGImage, where matches: ([CGFloat]) -> Bool) throws -> Int {
    let data = try #require(image.dataProvider?.data as Data?)
    var found = 0
    for y in 0..<image.height {
        for x in 0..<image.width {
            let offset = y * image.bytesPerRow + x * 4
            if matches(data[offset..<offset + 4].map { CGFloat($0) / 255 }) {
                found += 1
            }
        }
    }
    return found
}

@Test func aSolidBorderDrawsOutsideTheImageInItsColourWithConcentricCorners() throws {
    var doc = EditorDocument(base: filled(width: 60, height: 40, grey: 0.5))
    doc.setStyle(ObjectStyle(border: Border(kind: .solid, lineWidth: 4, color: RGBA(1, 0, 0))), of: .capture, margin: 16)
    doc.setCornerRadius(10, of: .capture)
    #expect(doc.canvasRect == CGRect(x: -4, y: -4, width: 68, height: 48))
    let flat = try #require(AnnotationRenderer.flatten(doc))
    func at(_ x: CGFloat, _ y: CGFloat) throws -> [CGFloat] { try pixel(flat, x + 4, y + 4) }
    // The border is red all the way out, beside the image and not over it.
    #expect(try at(-2, 20) == [1, 0, 0, 1])
    #expect(try at(-3.5, 20) == [1, 0, 0, 1])
    let inside = try at(30, 20)
    #expect(abs(inside[0] - 0.5) < 0.01 && inside[3] == 1)
    // Its outer corner is rounded by the image's radius plus its width, so the canvas corner stays clear while the
    // border still runs along each side up to the curve.
    #expect(try at(-3.5, -3.5)[3] == 0)
    #expect(try at(-3.5, 10) == [1, 0, 0, 1])
    // No seam shows between the border and the image along the edge.
    #expect(try at(-0.5, 20)[3] == 1)
}

@Test func theOutlineFollowsTheAlphaEdge() throws {
    let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
    var image = sticker(rect, radius: 30)
    #expect(image.hasTransparency)
    image.style = ObjectStyle(border: Border(kind: .outline, lineWidth: 8, color: RGBA(1, 1, 1)))
    #expect(image.paintedBounds == rect.insetBy(dx: -8, dy: -8))
    let doc = EditorDocument(base: filled(width: 300, height: 300, grey: 0), annotations: [image])
    let flat = try #require(AnnotationRenderer.flatten(doc))
    // The disc, centred at (150, 150), keeps its colour; just past its edge is the outline; past the outline, the screenshot.
    #expect(try pixel(flat, 150, 150) == [0, 0, 1, 1])
    #expect(try pixel(flat, 150 + 34, 150) == [1, 1, 1, 1])
    #expect(try pixel(flat, 150, 150 - 34) == [1, 1, 1, 1])
    #expect(try pixel(flat, 150 + 42, 150) == [0, 0, 0, 1])
    // It follows the disc, not the image's square: its corners are still the screenshot.
    #expect(try pixel(flat, 104, 104) == [0, 0, 0, 1])
}

@Test func anOpaqueImageTakesNoOutline() throws {
    var doc = EditorDocument(base: filled(width: 200, height: 100, grey: 0.5), annotations: [placed(CGRect(x: 10, y: 10, width: 40, height: 30))])
    let image = try #require(doc.annotations.first?.id)
    #expect(!doc.hasTransparency(of: .annotation(image)))
    #expect(!doc.hasTransparency(of: .capture))
    let outline = ObjectStyle(border: Border(kind: .outline, lineWidth: 8, color: RGBA(1, 1, 1)))
    doc.setStyle(outline, of: .annotation(image), margin: 16)
    doc.setStyle(outline, of: .capture, margin: 16)
    #expect(doc.style(of: .annotation(image)).isEmpty)
    #expect(doc.captureStyle.isEmpty)
    #expect(doc.canvasRect == doc.fullRect)
    // What the popover offers: no outline on an opaque image, and only an outline on text.
    #expect(StyleKind.image.borders(transparent: false) == [.hairline, .solid])
    #expect(StyleKind.image.borders(transparent: true) == [.hairline, .solid, .outline])
    #expect(StyleKind.text.borders(transparent: false) == [.outline])
    #expect(StyleKind.mark.borders(transparent: true).isEmpty)
}

/// Whether `a` and `b` are the same rect but for rounding.
private func same(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 1e-9 && abs(a.minY - b.minY) < 1e-9 && abs(a.width - b.width) < 1e-9 && abs(a.height - b.height) < 1e-9
}

@Test func paintedBoundsGrowWithAMarksShadowAndGlowAndATextOutline() {
    var mark = arrow(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
    let plain = mark.paintedBounds
    mark.style = ObjectStyle(shadow: soft)
    // Soft reaches 12 above, 24 to each side and 36 below.
    #expect(same(mark.paintedBounds, CGRect(x: plain.minX - 24, y: plain.minY - 12, width: plain.width + 48, height: plain.height + 48)))
    mark.style = ObjectStyle(shadow: ShadowPreset.glow.shadow(scale: 1))
    #expect(same(mark.paintedBounds, plain.insetBy(dx: -20, dy: -20)))

    var label = text("Hi", at: CGPoint(x: 50, y: 50))
    let unstyled = label.paintedBounds
    label.style = ObjectStyle(border: Border(kind: .outline, lineWidth: 3, color: RGBA(1, 1, 1)))
    #expect(same(label.paintedBounds, unstyled.insetBy(dx: -3, dy: -3)))
    // The outline casts the shadow along with the letters.
    label.style.shadow = soft
    #expect(same(label.paintedBounds, CGRect(x: unstyled.minX - 27, y: unstyled.minY - 15, width: unstyled.width + 54, height: unstyled.height + 54)))
}

@Test func aMarksShadowFallsBelowItAndItsGlowTakesItsColour() throws {
    var line = Annotation(kind: .line(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 250, y: 100)), color: RGBA(1, 0, 0), lineWidth: 4)
    line.style = ObjectStyle(shadow: soft)
    var doc = EditorDocument(base: filled(width: 300, height: 200, grey: 1), annotations: [line])
    var flat = try #require(AnnotationRenderer.flatten(doc))
    // Darker below the line than as far above it, and the line itself drawn once over its shadow.
    #expect(try pixel(flat, 150, 120)[1] < 0.99)
    #expect(try pixel(flat, 150, 120)[1] < pixel(flat, 150, 80)[1])
    #expect(try pixel(flat, 150, 100) == [1, 0, 0, 1])

    doc.annotations[0].style = ObjectStyle(shadow: ShadowPreset.glow.shadow(scale: 1))
    doc.base = filled(width: 300, height: 200, grey: 0)
    flat = try #require(AnnotationRenderer.flatten(doc))
    // On black, the glow around the line, which spans 98 to 102, is red, evenly above and below.
    let above = try pixel(flat, 150, 94), below = try pixel(flat, 150, 105)
    #expect(above[0] > 0.05 && above[1] < 0.01 && above[2] < 0.01)
    #expect(abs(above[0] - below[0]) < 0.02)
}

@Test func aTextOutlineIsDrawnInItsOwnColourUnderTheLetters() throws {
    var label = text("Shot", at: CGPoint(x: 20, y: 20), color: RGBA(1, 0, 0))
    var doc = EditorDocument(base: filled(width: 200, height: 100, grey: 1), annotations: [label])
    func isBlue(_ p: [CGFloat]) -> Bool { p[2] > 0.9 && p[0] < 0.1 && p[1] < 0.1 }
    func isRed(_ p: [CGFloat]) -> Bool { p[0] > 0.9 && p[1] < 0.1 && p[2] < 0.1 }
    let plain = try #require(AnnotationRenderer.flatten(doc))
    #expect(try count(plain, where: isBlue) == 0)
    let red = try count(plain, where: isRed)
    label.style = ObjectStyle(border: Border(kind: .outline, lineWidth: 3, color: RGBA(0, 0, 1)))
    doc.annotations = [label]
    let outlined = try #require(AnnotationRenderer.flatten(doc))
    // Core Text strokes in the outline's colour, and the letters stay red over it, as many of them as before.
    #expect(try count(outlined, where: isBlue) > 200)
    #expect(try abs(count(outlined, where: isRed) - red) < red / 20)
}

@Test func pasteStyleAppliesOnlyTheFieldsTheTargetHas() throws {
    let solid = Border(kind: .solid, lineWidth: 8, color: RGBA(1, 0, 0))
    var source = placed(CGRect(x: 10, y: 10, width: 40, height: 30))
    source.style = ObjectStyle(shadow: ShadowPreset.float.shadow(scale: 2), border: solid)
    source.cornerRadius = 16
    var outlined = text("Hi", at: CGPoint(x: 100, y: 10))
    outlined.style = ObjectStyle(border: Border(kind: .outline, lineWidth: 2, color: RGBA(1, 1, 1)))
    var doc = EditorDocument(base: filled(width: 300, height: 200, grey: 0.5), annotations: [
        source, arrow(from: CGPoint(x: 10, y: 100), to: CGPoint(x: 60, y: 120)), outlined,
        Annotation(kind: .shape(.rounded, rect: CGRect(x: 100, y: 100, width: 40, height: 40)), color: RGBA(1, 0, 0), lineWidth: 4),
        Annotation(kind: .note("Note", rect: CGRect(x: 200, y: 100, width: 80, height: 40)), color: RGBA(1, 0.8, 0), lineWidth: 4),
        Annotation(kind: .blur(CGRect(x: 200, y: 10, width: 40, height: 40)), color: RGBA(0, 0, 0), lineWidth: 4),
    ])
    let ids = doc.annotations.map(\.id)
    doc.annotations[3].cornerRadius = 6
    let untouched = Array(doc.annotations[4...])
    let copied = try #require(doc.copyStyle(of: .annotation(ids[0]), scale: 2))
    // Copied in points: Float's 64 pixel elevation on a Retina image is 32 points, and the medium border 4.
    #expect(copied.style.shadow?.elevation == 32 && copied.style.border?.lineWidth == 4 && copied.cornerRadius == 8)
    doc.pasteStyle(copied, to: [.capture] + ids.dropFirst().map { .annotation($0) }, scale: 2, margin: 16)
    // The screenshot takes all of it.
    #expect(doc.captureStyle == source.style)
    #expect(doc.captureCornerRadius == 16)
    // A mark takes the shadow only, keeping its own corners.
    #expect(doc.annotations[1].style == ObjectStyle(shadow: source.style.shadow))
    #expect(doc.annotations[3].style == ObjectStyle(shadow: source.style.shadow))
    #expect(doc.annotations[3].cornerRadius == 6)
    // Text takes the shadow and keeps its outline, since it can't have a solid border.
    #expect(doc.annotations[2].style == ObjectStyle(shadow: source.style.shadow, border: outlined.style.border))
    // A note, and kinds Style is off for, are left alone.
    #expect(Array(doc.annotations[4...]) == untouched)

    // A medium text outline pasted on a cut-out image is the image's medium outline, and no border pasted on an image
    // removes its border; corners from text leave the image's alone.
    var target = sticker(CGRect(x: 0, y: 0, width: 60, height: 60), radius: 20)
    target.style = ObjectStyle(border: .hairline)
    target.cornerRadius = 4
    var scene = EditorDocument(base: filled(width: 100, height: 100, grey: 0.5), annotations: [target])
    scene.pasteStyle(CopiedStyle(style: ObjectStyle(border: Border(kind: .outline, lineWidth: 2, color: RGBA(0, 0, 0))), source: .text), to: [.annotation(target.id)], scale: 1, margin: 16)
    #expect(scene.annotations[0].style.border == Border(kind: .outline, lineWidth: 9, color: RGBA(0, 0, 0)))
    #expect(scene.annotations[0].cornerRadius == 4)
    scene.pasteStyle(CopiedStyle(style: ObjectStyle(shadow: soft), source: .image), to: [.annotation(target.id)], scale: 1, margin: 16)
    #expect(scene.annotations[0].style == ObjectStyle(shadow: soft))
    #expect(scene.annotations[0].cornerRadius == nil)
    // A mark has no border to paste, so the image keeps its.
    scene.annotations[0].style = ObjectStyle(border: .hairline)
    scene.pasteStyle(CopiedStyle(style: ObjectStyle(), source: .mark), to: [.annotation(target.id)], scale: 1, margin: 16)
    #expect(scene.annotations[0].style == ObjectStyle(border: .hairline))
}

@Test func pastingStyleOnAllImagesRestylesTheScreenshotAndEveryPlacedImage() {
    var doc = EditorDocument(base: filled(width: 300, height: 200, grey: 0.5), annotations: [
        placed(CGRect(x: 10, y: 10, width: 40, height: 30)), arrow(from: CGPoint(x: 10, y: 100), to: CGPoint(x: 60, y: 120)),
        placed(CGRect(x: 100, y: 10, width: 40, height: 30)),
    ])
    #expect(doc.imageStyleTargets == [.capture, .annotation(doc.annotations[0].id), .annotation(doc.annotations[2].id)])
    doc.pasteStyle(CopiedStyle(style: ObjectStyle(border: .hairline), cornerRadius: 6, source: .image), to: doc.imageStyleTargets, scale: 1, margin: 16)
    #expect(doc.captureStyle == ObjectStyle(border: .hairline) && doc.captureCornerRadius == 6)
    #expect(doc.annotations[0].style == ObjectStyle(border: .hairline) && doc.annotations[2].cornerRadius == 6)
    #expect(doc.annotations[1].style.isEmpty)
}

@Test func aBorderSavedBeforeSolidAndOutlineDecodesUnchanged() throws {
    let json = #"{"border":{"kind":"hairline"}}"#
    let decoded = try JSONDecoder().decode(ObjectStyle.self, from: Data(json.utf8))
    #expect(decoded == ObjectStyle(border: .hairline))
    // A hairline still saves as it did, so the version before still reads it.
    let saved = try #require(String(data: JSONEncoder().encode(decoded), encoding: .utf8))
    #expect(saved == json)
}

@Test func styledMarksAndTextRoundTripAndPasteAndDuplicateKeepTheirStyle() throws {
    var mark = arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 40))
    mark.style = ObjectStyle(shadow: ShadowPreset.glow.shadow(scale: 2))
    var label = text("Hi", at: CGPoint(x: 100, y: 10))
    label.style = ObjectStyle(shadow: soft, border: Border(kind: .outline, lineWidth: 4, color: RGBA(1, 1, 1)))
    var image = sticker(CGRect(x: 0, y: 50, width: 40, height: 40), radius: 12)
    image.style = ObjectStyle(border: Border(kind: .solid, lineWidth: 8, color: RGBA(0, 0.48, 1)))
    var doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [mark, label, image])
    for original in [mark, label, image] {
        let decoded = try AnnotationClipboard.annotation(from: AnnotationClipboard.data(for: original))
        #expect(decoded.style == original.style)
        let duplicate = doc.paste(original, step: 10, margin: 16)
        let pasted = doc.paste(decoded, step: 10, margin: 16)
        for id in [duplicate, pasted] {
            #expect(doc.annotations.first { $0.id == id }?.style == original.style)
        }
    }
}

@Test func notesAndTheKindsStyleIsOffForTakeNoStyle() {
    let kinds: [Annotation.Kind] = [
        .note("Note", rect: CGRect(x: 0, y: 0, width: 80, height: 40)), .blur(CGRect(x: 0, y: 0, width: 10, height: 10)),
        .pixelate(CGRect(x: 0, y: 0, width: 10, height: 10)), .spotlight(CGRect(x: 0, y: 0, width: 10, height: 10), style: SpotlightStyle()),
        .highlight(CGRect(x: 0, y: 0, width: 10, height: 10)), .marker([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]),
    ]
    var doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: kinds.map { Annotation(kind: $0, color: RGBA(1, 0, 0), lineWidth: 4) })
    for annotation in doc.annotations {
        #expect(annotation.styleKind == nil)
        doc.setStyle(ObjectStyle(shadow: soft), of: .annotation(annotation.id), margin: 16)
    }
    #expect(doc.annotations.allSatisfy { $0.style.isEmpty })
}

@Test func theLastStyleOfEachKindStartsAtNone() throws {
    #expect(EditorStyle().objectStyles.isEmpty)
    for kind in StyleKind.allCases {
        #expect(EditorStyle().objectStyle(for: kind, scale: 2).isEmpty)
    }
    let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }
    Preferences.registerDefaults(in: store)
    let prefs = Preferences(store: store)
    #expect(prefs.editorStyle.objectStyles.isEmpty)
    // Remembered in points, so a Retina document gets twice the pixels; the screenshot always starts plain.
    let glow = ShadowPreset.glow.shadow(scale: 1)
    var style = prefs.editorStyle
    style.objectStyles = [.mark: ObjectStyle(shadow: glow), .capture: ObjectStyle(border: .hairline)]
    Preferences.remember(style, in: store)
    #expect(prefs.editorStyle.objectStyles[.mark] == ObjectStyle(shadow: glow))
    #expect(prefs.editorStyle.objectStyle(for: .mark, scale: 2) == ObjectStyle(shadow: ShadowPreset.glow.shadow(scale: 2)))
    #expect(prefs.editorStyle.objectStyle(for: .text, scale: 2).isEmpty)
    #expect(prefs.editorStyle.objectStyle(for: .capture, scale: 2).isEmpty)
    Preferences.resetAll(in: store)
    #expect(prefs.editorStyle.objectStyles.isEmpty)
}
