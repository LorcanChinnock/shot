import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

@Test func noFrameLeavesTheCanvasAsItIs() {
    let canvas = CGRect(x: -10, y: 0, width: 210, height: 100)
    #expect(CanvasFrame.none.framing(canvas, image: CGRect(x: 0, y: 0, width: 200, height: 100)) == canvas)
    #expect(CanvasFrame.none.isNone)
    #expect(!CanvasFrame(padding: 4).isNone)
    #expect(!CanvasFrame(aspect: .square).isNone)
}

@Test func paddingGoesRoundTheImageOnEverySide() {
    let image = CGRect(x: 0, y: 0, width: 200, height: 100)
    let framed = CanvasFrame(padding: 40).framing(image, image: image)
    #expect(framed == CGRect(x: -40, y: -40, width: 280, height: 180))
}

@Test func paddingNeverCutsOffWhatReachesFurther() {
    let image = CGRect(x: 0, y: 0, width: 200, height: 100)
    // A mark reaches 100 px past the right edge, further than the padding.
    let canvas = CGRect(x: 0, y: 0, width: 300, height: 100)
    let framed = CanvasFrame(padding: 40).framing(canvas, image: image)
    #expect(framed.minX == -40)
    #expect(framed.maxX == 300)
    #expect(framed.minY == -40)
    #expect(framed.maxY == 140)
}

@Test(arguments: CanvasAspect.allCases.filter { $0 != .auto })
func aSizeGrowsTheCanvasToItsShapeAboutItsCentre(aspect: CanvasAspect) throws {
    let image = CGRect(x: 0, y: 0, width: 300, height: 200)
    let framed = CanvasFrame(aspect: aspect).framing(image, image: image)
    let ratio = try #require(aspect.ratio)
    #expect(abs(framed.width / framed.height - ratio) < 0.01)
    #expect(framed.contains(image))
    #expect(abs(framed.midX - image.midX) <= 1)
    #expect(abs(framed.midY - image.midY) <= 1)
    #expect(framed == framed.integral)
}

@Test func aSquareIsExactlySquareFromAnOddSize() {
    let image = CGRect(x: 0, y: 0, width: 848, height: 693)
    let framed = CanvasFrame(aspect: .square).framing(image, image: image)
    #expect(framed.width == 848)
    #expect(framed.height == 848)
}

@Test func paddingComesBeforeTheSize() {
    let image = CGRect(x: 0, y: 0, width: 100, height: 100)
    let framed = CanvasFrame(padding: 20, aspect: .wide).framing(image, image: image)
    #expect(framed.height == 140)
    #expect(framed.minY == -20)
    // Both edges round outward to whole pixels.
    #expect(abs(framed.width - 140.0 * 16 / 9) <= 2)
}

@Test func theDocumentsCanvasTakesTheFrameAndItsUndoStepsKeepIt() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    let plain = doc.snapshot
    doc.frame = CanvasFrame(padding: 30, aspect: .square)
    #expect(doc.canvasRect.width == doc.canvasRect.height)
    #expect(doc.canvasRect.contains(CGRect(x: -30, y: -30, width: 260, height: 160)))
    #expect(doc.hasPadding)
    let framed = doc.snapshot
    doc.restore(plain)
    #expect(doc.canvasRect == doc.fullRect)
    doc.restore(framed)
    #expect(doc.frame == CanvasFrame(padding: 30, aspect: .square))
}

@Test func paddingGoesRoundTheCropNotTheWholeImage() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    doc.crop(to: CGRect(x: 50, y: 20, width: 100, height: 60))
    doc.frame = CanvasFrame(padding: 10)
    #expect(doc.canvasRect == CGRect(x: 40, y: 10, width: 120, height: 80))
    // The crop can still only be adjusted within what the document holds, not the padding.
    #expect(doc.contentRect == doc.fullRect)
}

@Test func trimToImageTakesOffTheFrameToo() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    #expect(!doc.canTrimToImage)
    doc.frame = CanvasFrame(padding: 30)
    #expect(doc.canTrimToImage)
    doc.trimToImage()
    #expect(doc.frame.isNone)
    #expect(doc.canvasRect == doc.fullRect)
}

