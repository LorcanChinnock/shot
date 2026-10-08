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
    #expect(Backdrop(base, images: [image], around: rect, outset: 4) == Backdrop(base, images: [image], around: rect, outset: 4))
    // With no image under it, it's the screenshot wherever it is.
    #expect(Backdrop(base, images: [image], around: CGRect(x: 60, y: 60, width: 10, height: 10), outset: 4) == Backdrop(base, images: [], around: rect, outset: 4))

    var moved = image
    moved.offset(by: CGVector(dx: 1, dy: 0))
    #expect(Backdrop(base, images: [image], around: rect, outset: 4) != Backdrop(base, images: [moved], around: rect, outset: 4))
    #expect(Backdrop(base, images: [image], around: rect, outset: 4) != Backdrop(base, images: [image], around: rect, outset: 8))
    #expect(Backdrop(base, images: [], around: rect, outset: 4) != Backdrop(pattern(width: 100, height: 100), images: [], around: rect, outset: 4))
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
