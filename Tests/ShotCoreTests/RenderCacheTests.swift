import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let red = RGBA.presets[0]

/// A different grey in every pixel, so any change to a filter's output changes the bytes.
private func pattern(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for x in 0..<width {
        for y in 0..<height {
            ctx.setFillColor(CGColor(srgbRed: CGFloat(x % 17) / 16, green: CGFloat(y % 13) / 12, blue: CGFloat((x * y) % 7) / 6, alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    return ctx.makeImage()!
}

private func annotation(_ kind: Annotation.Kind) -> Annotation {
    Annotation(kind: kind, color: red, lineWidth: 4)
}

private func placed(_ rect: CGRect) -> Annotation {
    annotation(.image(AnnotationImage(pattern(width: Int(rect.width), height: Int(rect.height))), rect: rect))
}

/// A document with every kind of cached image: redactions and a blurred dim over a placed image, and soft spotlights.
/// Each call makes new images with the same pixels, so a render of it never hits what an earlier one cached.
private func document(effect: SpotlightStyle.Effect) -> EditorDocument {
    EditorDocument(base: pattern(width: 200, height: 120), annotations: [
        placed(CGRect(x: 30.4, y: 20.3, width: 60, height: 50)),
        annotation(.spotlight(CGRect(x: 120, y: 10, width: 50, height: 40), style: SpotlightStyle(effect: effect, softEdge: 0.4))),
        annotation(.spotlight(CGRect(x: 110, y: 60, width: 60, height: 40), style: SpotlightStyle(shape: .ellipse, effect: effect, softEdge: 0.2))),
        annotation(.pixelate(CGRect(x: 20, y: 30, width: 50, height: 30), amount: nil)),
        annotation(.blur(CGRect(x: 60, y: 50, width: 40, height: 40), amount: nil)),
    ])
}

private func bytes(_ image: CGImage) throws -> Data {
    try #require(image.dataProvider?.data as Data?)
}

@Test(arguments: [SpotlightStyle.Effect.darken, .blur])
func aCachedRenderMatchesAnUncachedOneByteForByte(effect: SpotlightStyle.Effect) throws {
    let doc = document(effect: effect)
    let first = try #require(AnnotationRenderer.flatten(doc))
    let cached = try #require(AnnotationRenderer.flatten(doc))
    let uncached = try #require(AnnotationRenderer.flatten(document(effect: effect)))
    #expect(try bytes(first) == bytes(uncached))
    #expect(try bytes(cached) == bytes(uncached))
}

@Test func aChangedRedactionRendersAsIfNothingWereCached() throws {
    var doc = document(effect: .blur)
    _ = AnnotationRenderer.flatten(doc)
    var fresh = document(effect: .blur)
    for index in [1, 4] {
        doc.annotations[index].offset(by: CGVector(dx: 7, dy: 3))
        fresh.annotations[index].offset(by: CGVector(dx: 7, dy: 3))
    }
    let cached = try #require(AnnotationRenderer.flatten(doc))
    let uncached = try #require(AnnotationRenderer.flatten(fresh))
    #expect(try bytes(cached) == bytes(uncached))
}

@Test func aBackdropIsTheSameWhileWhatItDrawsIs() {
    let base = pattern(width: 100, height: 100)
    let image = placed(CGRect(x: 10, y: 10, width: 20, height: 20))
    let rect = CGRect(x: 15, y: 15, width: 30, height: 30)
    #expect(Backdrop(base, below: [image], around: rect, outset: 4) == Backdrop(base, below: [image], around: rect, outset: 4))
    // With no image under it, it's the screenshot wherever it is.
    #expect(Backdrop(base, below: [image], around: CGRect(x: 60, y: 60, width: 10, height: 10), outset: 4) == Backdrop(base, below: [], around: rect, outset: 4))

    var moved = image
    moved.offset(by: CGVector(dx: 1, dy: 0))
    #expect(Backdrop(base, below: [image], around: rect, outset: 4) != Backdrop(base, below: [moved], around: rect, outset: 4))
    #expect(Backdrop(base, below: [image], around: rect, outset: 4) != Backdrop(base, below: [image], around: rect, outset: 8))
    #expect(Backdrop(base, below: [], around: rect, outset: 4) != Backdrop(pattern(width: 100, height: 100), below: [], around: rect, outset: 4))
}

@Test func aBackdropChangesWithTheAnnotationsUnderItThere() {
    let base = pattern(width: 100, height: 100)
    let rect = CGRect(x: 15, y: 15, width: 30, height: 30)
    let arrow = Annotation(kind: .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 40)), color: RGBA(1, 0, 0), lineWidth: 4)
    var far = arrow
    far.offset(by: CGVector(dx: 50, dy: 50))
    var hidden = arrow
    hidden.isHidden = true
    #expect(Backdrop(base, below: [arrow], around: rect, outset: 4) != Backdrop(base, below: [], around: rect, outset: 4))
    #expect(Backdrop(base, below: [far], around: rect, outset: 4) == Backdrop(base, below: [], around: rect, outset: 4))
    #expect(Backdrop(base, below: [hidden], around: rect, outset: 4) == Backdrop(base, below: [], around: rect, outset: 4))
    // A redaction there reads past its rect, so what it reads counts too.
    let blur = Annotation(kind: .blur(CGRect(x: 40, y: 40, width: 30, height: 30)), color: RGBA(1, 0, 0), lineWidth: 4)
    let nearBlur = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 54, y: 42, width: 4, height: 4)), color: RGBA(1, 0, 0), lineWidth: 4)
    #expect(Backdrop(base, below: [nearBlur], around: rect, outset: 4).below.isEmpty)
    #expect(Backdrop(base, below: [nearBlur, blur], around: rect, outset: 4).below == [nearBlur, blur])
    // Only what's under the redaction counts; what's over it is drawn after.
    #expect(Backdrop(base, below: [blur, nearBlur], around: rect, outset: 4).below == [blur])
    // Every spotlight counts, since their one dim covers the whole canvas.
    let spotlight = Annotation(kind: .spotlight(CGRect(x: 80, y: 80, width: 10, height: 10), style: SpotlightStyle()), color: RGBA(1, 0, 0), lineWidth: 4)
    #expect(Backdrop(base, below: [spotlight], around: rect, outset: 4).below == [spotlight])
}