@Test func aSnapshotSavedBeforeTheStylePanelDecodesWithNoFrameOrFill() throws {
    let json = """
    {"annotations":[],"contentRect":[[0,0],[200,100]],"isFrameCropHidden":false,"captureCornerRadius":0,"captureStyle":{}}
    """
    let snapshot = try JSONDecoder().decode(EditorSnapshot.self, from: Data(json.utf8))
    #expect(snapshot.frame == nil)
    #expect(snapshot.backgroundFill == nil)
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    doc.frame = CanvasFrame(padding: 8)
    doc.backgroundFill = .sea
    doc.restore(snapshot)
    #expect(doc.frame.isNone)
    #expect(doc.backgroundFill == nil)
}

@Test func aGradientFillsThePaddingFromCornerToCorner() throws {
    var doc = EditorDocument(base: solidImage(width: 40, height: 40))
    doc.frame = CanvasFrame(padding: 30)
    doc.backgroundFill = .citrus
    doc.background = BackgroundFill.citrus.average
    let image = try #require(AnnotationRenderer.flatten(doc))
    #expect(image.width == 100)
    let topLeft = try pixel(image, 1, 1), bottomRight = try pixel(image, 98, 98)
    let (start, end) = BackgroundFill.citrus.colors
    #expect(abs(topLeft[1] - start.g) < 0.05)
    #expect(abs(bottomRight[1] - end.g) < 0.05)
    #expect(topLeft[3] == 1)
    // The screenshot, red, is still drawn over it.
    let middle = try pixel(image, 50, 50)
    #expect(middle[0] > 0.9 && middle[1] < 0.1)
}

@Test func theDesktopFillDrawsThePictureAndFallsBackToGreyWithout() throws {
    var doc = EditorDocument(base: solidImage(width: 20, height: 20))
    doc.frame = CanvasFrame(padding: 20)
    doc.backgroundFill = .desktop
    doc.background = BackgroundFill.desktop.average
    let grey = try pixel(try #require(AnnotationRenderer.flatten(doc)), 1, 1)
    let start = BackgroundFill.desktop.colors.start
    #expect(abs(grey[0] - start.r) < 0.05)
    let ctx = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    doc.desktopPicture = ctx.makeImage()
    let blue = try pixel(try #require(AnnotationRenderer.flatten(doc)), 1, 1)
    #expect(blue[2] > 0.9 && blue[0] < 0.1)
}

@Test func theDesktopPictureStandsTheRightWayUp() throws {
    // Top half green, bottom half blue, as a person sees it.
    let ctx = try #require(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 5))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 5, width: 10, height: 5))
    var doc = EditorDocument(base: solidImage(width: 10, height: 10))
    doc.frame = CanvasFrame(padding: 45)
    doc.backgroundFill = .desktop
    doc.background = BackgroundFill.desktop.average
    doc.desktopPicture = ctx.makeImage()
    let image = try #require(AnnotationRenderer.flatten(doc))
    #expect(try pixel(image, 50, 2)[1] > 0.9)
    #expect(try pixel(image, 50, 97)[2] > 0.9)
}

@Test func theBackgroundSwatchesAreTheBoardsAndKnowTheirOwn() {
    #expect(BackgroundSwatches.colors.map(\.color.hex) == ["#F3D9B1", "#C9DCEB", "#D8E8D0", "#F2D3D8", "#DCD6F2", "#2A2A2E", "#FFFFFF"])
    #expect(BackgroundSwatches.contains(RGBA(hex: 0xC9DCEB)))
    #expect(!BackgroundSwatches.contains(RGBA(0.1, 0.2, 0.3)))
    #expect(!BackgroundSwatches.contains(nil))
}

// MARK: Use for new captures

@Test func aPlainCanvasIsntSavedForNewCaptures() throws {
    var doc = EditorDocument(base: solidImage(width: 100, height: 60), background: RGBA(1, 1, 1))
    doc.captureStyle = ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 2))
    let saved = try #require(doc.newCaptureStyle(scale: 2))
    #expect(saved.canvas == nil)
}

