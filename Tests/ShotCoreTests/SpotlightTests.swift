import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let blue = RGBA(0, 0, 1)

private func spotlight(_ rect: CGRect) -> Annotation {
    Annotation(kind: .spotlight(rect, style: SpotlightStyle()), color: blue, lineWidth: 4)
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

/// The pixel at canvas point (`x`, `y`), top-left origin, as 0...1 premultiplied components.
private func pixel(_ image: CGImage, _ x: CGFloat, _ y: CGFloat, scale: CGFloat = 1) throws -> [CGFloat] {
    let data = try #require(image.dataProvider?.data as Data?)
    let offset = Int(y * scale) * image.bytesPerRow + Int(x * scale) * 4
    return data[offset..<offset + 4].map { CGFloat($0) / 255 }
}

private func isDimmed(_ p: [CGFloat]) -> Bool { abs(p[0] - 0.5) < 0.03 && p[3] == 1 }
private func isBright(_ p: [CGFloat]) -> Bool { p[0] > 0.97 && p[3] == 1 }

// MARK: Shape

@Test func spotlightIsAFilledBoxThatMoves() {
    let rect = CGRect(x: 10, y: 10, width: 50, height: 20)
    var a = spotlight(rect)
    #expect(a.bounds == rect)
    #expect(a.paintedBounds == rect)
    #expect(a.hitTest(CGPoint(x: 30, y: 20), tolerance: 0))
    #expect(!a.hitTest(CGPoint(x: 100, y: 20), tolerance: 0))
    a.offset(by: CGVector(dx: 5, dy: -5))
    #expect(a.kind == .spotlight(CGRect(x: 15, y: 5, width: 50, height: 20), style: SpotlightStyle()))
}

// MARK: Dim area

@Test func noSpotlightMeansNoDim() {
    let doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [Annotation(kind: .shape(.rectangle, rect: CGRect(x: 10, y: 10, width: 20, height: 20)), color: blue, lineWidth: 4)])
    #expect(doc.spotlightDimPath == nil)
}

@Test func theDimCoversTheImageOutsideEverySpotlight() throws {
    let doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [
        spotlight(CGRect(x: 10, y: 10, width: 40, height: 40)),
        spotlight(CGRect(x: 30, y: 30, width: 40, height: 40)),
        spotlight(CGRect(x: 150, y: 20, width: 30, height: 30)),
    ])
    let dim = try #require(doc.spotlightDimPath)
    // Inside each spotlight, including where two overlap, nothing is dimmed.
    for point in [CGPoint(x: 15, y: 15), CGPoint(x: 40, y: 40), CGPoint(x: 65, y: 65), CGPoint(x: 160, y: 30)] {
        #expect(!dim.contains(point), "\(point)")
    }
    for point in [CGPoint(x: 5, y: 5), CGPoint(x: 100, y: 50), CGPoint(x: 60, y: 15), CGPoint(x: 195, y: 95)] {
        #expect(dim.contains(point), "\(point)")
    }
    #expect(dim.boundingBoxOfPath == doc.fullRect)
}

@Test func theDimStaysOnTheImageAndOffThePadding() throws {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [spotlight(CGRect(x: 150, y: 20, width: 100, height: 40))])
    doc.canvasRect = CGRect(x: -20, y: -20, width: 300, height: 140)
    let dim = try #require(doc.spotlightDimPath)
    #expect(dim.contains(CGPoint(x: 100, y: 50)))
    #expect(!dim.contains(CGPoint(x: -10, y: 50)))
    #expect(!dim.contains(CGPoint(x: 260, y: 90)))
    #expect(!dim.contains(CGPoint(x: 220, y: 40)))
}

@Test func aSpotlightWithNoAreaDimsNothing() throws {
    // A straight drag, or a resize down to a line, mustn't darken the whole image.
    var doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [spotlight(CGRect(x: 50, y: 10, width: 0, height: 50))])
    #expect(doc.spotlightDimPath == nil)
    doc.annotations.append(spotlight(CGRect(x: 100, y: 10, width: 40, height: 40)))
    let dim = try #require(doc.spotlightDimPath)
    #expect(dim.contains(CGPoint(x: 50, y: 30)))
    #expect(!dim.contains(CGPoint(x: 120, y: 30)))
}

// MARK: Rendering