@Test func theCacheMakesEachImageOnceAndDropsWhatARenderDidntUse() throws {
    let cache = RenderCache()
    let image = pattern(width: 4, height: 4)
    let key = RenderCache.Key.softSpotlight(SoftSpotlight(rect: CGRect(x: 0, y: 0, width: 4, height: 4), style: SpotlightStyle(softEdge: 0.5), cornerRadius: nil))
    var made = 0
    let make = { () -> RenderCache.Value? in
        made += 1
        return (image, .zero)
    }
    #expect(cache.value(for: key, make: make)?.image === image)
    #expect(cache.value(for: key, make: make)?.image === image)
    #expect(made == 1)
    cache.sweep()
    #expect(cache.count == 1)
    cache.sweep()
    #expect(cache.count == 0)
    _ = cache.value(for: key, make: make)
    #expect(made == 2)
}

@Test func aShadowCasterMovedAnywhereIsTheSameShadowMoved() {
    var arrow = Annotation(kind: .arrow(from: CGPoint(x: 10.3, y: 20.7), to: CGPoint(x: 80.1, y: 45.9)), color: RGBA(1, 0, 0), lineWidth: 4)
    arrow.style = ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 1))
    let origin = arrow.paintedBounds.origin
    // Moved by fractions of a pixel, as a keyframed move does, which leaves its points rounded differently.
    for delta in [CGSize(width: 0.37, height: 1.21), CGSize(width: 123.456, height: -7.89), CGSize(width: 1e-9, height: 0)] {
        let moved = arrow.moved(by: delta)
        #expect(ShadowCaster.annotation(moved).relative(to: moved.paintedBounds.origin) == ShadowCaster.annotation(arrow).relative(to: origin))
    }
    var bigger = arrow
    bigger.lineWidth = 6
    #expect(ShadowCaster.annotation(bigger).relative(to: bigger.paintedBounds.origin) != ShadowCaster.annotation(arrow).relative(to: origin))
}

@Test func aMovedAnnotationsCachedShadowIsDrawnWhereItNowIs() throws {
    var line = Annotation(kind: .line(from: CGPoint(x: 20, y: 40), to: CGPoint(x: 120, y: 40)), color: RGBA(1, 0, 0), lineWidth: 4)
    line.style = ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 1))
    let base = pattern(width: 1, height: 1)
    func render(_ annotation: Annotation) throws -> CGImage {
        let ctx = try #require(CGContext(data: nil, width: 260, height: 160, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.translateBy(x: 0, y: 160)
        ctx.scaleBy(x: 1, y: -1)
        AnnotationRenderer.draw(annotation, base: base, in: ctx)
        return try #require(ctx.makeImage())
    }
    // Drawn here first, so the moved one comes from the cache.
    let first = try render(line)
    let moved = try render(line.moved(by: CGSize(width: 100, height: 70)))
    let a = try bytes(first), b = try bytes(moved), row = first.bytesPerRow
    // Under the line, where only the shadow is, the shadow moved with it.
    for (x, y) in [(70, 52), (40, 60), (100, 48)] {
        let before = a[y * row + x * 4 + 3], after = b[(y + 70) * row + (x + 100) * 4 + 3]
        #expect(before > 0)
        #expect(abs(Int(before) - Int(after)) <= 2)
    }
}