@Test func aFramedCanvasIsSavedInPointsAndComesBackOnANewCapture() throws {
    var doc = EditorDocument(base: solidImage(width: 100, height: 60))
    doc.frame = CanvasFrame(padding: 48, aspect: .wide)
    doc.backgroundFill = .dusk
    doc.background = BackgroundFill.dusk.average
    let saved = try #require(doc.newCaptureStyle(scale: 2))
    #expect(saved.canvas == CanvasStyle(background: BackgroundFill.dusk.average, fill: .dusk, padding: 24, aspect: .wide))
    #expect(doc.captureHas(saved, scale: 2))

    var fresh = EditorDocument(base: solidImage(width: 300, height: 200))
    #expect(!fresh.captureHas(saved, scale: 1))
    fresh.applyNewCaptureStyle(saved, scale: 1, margin: 0)
    #expect(fresh.frame == CanvasFrame(padding: 24, aspect: .wide))
    #expect(fresh.backgroundFill == .dusk)
    #expect(fresh.captureHas(saved, scale: 1))
}

@Test func aTransparentSavedBackgroundLeavesAJPEGsWhite() {
    var doc = EditorDocument(base: solidImage(width: 100, height: 60), background: EditorDocument.defaultBackground(for: .jpeg))
    doc.applyCanvas(CanvasStyle(background: nil, fill: nil, padding: 10, aspect: .auto), scale: 1)
    #expect(doc.background == RGBA(1, 1, 1))
    #expect(doc.frame.padding == 10)
}

@Test func aNewCaptureWithOnlyACanvasIsStyled() throws {
    var copied = CopiedStyle(style: ObjectStyle(), cornerRadius: 0, source: .capture)
    copied.canvas = CanvasStyle(background: RGBA(1, 1, 1), fill: nil, padding: 10, aspect: .auto)
    let styled = try #require(copied.styledCapture(solidImage(width: 20, height: 20), scale: 1, background: nil))
    #expect(styled.width == 40)
    #expect(try pixel(styled, 1, 1) == [1, 1, 1, 1])
}

@Test func aStyleSavedBeforeCanvasesDecodesWithout() throws {
    let copied = CopiedStyle(style: ObjectStyle(), cornerRadius: 4, source: .capture)
    let data = try JSONEncoder().encode(copied)
    #expect(!String(decoding: data, as: UTF8.self).contains("canvas"))
    #expect(try JSONDecoder().decode(CopiedStyle.self, from: data).canvas == nil)
}

@Test func stylesWithDifferentCanvasesArentTheSame() {
    let plain = CopiedStyle(style: ObjectStyle(), cornerRadius: 0, source: .capture)
    var padded = plain
    padded.canvas = CanvasStyle(background: nil, fill: nil, padding: 10, aspect: .auto)
    #expect(!plain.isSameStyle(as: padded))
    var nearly = padded
    nearly.canvas?.padding = 10.0001
    #expect(padded.isSameStyle(as: nearly))
}

// MARK: Layout

@Test func theScreenshotsPanelIsOneListInTheBoardsOrder() {
    let sections = StylePanelLayout.sections(kind: .capture, windowShadow: false, borders: true)
    #expect(sections.target == [.background, .padding, .corners, .shadow, .border, .size, .newCaptures])
    #expect(sections.canvas.isEmpty)
}

@Test func aWindowWithItsOwnShadowStillTakesACanvas() {
    let sections = StylePanelLayout.sections(kind: .capture, windowShadow: true, borders: true)
    #expect(sections.target == [.background, .padding, .windowShadowNote, .size, .newCaptures])
}

@Test func aSelectionsOwnPartsComeBeforeTheCanvas() {
    let shape = StylePanelLayout.sections(kind: .mark, windowShadow: false, borders: false)
    #expect(shape.target == [.shadow])
    #expect(shape.canvas == [.background, .padding, .size])
    let image = StylePanelLayout.sections(kind: .image, windowShadow: false, borders: true)
    #expect(image.target == [.corners, .shadow, .border])
}

@Test func nothingToStyleStillOffersTheCanvas() {
    let sections = StylePanelLayout.sections(kind: nil, windowShadow: false, borders: false)
    #expect(sections.target == [.noTargetNote])
    #expect(sections.canvas == [.background, .padding, .size])
}
