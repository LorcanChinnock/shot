import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let blue = RGBA(0, 0, 1)
private let canvas = CGRect(x: 0, y: 0, width: 400, height: 300)
private let view = CGSize(width: 800, height: 600)

private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
    let data = try #require(image.dataProvider?.data as Data?)
    let offset = y * image.bytesPerRow + x * 4
    return Array(data[offset..<offset + 4])
}

private func isBlue(_ p: [UInt8]) -> Bool { p[0] < 30 && p[1] < 30 && p[2] > 225 && p[3] == 255 }
private func isRed(_ p: [UInt8]) -> Bool { p[0] > 225 && p[1] < 30 && p[2] < 30 && p[3] == 255 }

@Test func fitCentresTheCanvasAndNeverGoesPastMaxScale() {
    // 380 × 280 pt is the room left inside the 20 pt inset.
    let fit = Viewport.fit(canvas, in: CGSize(width: 420, height: 320), maxScale: 1)
    #expect(abs(fit.scale - 280.0 / 300) < 1e-9)
    #expect(fit.viewRect(canvas).midY == 160)
    #expect(fit.viewRect(canvas).minX == ((420 - 400 * fit.scale) / 2).rounded())

    // A small Retina capture stops at actual size, half a point per pixel.
    let capped = Viewport.fit(canvas, in: view, maxScale: 0.5)
    #expect(capped == Viewport(scale: 0.5, origin: CGPoint(x: 300, y: 225)))
    #expect(capped.viewRect(canvas) == CGRect(x: 300, y: 225, width: 200, height: 150))

    // Before the view has a size, the scale stays positive.
    #expect(Viewport.fit(canvas, in: .zero, maxScale: 1).scale > 0)
}

@Test func fitPlacesACanvasThatGrewPastTheImage() {
    // The canvas grew 50 px left and 20 px up, so image point (0, 0) sits inside it.
    let grown = CGRect(x: -50, y: -20, width: 450, height: 320)
    let fit = Viewport.fit(grown, in: CGSize(width: 490, height: 360), maxScale: 1)
    #expect(fit.scale == 1)
    #expect(fit.viewRect(grown) == CGRect(x: 20, y: 20, width: 450, height: 320))
    #expect(fit.viewPoint(.zero) == CGPoint(x: 70, y: 40))
}

@Test func viewAndImagePointsRoundTrip() {
    let viewport = Viewport(scale: 3, origin: CGPoint(x: -125, y: 40))
    let image = CGPoint(x: 17.5, y: 230)
    #expect(viewport.viewPoint(image) == CGPoint(x: -72.5, y: 730))
    #expect(viewport.imagePoint(viewport.viewPoint(image)) == image)
    #expect(viewport.viewRect(CGRect(x: 10, y: 20, width: 5, height: 1)) == CGRect(x: -95, y: 100, width: 15, height: 3))
}

@Test func zoomingAboutAPointKeepsThatPixelUnderIt() {
    let viewport = Viewport.fit(canvas, in: view, maxScale: 0.5)
    let cursor = CGPoint(x: 333, y: 271)
    let under = viewport.imagePoint(cursor)
    for scale in [0.25, 1, 2, 4] as [CGFloat] {
        let zoomed = viewport.zoomed(to: scale, about: cursor)
        #expect(zoomed.scale == scale)
        let back = zoomed.viewPoint(under)
        #expect(abs(back.x - cursor.x) < 1e-9 && abs(back.y - cursor.y) < 1e-9)
    }
}

@Test func clampingCentresACanvasSmallerThanTheView() {
    let wandered = Viewport(scale: 0.5, origin: CGPoint(x: -900, y: 4000))
    #expect(wandered.clamped(to: canvas, in: view) == Viewport.fit(canvas, in: view, maxScale: 0.5))
    // A fitted viewport is already clamped.
    let fit = Viewport.fit(canvas, in: CGSize(width: 517, height: 333), maxScale: 1)
    #expect(fit.clamped(to: canvas, in: CGSize(width: 517, height: 333)) == fit)
}

@Test func clampingStopsTheCanvasScrollingMoreThanTheInsetPastAnEdge() {
    // At 4 points per pixel the canvas is 1600 × 1200 pt, larger than the view both ways.
    let far = Viewport(scale: 4, origin: CGPoint(x: 500, y: -5000)).clamped(to: canvas, in: view)
    #expect(far.origin == CGPoint(x: Viewport.inset, y: 600 - Viewport.inset - 1200))
    let inside = Viewport(scale: 4, origin: CGPoint(x: -300, y: -200))
    #expect(inside.clamped(to: canvas, in: view) == inside)
    // A canvas that grew left keeps its own left edge, not the image's, within reach.
    let grown = CGRect(x: -100, y: 0, width: 500, height: 300)
    #expect(Viewport(scale: 4, origin: CGPoint(x: 1000, y: 0)).clamped(to: grown, in: view).origin.x == 400 + Viewport.inset)
}

