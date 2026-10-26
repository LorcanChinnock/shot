import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let white = RGBA(1, 1, 1)
private let dark = RGBA(0.1, 0.1, 0.1)

private func caption(_ string: String = "Click Save", fill: RGBA? = dark) -> Annotation {
    Annotation(kind: .text(string, origin: CGPoint(x: 60, y: 40), fontSize: 20), color: white, fill: fill, lineWidth: 4)
}

@Test func textWithAFillHasABoxAroundIt() throws {
    let text = caption()
    let box = try #require(text.textBox)
    #expect(box.minX == text.bounds.minX - 8 && box.maxX == text.bounds.maxX + 8)
    #expect(box.minY == text.bounds.minY - 4 && box.maxY == text.bounds.maxY + 4)
    #expect(text.paintedBounds.contains(box))
    #expect(text.hitTest(CGPoint(x: box.minX + 1, y: box.minY + 1), tolerance: 0))
    #expect(text.textBoxCornerRadius == 4)
}

@Test func textWithoutAFillHasNoBox() {
    let text = caption(fill: nil)
    #expect(text.textBox == nil)
    #expect(text.paintedBounds == text.bounds)
    #expect(!text.hitTest(CGPoint(x: text.bounds.minX - 6, y: text.bounds.minY - 3), tolerance: 0))
}

@Test func theBoxIsDrawnBehindTheText() throws {
    let text = caption()
    let box = try #require(text.textBox)
    let doc = EditorDocument(base: solidImage(width: 300, height: 120), annotations: [text])
    let image = try #require(AnnotationRenderer.flatten(doc))
    // Inside the padding, left of the first letter: the box's colour.
    let inside = try pixel(image, box.minX + 4, box.midY)
    #expect(inside[0] < 0.15 && inside[1] < 0.15 && inside[2] < 0.15)
    // Just outside the box: the image underneath.
    let outside = try pixel(image, box.minX - 3, box.midY)
    let plain = try #require(AnnotationRenderer.flatten(EditorDocument(base: solidImage(width: 300, height: 120), annotations: [])))
    #expect(try outside == pixel(plain, box.minX - 3, box.midY))
    // The text is drawn over the box: somewhere along its middle, white.
    var brightest: CGFloat = 0
    for x in stride(from: text.bounds.minX, to: text.bounds.maxX, by: 0.5) {
        brightest = max(brightest, try pixel(image, x, text.bounds.midY)[0])
    }
    #expect(brightest > 0.8)
}
