import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

// Linux draws the spotlight dim through a mask, since a `CanvasPath` has no booleans; a Mac draws the `CGPath`. Both
// give the same pixels, except that an edge drawn smooth can be a level apart, since the mask keeps its coverage in 8 bits.

private func spotlight(_ rect: CGRect, _ style: SpotlightStyle = SpotlightStyle(), cornerRadius: CGFloat? = nil) -> Annotation {
    var annotation = Annotation(kind: .spotlight(rect, style: style), color: RGBA(0, 0, 1), lineWidth: 4)
    annotation.cornerRadius = cornerRadius
    return annotation
}

/// A 200 × 100 image that's a different colour in every pixel, so a dim that's off by a pixel shows.
private func gradient() throws -> CGImage {
    let canvas = try #require(CGCanvas(width: 200, height: 100, format: .sRGB))
    for x in 0..<200 {
        canvas.setFillColor(RGBA(Double(x) / 200, 0.3, 1 - Double(x) / 200))
        canvas.fill(CGRect(x: x, y: 0, width: 1, height: 100))
    }
    canvas.setFillColor(RGBA(1, 1, 1, 0.4))
    canvas.fill(CanvasPath(ellipseIn: CGRect(x: 20, y: 10, width: 150, height: 70)))
    return try #require(canvas.makeImage())
}

/// The documents to dim, and whether every edge of their dim falls on whole pixels at 1 pixel to a point.
private func documents() throws -> [(name: String, doc: EditorDocument, aligned: Bool)] {
    let base = try gradient()
    var padded = EditorDocument(base: base, annotations: [
        Annotation(kind: .shape(.rectangle, rect: CGRect(x: 170, y: 60, width: 60, height: 50)), color: RGBA(1, 0, 0), lineWidth: 6),
        spotlight(CGRect(x: 40.5, y: 20.25, width: 60.3, height: 45.7), SpotlightStyle(shape: .ellipse)),
    ])
    padded.contentRect = CGRect(x: -20, y: -15, width: 260, height: 140)
    padded.captureCornerRadius = 12
    var cropped = EditorDocument(base: base, annotations: [spotlight(CGRect(x: 30, y: 30, width: 50, height: 40))])
    cropped.contentRect = CGRect(x: -10, y: -10, width: 220, height: 120)
    cropped.frameCrop = CGRect(x: 15, y: 5, width: 150, height: 80)
    return [
        ("overlapping rectangles", EditorDocument(base: base, annotations: [
            spotlight(CGRect(x: 10, y: 10, width: 40, height: 40)),
            spotlight(CGRect(x: 30, y: 30, width: 40, height: 40)),
            spotlight(CGRect(x: 150, y: 20, width: 30, height: 30)),
        ]), true),
        ("rounded corners", EditorDocument(base: base, annotations: [
            spotlight(CGRect(x: 10, y: 10, width: 40, height: 40), cornerRadius: 8),
            spotlight(CGRect(x: 30, y: 30, width: 40, height: 40)),
        ]), false),
        ("an ellipse over padding and a shape", padded, false),
        ("a star and a triangle off the edge", EditorDocument(base: base, annotations: [
            spotlight(CGRect(x: -20, y: 40, width: 80, height: 80), SpotlightStyle(shape: .star), cornerRadius: 4),
            spotlight(CGRect(x: 120.6, y: -10.2, width: 70, height: 60), SpotlightStyle(shape: .triangle)),
        ]), false),
        ("a soft one beside a hard one", EditorDocument(base: base, annotations: [
            spotlight(CGRect(x: 20, y: 20, width: 50, height: 50), SpotlightStyle(softEdge: 0.5)),
            spotlight(CGRect(x: 110, y: 30, width: 50, height: 40), SpotlightStyle(shape: .diamond)),
        ]), false),
        ("one lighting the whole left half", EditorDocument(base: base, annotations: [
            spotlight(CGRect(x: -10, y: -10, width: 110, height: 120)),
        ]), true),
        ("a frame crop", cropped, true),
    ]
}