@Test func theExportIsDimmedOutsideTheSpotlightAndBrightInside() throws {
    let doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [spotlight(CGRect(x: 40, y: 20, width: 80, height: 40))])
    let image = try #require(AnnotationRenderer.flatten(doc))
    #expect(isBright(try pixel(image, 80, 40)))
    #expect(isBright(try pixel(image, 42, 22)))
    #expect(isDimmed(try pixel(image, 10, 10)))
    #expect(isDimmed(try pixel(image, 150, 40)))
    #expect(isDimmed(try pixel(image, 80, 80)))
}

@Test func overlappingSpotlightsCombineWithoutDimmingTwice() throws {
    let doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [
        spotlight(CGRect(x: 10, y: 10, width: 60, height: 60)),
        spotlight(CGRect(x: 40, y: 40, width: 60, height: 50)),
        spotlight(CGRect(x: 140, y: 10, width: 40, height: 40)),
    ])
    let image = try #require(AnnotationRenderer.flatten(doc))
    for (x, y) in [(20.0, 20.0), (55.0, 55.0), (90.0, 80.0), (160.0, 30.0)] {
        #expect(isBright(try pixel(image, x, y)), "at \(x), \(y)")
    }
    // Dimmed once, not once per spotlight.
    for (x, y) in [(5.0, 95.0), (120.0, 30.0), (190.0, 90.0)] {
        #expect(isDimmed(try pixel(image, x, y)), "at \(x), \(y)")
    }
}

@Test(arguments: [1.0, 2.0])
func spotlightRendersTheSameInTheEditorAndTheExport(scale: CGFloat) throws {
    let doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [
        spotlight(CGRect(x: 40, y: 20, width: 80, height: 40)),
        spotlight(CGRect(x: 100, y: 50, width: 60, height: 40)),
    ])
    let flat = try #require(AnnotationRenderer.flatten(doc))
    let editor = try render(doc, scale: scale)
    for x in stride(from: 3.0, to: 200, by: 7) {
        for y in stride(from: 3.0, to: 100, by: 7) {
            let exported = try pixel(flat, x, y), shown = try pixel(editor, x, y, scale: scale)
            #expect(zip(exported, shown).allSatisfy { abs($0 - $1) < 0.03 }, "at \(x), \(y)")
        }
    }
}

@Test func paddingIsNotDimmed() throws {
    var doc = EditorDocument(base: solidImage(width: 100, height: 100), annotations: [spotlight(CGRect(x: 20, y: 20, width: 30, height: 30))], background: RGBA(1, 1, 1))
    doc.canvasRect = CGRect(x: 0, y: 0, width: 160, height: 100)
    let image = try #require(AnnotationRenderer.flatten(doc))
    #expect(try pixel(image, 130, 50).allSatisfy { $0 > 0.97 })
    #expect(isDimmed(try pixel(image, 80, 50)))
    #expect(isBright(try pixel(image, 35, 35)))
}

@Test func transparentPixelsStayTransparent() throws {
    // The left half is the image, the right half transparent, like a window shadow's edge.
    let ctx = try #require(CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
    let base = try #require(ctx.makeImage())
    let doc = EditorDocument(base: base, annotations: [spotlight(CGRect(x: 5, y: 5, width: 10, height: 10))])
    let image = try #require(AnnotationRenderer.flatten(doc))
    #expect(try pixel(image, 80, 25)[3] == 0)
    #expect(isDimmed(try pixel(image, 30, 25)))
}

@Test func theDimSitsAtTheLowestSpotlightsLayer() throws {
    // A counter drawn before the spotlights is dimmed with the image; one drawn after stays bright.
    let below = Annotation(kind: .counter(1, center: CGPoint(x: 40, y: 50)), color: blue, lineWidth: 4)
    let above = Annotation(kind: .counter(2, center: CGPoint(x: 160, y: 50)), color: blue, lineWidth: 4)
    let doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [
        below,
        spotlight(CGRect(x: 80, y: 30, width: 20, height: 20)),
        above,
        spotlight(CGRect(x: 100, y: 60, width: 20, height: 20)),
    ])
    let image = try #require(AnnotationRenderer.flatten(doc))
    // Below the digit, inside the circle.
    let dimmed = try pixel(image, 40, 66), bright = try pixel(image, 160, 66)
    #expect(abs(dimmed[2] - 0.5) < 0.03)
    #expect(bright[2] > 0.97)
    #expect(isBright(try pixel(image, 110, 70)))
}

// MARK: Canvas

@Test func spotlightsNeverGrowTheCanvas() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    let past = spotlight(CGRect(x: 150, y: 50, width: 120, height: 80))
    doc.annotations.append(past)
    doc.grow(toFit: past, margin: 10)
    #expect(doc.canvasRect == doc.fullRect)
    doc.fitToContent(margin: 10)
    #expect(doc.canvasRect == doc.fullRect)
}

