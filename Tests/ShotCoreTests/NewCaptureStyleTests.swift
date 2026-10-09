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
    let styled = try #require(copied.styledCapture(capture, scale: 2))
    #expect(styled.width > capture.width)
    #expect(styled.height > capture.height)
    // No background, so the corner of the canvas stays clear for pasting on any page.
    #expect(try alpha(styled, 0, 0) == 0)
}

@Test func aNewCaptureStyleThatChangesNothingStylesNothing() {
    let copied = CopiedStyle(style: ObjectStyle(), cornerRadius: 0, source: .capture)
    #expect(copied.styledCapture(grey(width: 20, height: 20), scale: 2) == nil)
}

@Test func roundingTheCornersAloneKeepsTheCaptureSize() throws {
    let capture = grey(width: 100, height: 60)
    let styled = try #require(CopiedStyle(style: ObjectStyle(), cornerRadius: 10, source: .capture).styledCapture(capture, scale: 1))
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
