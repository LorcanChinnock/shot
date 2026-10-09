import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private func grey(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

/// The alpha of the pixel at (`x`, `y`), top-left origin, from 0 to 255.
private func alpha(_ image: CGImage, _ x: Int, _ y: Int) throws -> UInt8 {
    let data = try #require(image.dataProvider?.data as Data?)
    return data[y * image.bytesPerRow + x * 4 + 3]
}

@Test func aNewCaptureWithAShadowGrowsToHoldItAndStaysClearAtTheCorners() throws {
    let capture = grey(width: 200, height: 120)
    let copied = CopiedStyle(style: ObjectStyle(shadow: ShadowPreset.float.shadow(scale: 1)), cornerRadius: 12, source: .capture)
    let styled = try #require(copied.styledCapture(capture, scale: 2, background: nil))
    #expect(styled.width > capture.width)
    #expect(styled.height > capture.height)
    // No background, so the corner of the canvas stays clear for pasting on any page.
    #expect(try alpha(styled, 0, 0) == 0)
}

@Test func aNewCaptureStyleThatChangesNothingStylesNothing() {
    let copied = CopiedStyle(style: ObjectStyle(), cornerRadius: 0, source: .capture)
    #expect(copied.styledCapture(grey(width: 20, height: 20), scale: 2, background: nil) == nil)
}

@Test func roundingTheCornersAloneKeepsTheCaptureSize() throws {
    let capture = grey(width: 100, height: 60)
    let styled = try #require(CopiedStyle(style: ObjectStyle(), cornerRadius: 10, source: .capture).styledCapture(capture, scale: 1, background: nil))
    #expect(styled.width == capture.width)
    #expect(styled.height == capture.height)
    #expect(try alpha(styled, 0, 0) == 0)
    #expect(try alpha(styled, 50, 30) == 255)
}

@Test func theNewCaptureStyleIsSavedOnlyWhileItsSettingIsOn() throws {
    let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }
    Preferences.registerDefaults(in: store)
    let prefs = Preferences(store: store)
    #expect(prefs.newCaptureStyle == nil)
    let copied = CopiedStyle(style: ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 1), border: .hairline), cornerRadius: 8, source: .capture)
    Preferences.styleNewCaptures(with: copied, in: store)
    #expect(prefs.newCaptureStyle == copied)
    Preferences.styleNewCaptures(with: nil, in: store)
    #expect(prefs.newCaptureStyle == nil)
}

@Test func aJPEGCaptureIsStyledOverTheBackgroundTheEditorShowsItOn() throws {
    let copied = CopiedStyle(style: ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 1)), cornerRadius: 12, source: .capture)
    let styled = try #require(copied.styledCapture(grey(width: 100, height: 60), scale: 1, background: EditorDocument.defaultBackground(for: .jpeg)))
    #expect(try alpha(styled, 0, 0) == 255)
}

@Test func aScreenshotOpenedWithTheNewCaptureStyleStillHasItAtAnyScale() {
    let copied = CopiedStyle(style: ObjectStyle(shadow: Shadow(elevation: 10.1, opacity: 0.13, tint: .ambient, isOffset: true), border: .hairline), cornerRadius: 0.1, source: .capture)
    for scale: CGFloat in [1, 1.5, 2, 3] {
        var doc = EditorDocument(base: grey(width: 40, height: 30))
        doc.pasteStyle(copied, to: [.capture], scale: scale, margin: 0)
        #expect(doc.captureHas(copied, scale: scale))
    }
}

@Test func aScreenshotStyledDifferentlyDoesNotHaveTheNewCaptureStyle() {
    let copied = CopiedStyle(style: ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 1)), cornerRadius: 12, source: .capture)
    var doc = EditorDocument(base: grey(width: 40, height: 30))
    #expect(!doc.captureHas(copied, scale: 2))
    doc.pasteStyle(copied, to: [.capture], scale: 2, margin: 0)
    doc.setCornerRadius(4, of: .capture)
    #expect(!doc.captureHas(copied, scale: 2))
    #expect(!doc.captureHas(nil, scale: 2))
}

@Test(arguments: [ImageFormat.png, .jpeg])
func aWindowCapturedWithTheMacOSShadowSaysSoInItsFile(format: ImageFormat) throws {
    let marked = try #require(ImageCodec.data(from: grey(width: 20, height: 10), scale: 2, format: format, windowShadow: true))
    let plain = try #require(ImageCodec.data(from: grey(width: 20, height: 10), scale: 2, format: format))
    #expect(ImageCodec.hasWindowShadow(of: marked))
    #expect(!ImageCodec.hasWindowShadow(of: plain))
    #expect(ImageCodec.scale(of: marked) == 2)
}

@Test func aWindowWithTheMacOSShadowTakesNoSecondShadowButKeepsTheRestOfAStyle() {
    var doc = EditorDocument(base: grey(width: 40, height: 30))
    doc.hasWindowShadow = true
    doc.setStyle(ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 2), border: .hairline), of: .capture, margin: 0)
    #expect(doc.captureStyle == ObjectStyle(border: .hairline))
    // A pasted style loses its shadow the same way, and a shadow alone changes nothing.
    let copied = CopiedStyle(style: ObjectStyle(shadow: ShadowPreset.float.shadow(scale: 1)), cornerRadius: 0, source: .capture)
    doc.pasteStyle(copied, to: [.capture], scale: 2, margin: 0)
    #expect(doc.captureStyle.shadow == nil)
    #expect(copied.styledCapture(grey(width: 40, height: 30), scale: 2, background: nil, windowShadow: true) == nil)
    #expect(copied.styledCapture(grey(width: 40, height: 30), scale: 2, background: nil) != nil)
}

@Test func aWindowWithTheMacOSShadowHasTheNewCaptureStyleWithoutItsShadowAndKeepsItWhenSaving() throws {
    let saved = CopiedStyle(style: ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 1), border: .hairline), cornerRadius: 8, source: .capture)
    var doc = EditorDocument(base: grey(width: 40, height: 30))
    doc.hasWindowShadow = true
    doc.pasteStyle(saved, to: [.capture], scale: 2, margin: 0)
    #expect(doc.captureHas(saved, scale: 2))
    // Saving this screenshot's style for new captures keeps the shadow saved before, for captures that can take one.
    doc.setCornerRadius(4, of: .capture)
    let resaved = try #require(doc.newCaptureStyle(keeping: saved, scale: 2))
    #expect(resaved.style.shadow == saved.style.shadow)
    #expect(resaved.cornerRadius == 2)
    var plain = EditorDocument(base: grey(width: 40, height: 30))
    plain.pasteStyle(saved, to: [.capture], scale: 2, margin: 0)
    plain.setStyle(ObjectStyle(border: .hairline), of: .capture, margin: 0)
    #expect(plain.newCaptureStyle(keeping: saved, scale: 2)?.style.shadow == nil)
}
