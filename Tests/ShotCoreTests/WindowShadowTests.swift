import CoreGraphics
import Testing
@testable import ShotCore

/// A window capture in miniature: a see-through margin, a faint shadow band, then the opaque window.
private func capture(width: Int, height: Int, window: CGRect, shadow: CGFloat = 12) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // CoreGraphics draws from the bottom left, so the window is flipped into place.
    let flipped = CGRect(x: window.minX, y: CGFloat(height) - window.maxY, width: window.width, height: window.height)
    context.setFillColor(CGColor(gray: 0, alpha: 0.4))
    context.fill(flipped.insetBy(dx: -shadow, dy: -shadow))
    context.setFillColor(CGColor(gray: 0.9, alpha: 1))
    context.fill(flipped)
    return context.makeImage()!
}

@Test func findsTheWindowInsideItsShadow() {
    let window = CGRect(x: 40, y: 30, width: 200, height: 120)
    #expect(WindowShadow.body(of: capture(width: 280, height: 200, window: window)) == window)
}

@Test func anOffCentreWindowIsFoundFromTheTop() {
    // macOS draws more shadow below a window than above it.
    let window = CGRect(x: 30, y: 10, width: 100, height: 60)
    #expect(WindowShadow.body(of: capture(width: 160, height: 120, window: window)) == window)
}

@Test func aCaptureOpaqueToItsEdgesHasNoWindowBody() {
    let full = CGRect(x: 0, y: 0, width: 50, height: 40)
    #expect(WindowShadow.body(of: capture(width: 50, height: 40, window: full, shadow: 0)) == nil)
}

private let window = CGRect(x: 40, y: 30, width: 200, height: 120)

private func shadowedDocument() -> EditorDocument {
    var document = EditorDocument(base: capture(width: 280, height: 200, window: window))
    document.hasWindowShadow = true
    return document
}

@Test func aCropThatOnlyTrimsTheShadowKeepsIt() {
    var document = shadowedDocument()
    #expect(document.windowBody == window)
    let trimmed = window.insetBy(dx: -6, dy: -6)
    document.crop(to: trimmed)
    #expect(document.frameCrop == trimmed)
    #expect(document.usesWindowShadow)
}

@Test func aCropThatCutsIntoTheWindowLeavesNoShadow() {
    // #1381: the left of the window cropped off, the right and bottom edges out in the shadow.
    var document = shadowedDocument()
    document.crop(to: CGRect(x: 120, y: 20, width: 150, height: 170))
    #expect(document.frameCrop == CGRect(x: 120, y: 30, width: 120, height: 120))
    #expect(!document.usesWindowShadow)
}

@Test func aCroppedWindowDrawsItsOwnStyleOnlyWhileTheCropShows() {
    var document = shadowedDocument()
    document.crop(to: CGRect(x: 120, y: 20, width: 150, height: 170))
    let own = ObjectStyle(shadow: Shadow(elevation: 8, opacity: 0.3))
    document.setStyle(own, of: .capture, margin: 0)
    document.setCornerRadius(12, of: .capture)
    #expect(document.drawnCaptureStyle == own)
    #expect(document.drawnCaptureCornerRadius == 12)

    // Hiding the crop shows the whole window with its macOS shadow, so the own style isn't drawn as well.
    document.isFrameCropHidden = true
    #expect(document.usesWindowShadow)
    #expect(document.drawnCaptureStyle == ObjectStyle())
    #expect(document.drawnCaptureCornerRadius == 0)
    #expect(document.capturePaintedBounds == document.fullRect)

    // It comes back with the crop.
    document.isFrameCropHidden = false
    #expect(document.drawnCaptureStyle == own)

    document.resetCrop()
    #expect(document.drawnCaptureStyle == ObjectStyle())
}

@Test func otherImagesCropAsDrawn() {
    var document = EditorDocument(base: capture(width: 280, height: 200, window: window))
    #expect(document.windowBody == nil)
    let crop = CGRect(x: 120, y: 20, width: 150, height: 170)
    document.crop(to: crop)
    #expect(document.frameCrop == crop)
}