// MARK: Style

@Test func anEllipseSpotlightLightsOnlyItsEllipse() throws {
    var lit = spotlight(CGRect(x: 20, y: 20, width: 60, height: 60))
    lit.kind = .spotlight(CGRect(x: 20, y: 20, width: 60, height: 60), style: SpotlightStyle(shape: .ellipse))
    let image = try render(EditorDocument(base: solidImage(width: 100, height: 100), annotations: [lit]), scale: 1)
    #expect(isBright(try pixel(image, 50, 50)))
    // Inside the rect, but outside the ellipse.
    #expect(isDimmed(try pixel(image, 23, 23)))
}

@Test func strengthSetsHowDarkTheDimIs() throws {
    var dims: [CGFloat] = []
    for strength in [0.3, 0.5, 0.7] {
        let a = Annotation(kind: .spotlight(CGRect(x: 0, y: 0, width: 10, height: 10), style: SpotlightStyle(strength: strength)), color: blue, lineWidth: 4)
        let image = try render(EditorDocument(base: solidImage(width: 100, height: 100), annotations: [a]), scale: 1)
        dims.append(try pixel(image, 50, 50)[0])
    }
    #expect(dims == dims.sorted(by: >))
    #expect(abs(dims[1] - 0.5) < 0.03)
}

@Test func blurStrengthDoublesTheRadiusEveryFifthOfTheRange() {
    #expect(SpotlightStyle(strength: 0.5).blurRadius(forImageLength: 1000) == 8)
    #expect(abs(SpotlightStyle(strength: 0.3).blurRadius(forImageLength: 1000) - 4) < 0.001)
    #expect(abs(SpotlightStyle(strength: 0.7).blurRadius(forImageLength: 1000) - 16) < 0.001)
    #expect(SpotlightStyle(strength: 0.1).blurRadius(forImageLength: 100) == 4)
}

@Test func oldStrengthPresetsDecodeToTheirLook() throws {
    for (preset, strength) in [(0, 0.3), (1, 0.5), (2, 0.7)] {
        let json = Data(#"{"shape":"ellipse","effect":"blur","strength":\#(preset)}"#.utf8)
        #expect(try JSONDecoder().decode(SpotlightStyle.self, from: json) == SpotlightStyle(shape: .ellipse, effect: .blur, strength: strength))
    }
}

@Test func aStrengthRoundTrips() throws {
    let style = SpotlightStyle(effect: .blur, strength: 0.62)
    #expect(try JSONDecoder().decode(SpotlightStyle.self, from: JSONEncoder().encode(style)) == style)
}

@Test func theBlurEffectBlursOutsideAndLeavesTheSpotlightSharp() throws {
    // Black on the left half, red on the right: blurring softens the edge between them.
    let ctx = try #require(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    let base = try #require(ctx.makeImage())
    let style = SpotlightStyle(effect: .blur, strength: 0.7)
    let lit = Annotation(kind: .spotlight(CGRect(x: 90, y: 0, width: 20, height: 40), style: style), color: blue, lineWidth: 4)
    let image = try render(EditorDocument(base: base, annotations: [lit]), scale: 1)
    // At the edge inside the spotlight, sharp; at the same edge below it, blurred into a mix.
    #expect(try pixel(image, 101, 20)[0] > 0.97)
    let blurred = try pixel(image, 101, 80)[0]
    #expect(blurred > 0.1 && blurred < 0.9)
    // Far from the edge, the colour stays.
    #expect(try pixel(image, 190, 80)[0] > 0.97)
}

@Test func everySpotlightSharesTheEffectAndStrength() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [
        spotlight(CGRect(x: 10, y: 10, width: 20, height: 20)),
        Annotation(kind: .spotlight(CGRect(x: 50, y: 10, width: 20, height: 20), style: SpotlightStyle(shape: .ellipse)), color: blue, lineWidth: 4),
    ])
    doc.setSpotlights(effect: .blur, strength: 0.3)
    let styles = doc.annotations.compactMap { annotation -> SpotlightStyle? in
        if case let .spotlight(_, style) = annotation.kind { style } else { nil }
    }
    #expect(styles == [SpotlightStyle(effect: .blur, strength: 0.3), SpotlightStyle(shape: .ellipse, effect: .blur, strength: 0.3)])
    #expect(doc.spotlightStyle == styles[0])
}

// MARK: Soft edge