@Test func panningMovesTheOrigin() {
    let viewport = Viewport(scale: 2, origin: CGPoint(x: 10, y: 20))
    #expect(viewport.panned(by: CGVector(dx: -15, dy: 7)) == Viewport(scale: 2, origin: CGPoint(x: -5, y: 27)))
}

@Test func zoomStepsWalkTheLadderFromAnyZoom() {
    #expect(Viewport.zoom(after: 1) == 1.5)
    #expect(Viewport.zoom(before: 1) == 0.75)
    // A fitted zoom between steps goes to the neighbouring step.
    #expect(Viewport.zoom(after: 0.62) == 0.75)
    #expect(Viewport.zoom(before: 0.62) == 0.5)
    // A float a hair off a step counts as that step.
    #expect(Viewport.zoom(after: 0.9999999) == 1.5)
    // The ends hold, and a fit smaller than the smallest step never zooms in on ⌘-.
    #expect(Viewport.zoom(after: Viewport.maxZoom) == Viewport.maxZoom)
    #expect(Viewport.zoom(before: Viewport.minZoom) == Viewport.minZoom)
    #expect(Viewport.zoom(before: 0.04) == 0.04)
    #expect(Viewport.zoom(after: 0.04) == Viewport.minZoom)
}

@Test func pinchZoomStaysInRangeButCanReachAFitBelowIt() {
    #expect(Viewport.clampedZoom(50, fit: 0.5) == Viewport.maxZoom)
    #expect(Viewport.clampedZoom(0.01, fit: 0.5) == Viewport.minZoom)
    #expect(Viewport.clampedZoom(0.01, fit: 0.04) == 0.04)
    #expect(Viewport.clampedZoom(2.5, fit: 0.5) == 2.5)
}

@Test func zoomIsRelativeToActualSize() {
    // On a 2× capture, actual size is half a point per pixel.
    #expect(Viewport.scale(forZoom: 4, pixelsPerPoint: 2) == 2)
    #expect(Viewport(scale: 2, origin: .zero).zoom(pixelsPerPoint: 2) == 4)
}

/// Done when: you can annotate at 400% zoom, and the shapes land on the right pixels in the export.
@Test func aShapeDrawnAt400PercentLandsOnThePixelsUnderTheCursor() throws {
    // A 400 × 300 px Retina capture fits the 800 × 600 pt view at actual size, then zooms to 400% about the centre and scrolls.
    let fit = Viewport.fit(canvas, in: view, maxScale: 0.5)
    let zoomed = fit.zoomed(to: Viewport.scale(forZoom: 4, pixelsPerPoint: 2), about: CGPoint(x: 400, y: 300))
    #expect(zoomed.origin == .zero)
    let viewport = zoomed.panned(by: CGVector(dx: -14, dy: -14)).clamped(to: canvas, in: view)
    #expect(viewport.origin == CGPoint(x: -14, y: -14))

    // A drag from (100, 100) to (180, 140) pt covers pixels 57…97 across and 57…77 down.
    let start = viewport.imagePoint(CGPoint(x: 100, y: 100))
    let end = viewport.imagePoint(CGPoint(x: 180, y: 140))
    #expect(start == CGPoint(x: 57, y: 57))
    #expect(end == CGPoint(x: 97, y: 77))
    var doc = EditorDocument(base: solidImage(width: 400, height: 300))
    doc.annotations.append(Annotation(kind: .rect(Geometry.normalized(from: start, to: end)), color: blue, lineWidth: 2))
    let image = try #require(AnnotationRenderer.flatten(doc))

    // The 2 px stroke straddles each edge: pixels 56–57 and 96–97 across, and nothing outside it.
    for x in [56, 57, 96, 97] {
        #expect(isBlue(try pixel(image, x: x, y: 67)))
    }
    for x in [54, 59, 77, 94, 99] {
        #expect(isRed(try pixel(image, x: x, y: 67)))
    }
    for y in [56, 57, 76, 77] {
        #expect(isBlue(try pixel(image, x: 77, y: y)))
    }
    for y in [54, 59, 67, 74, 79] {
        #expect(isRed(try pixel(image, x: 77, y: y)))
    }
}