/// The document's image drawn on a new canvas at `scale` pixels to a point, top-left origin, as the renderer sets it up,
/// with `draw` done after.
private func drawn(_ doc: EditorDocument, scale: CGFloat, _ draw: (any Canvas) -> Void) throws -> Bitmap {
    let canvas = doc.canvasRect
    let ctx = try #require(CGCanvas(width: Int(canvas.width * scale), height: Int(canvas.height * scale), format: .sRGB))
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: canvas.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: -canvas.minX, y: -canvas.minY)
    AnnotationRenderer.drawUpright(doc.base, in: doc.captureRect, ctx: ctx)
    draw(ctx)
    return try #require(ctx.makeBitmap())
}

/// Whether `a` and `b` are the same size, no byte of one is more than `tolerance` from the other's, and only a few
/// edge bytes differ at all, so a dim that's a level off everywhere still fails.
private func matches(_ a: Bitmap, _ b: Bitmap, within tolerance: Int, differing maxDiffering: Int = 64) -> Bool {
    let differences = zip(a.pixels, b.pixels).map { abs(Int($0) - Int($1)) }.filter { $0 > 0 }
    return a.width == b.width && a.height == b.height && differences.allSatisfy { $0 <= tolerance } && differences.count <= maxDiffering
}

private func dims(of doc: EditorDocument, scale: CGFloat) throws -> (path: SpotlightDim, mask: SpotlightDim) {
    let path = try #require(doc.spotlightDimPath(shaper: CoreTextShaper()))
    let (mask, frame) = try #require(doc.spotlightDimMask(shaper: CoreTextShaper(), canvasType: CGCanvas.self, scale: scale))
    return (.path(path), .mask(mask, frame: frame))
}

@Test(arguments: [1, 2] as [CGFloat])
func theMaskedDimDarkensTheSamePixelsAsThePath(scale: CGFloat) throws {
    for (name, doc, aligned) in try documents() {
        let (path, mask) = try dims(of: doc, scale: scale)
        let darken: (SpotlightDim) -> (any Canvas) -> Void = { dim in
            { ctx in
                ctx.setBlendMode(.sourceAtop)
                ctx.setFillColor(RGBA(0, 0, 0, 0.6))
                dim.fill(ctx)
            }
        }
        #expect(try matches(drawn(doc, scale: scale, darken(path)), drawn(doc, scale: scale, darken(mask)), within: aligned ? 0 : 1), "\(name)")
        // Core Graphics' booleans can leave an edge a hair past a whole pixel.
        #expect(path.bounds.insetBy(dx: 1e-6, dy: 1e-6).integral == mask.bounds, "\(name)")
    }
}

@Test(arguments: [1, 2] as [CGFloat])
func theMaskedDimClipsToTheSamePixelsAsThePath(scale: CGFloat) throws {
    for (name, doc, aligned) in try documents() {
        let (path, mask) = try dims(of: doc, scale: scale)
        let paint: (SpotlightDim) -> (any Canvas) -> Void = { dim in
            { ctx in
                dim.clip(ctx)
                ctx.setFillColor(RGBA(1, 0.5, 0, 0.8))
                ctx.fill(doc.canvasRect)
            }
        }
        #expect(try matches(drawn(doc, scale: scale, paint(path)), drawn(doc, scale: scale, paint(mask)), within: aligned ? 0 : 1), "\(name)")
    }
}

@Test func thereIsNoMaskWithoutASpotlight() throws {
    let doc = EditorDocument(base: try gradient(), annotations: [spotlight(CGRect(x: 50, y: 10, width: 0, height: 50))])
    #expect(doc.spotlightDimMask(shaper: CoreTextShaper(), canvasType: CGCanvas.self, scale: 1) == nil)
}