private func softSpotlight(_ rect: CGRect, shape: BoxShape = .rectangle, effect: SpotlightStyle.Effect = .darken, softEdge: Double = 1) -> Annotation {
    Annotation(kind: .spotlight(rect, style: SpotlightStyle(shape: shape, effect: effect, softEdge: softEdge)), color: blue, lineWidth: 4)
}

@Test func savedSpotlightsWithoutASoftEdgeDecodeAsHard() throws {
    let saved = Data(#"{"shape":"ellipse","effect":"blur","strength":2}"#.utf8)
    #expect(try JSONDecoder().decode(SpotlightStyle.self, from: saved) == SpotlightStyle(shape: .ellipse, effect: .blur, strength: 0.7))
    let soft = SpotlightStyle(softEdge: 0.4)
    #expect(try JSONDecoder().decode(SpotlightStyle.self, from: JSONEncoder().encode(soft)) == soft)
}

@Test func aSoftSpotlightFadesTheDimRatherThanCuttingItOut() throws {
    let doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [
        spotlight(CGRect(x: 10, y: 10, width: 40, height: 40)),
        softSpotlight(CGRect(x: 120, y: 20, width: 60, height: 60)),
    ])
    let dim = try #require(doc.spotlightDimPath)
    #expect(!dim.contains(CGPoint(x: 30, y: 30)))
    #expect(dim.contains(CGPoint(x: 150, y: 50)))
    #expect(doc.softSpotlights.map(\.rect) == [CGRect(x: 120, y: 20, width: 60, height: 60)])
}

@Test(arguments: BoxShape.spotlightShapes, SpotlightStyle.Effect.allCases)
func aSoftSpotlightIsBrightInsideDimOutsideAndFadesBetween(shape: BoxShape, effect: SpotlightStyle.Effect) throws {
    let doc = EditorDocument(base: solidImage(width: 300, height: 200), annotations: [softSpotlight(CGRect(x: 100, y: 50, width: 100, height: 100), shape: shape, effect: effect)])
    let image = try #require(AnnotationRenderer.flatten(doc))
    let centre = try pixel(image, 150, 100)[0]
    #expect(centre > 0.97, "\(centre)")
    if effect == .darken {
        #expect(isDimmed(try pixel(image, 10, 10)))
        let edge = try pixel(image, 100, 100)[0]
        #expect(edge > 0.6 && edge < 0.9, "\(edge)")
    }
}

@Test func aSoftEdgeLooksTheSameAtAnyImageSize() throws {
    var fades: [CGFloat] = []
    for size in [1.0, 2.0] {
        let doc = EditorDocument(base: solidImage(width: Int(200 * size), height: Int(100 * size)), annotations: [
            softSpotlight(CGRect(x: 50 * size, y: 20 * size, width: 100 * size, height: 60 * size), softEdge: 0.5),
        ])
        let image = try #require(AnnotationRenderer.flatten(doc))
        fades.append(try pixel(image, 46 * size, 50 * size)[0])
    }
    #expect(fades[0] > 0.55 && fades[0] < 0.9, "\(fades[0])")
    #expect(abs(fades[0] - fades[1]) < 0.03)
}

@Test(arguments: [1.0, 2.0])
func aSoftSpotlightRendersTheSameInTheEditorAndTheExport(scale: CGFloat) throws {
    let doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [
        softSpotlight(CGRect(x: 40, y: 20, width: 80, height: 40), shape: .ellipse),
        spotlight(CGRect(x: 130, y: 50, width: 40, height: 30)),
    ])
    let flat = try #require(AnnotationRenderer.flatten(doc))
    let editor = try render(doc, scale: scale)
    for x in stride(from: 3.0, to: 200, by: 7) {
        for y in stride(from: 3.0, to: 100, by: 7) {
            let exported = try pixel(flat, x, y), shown = try pixel(editor, x, y, scale: scale)
            #expect(zip(exported, shown).allSatisfy { abs($0 - $1) < 0.03 }, "at \(x), \(y)")
        }
    }
}

@Test func settingTheSharedLookKeepsEachSpotlightsEdge() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [
        spotlight(CGRect(x: 10, y: 10, width: 20, height: 20)),
        softSpotlight(CGRect(x: 50, y: 10, width: 20, height: 20), softEdge: 0.3),
    ])
    doc.setSpotlights(effect: .blur, strength: 0.3)
    #expect(doc.softSpotlights.map(\.style) == [SpotlightStyle(effect: .blur, strength: 0.3, softEdge: 0.3)])
}
