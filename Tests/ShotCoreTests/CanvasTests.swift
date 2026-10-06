import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let blue = RGBA(0, 0, 1)

private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
    let data = try #require(image.dataProvider?.data as Data?)
    let offset = y * image.bytesPerRow + x * 4
    return Array(data[offset..<offset + 4])
}

// The test images use device RGB, so sRGB annotation colours can land a step off their exact values.
private func isBlue(_ p: [UInt8]) -> Bool { p[0] < 30 && p[1] < 30 && p[2] > 225 && p[3] == 255 }
private func isRed(_ p: [UInt8]) -> Bool { p[0] > 225 && p[1] < 30 && p[2] < 30 && p[3] == 255 }
private func isWhite(_ p: [UInt8]) -> Bool { p.allSatisfy { $0 > 245 } }

@Test func canvasStartsAtTheImageBounds() {
    let doc = EditorDocument(base: solidImage(width: 200, height: 100))
    #expect(doc.canvasRect == CGRect(x: 0, y: 0, width: 200, height: 100))
    #expect(doc.background == nil)
    #expect(!doc.hasPadding)
}

@Test func paintedBoundsCoverStrokesAndArrowheads() {
    let line = Annotation(kind: .line(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 10)), color: blue, lineWidth: 4)
    #expect(line.paintedBounds == CGRect(x: 8, y: 8, width: 104, height: 4))
    // The head is max(12, 4 × 4) = 16 long and 16 × 0.45 = 7.2 wide on each side.
    let arrow = Annotation(kind: .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 10)), color: blue, lineWidth: 4)
    #expect(arrow.paintedBounds.contains(CGRect(x: 8, y: 2.8, width: 104, height: 14.4)))
    let highlight = Annotation(kind: .highlight(CGRect(x: 0, y: 0, width: 50, height: 20)), color: blue, lineWidth: 4)
    #expect(highlight.paintedBounds == highlight.bounds)
}

@Test func growsOnlyWhenAnAnnotationCrossesTheEdge() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    let inside = Annotation(kind: .rect(CGRect(x: 20, y: 20, width: 40, height: 40)), color: blue, lineWidth: 4)
    doc.grow(toFit: inside, margin: 10)
    #expect(doc.canvasRect == doc.fullRect)

    let label = Annotation(kind: .counter(1, center: CGPoint(x: 260, y: 50)), color: blue, lineWidth: 4)
    doc.grow(toFit: label, margin: 10)
    #expect(doc.canvasRect.contains(label.paintedBounds.insetBy(dx: -10, dy: -10)))
    #expect(doc.canvasRect.minX == 0 && doc.canvasRect.minY == 0 && doc.canvasRect.maxY == 100)
    #expect(doc.canvasRect == doc.canvasRect.integral)
    #expect(doc.hasPadding)

    let above = Annotation(kind: .text("Note", origin: CGPoint(x: 40, y: -60), fontSize: 20), color: blue, lineWidth: 4)
    doc.grow(toFit: above, margin: 10)
    #expect(doc.canvasRect.minY <= -70)
}

@Test func growingNeverReopensACropOrReactsToAStrokeOnTheEdge() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    // A rect drawn along the image edge only pokes its stroke past it.
    doc.grow(toFit: Annotation(kind: .rect(CGRect(x: 0, y: 0, width: 200, height: 100)), color: blue, lineWidth: 8), margin: 10)
    #expect(doc.canvasRect == doc.fullRect)

    // Cropped to the middle, a shape past every side leaves the crop as it is.
    doc.crop(to: CGRect(x: 50, y: 20, width: 100, height: 60))
    doc.grow(toFit: Annotation(kind: .rect(CGRect(x: 40, y: 10, width: 120, height: 80)), color: blue, lineWidth: 4), margin: 10)
    #expect(doc.canvasRect == CGRect(x: 50, y: 20, width: 100, height: 60))

    // Cropped flush with the right edge, the right side still grows into padding; the cropped left stays.
    doc.canvasRect = CGRect(x: 100, y: 0, width: 100, height: 100)
    doc.grow(toFit: Annotation(kind: .line(from: CGPoint(x: 90, y: 50), to: CGPoint(x: 250, y: 50)), color: blue, lineWidth: 4), margin: 10)
    #expect(doc.canvasRect == CGRect(x: 100, y: 0, width: 162, height: 100))
}

@Test func fitToContentHoldsTheImageAndEveryAnnotation() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    doc.fitToContent(margin: 10)
    #expect(doc.canvasRect == doc.fullRect)

    let arrow = Annotation(kind: .arrow(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 300, y: 150)), color: blue, lineWidth: 4)
    let note = Annotation(kind: .text("Look", origin: CGPoint(x: -80, y: -40), fontSize: 20), color: blue, lineWidth: 4)
    doc.annotations = [arrow, note]
    doc.fitToContent(margin: 10)
    let expected = doc.fullRect.union(arrow.paintedBounds.insetBy(dx: -10, dy: -10)).union(note.paintedBounds.insetBy(dx: -10, dy: -10)).integral
    #expect(doc.canvasRect == expected)

    // Fit shrinks too, once the annotations move back inside.
    doc.annotations = [Annotation(kind: .rect(CGRect(x: 20, y: 20, width: 40, height: 40)), color: blue, lineWidth: 4)]
    doc.fitToContent(margin: 10)
    #expect(doc.canvasRect == doc.fullRect)
}

@Test func trimToImageDropsThePaddingButKeepsACrop() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    doc.canvasRect = CGRect(x: -50, y: -20, width: 400, height: 200)
    doc.trimToImage()
    #expect(doc.canvasRect == doc.fullRect)

    doc.canvasRect = CGRect(x: 150, y: 50, width: 150, height: 100)
    doc.trimToImage()
    #expect(doc.canvasRect == CGRect(x: 150, y: 50, width: 50, height: 50))

    // A crop that lies wholly in the padding has no image left, so trim goes back to the image.
    doc.canvasRect = CGRect(x: 250, y: 0, width: 50, height: 50)
    doc.trimToImage()
    #expect(doc.canvasRect == doc.fullRect)
}

@Test func cropStaysInsideTheCanvasAndCanReachThePadding() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    doc.crop(to: CGRect(x: -30, y: 10.4, width: 100, height: 40))
    #expect(doc.canvasRect == CGRect(x: 0, y: 10, width: 70, height: 41))

    doc.canvasRect = CGRect(x: -100, y: -100, width: 400, height: 300)
    doc.crop(to: CGRect(x: -80, y: -60, width: 120, height: 100))
    #expect(doc.canvasRect == CGRect(x: -80, y: -60, width: 120, height: 100))
    #expect(doc.exportSize == CGSize(width: 120, height: 100))
}

@Test func snapshotRestoresCanvasAndBackground() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    let before = doc.snapshot
    doc.canvasRect = CGRect(x: -20, y: 0, width: 220, height: 100)
    doc.background = RGBA(1, 1, 1)
    let after = doc.snapshot
    #expect(before != after)
    doc.restore(before)
    #expect(doc.canvasRect == doc.fullRect)
    #expect(doc.background == nil)
    doc.restore(after)
    #expect(doc.canvasRect == CGRect(x: -20, y: 0, width: 220, height: 100))
    #expect(doc.background == RGBA(1, 1, 1))
}

@Test func undoAndRedoRestoreAGrownCanvas() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    var stack = UndoStack<EditorSnapshot>()
    let label = Annotation(kind: .text("Outside", origin: CGPoint(x: 220, y: 40), fontSize: 20), color: blue, lineWidth: 4)
    stack.record(doc.snapshot)
    doc.annotations.append(label)
    doc.grow(toFit: label, margin: 10)
    let grown = doc.canvasRect
    #expect(grown.maxX > 220)

    doc.restore(stack.undo(from: doc.snapshot)!)
    #expect(doc.canvasRect == doc.fullRect)
    #expect(doc.annotations.isEmpty)
    doc.restore(stack.redo(from: doc.snapshot)!)
    #expect(doc.canvasRect == grown)
    #expect(doc.annotations == [label])
}

@Test func defaultBackgroundIsTransparentOnlyForPNG() {
    #expect(EditorDocument.defaultBackground(for: .png) == nil)
    #expect(EditorDocument.defaultBackground(for: .jpeg) == RGBA(1, 1, 1))
}

@Test func exportRendersAnArrowIntoALabelOutsideTheImage() throws {
    // A 100 × 100 red image, an arrow from its middle to a counter 60 px to its right.
    var doc = EditorDocument(base: solidImage(width: 100, height: 100))
    let arrow = Annotation(kind: .arrow(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 50)), color: blue, lineWidth: 4)
    let label = Annotation(kind: .counter(1, center: CGPoint(x: 160, y: 50)), color: blue, lineWidth: 4)
    for annotation in [arrow, label] {
        doc.annotations.append(annotation)
        doc.grow(toFit: annotation, margin: 8)
    }
    let image = try #require(AnnotationRenderer.flatten(doc))
    #expect(CGSize(width: image.width, height: image.height) == doc.exportSize)
    #expect(image.width > 170)
    let origin = doc.canvasRect.origin
    func at(_ x: CGFloat, _ y: CGFloat) throws -> [UInt8] { try pixel(image, x: Int(x - origin.x), y: Int(y - origin.y)) }
    // Arrow shaft inside the image, the label outside it, untouched image, and transparent padding.
    #expect(isBlue(try at(70, 50)))
    #expect(isBlue(try at(160, 32)))
    #expect(isRed(try at(20, 20)))
    #expect(try at(130, 10)[3] == 0)
}

@Test func exportFillsThePaddingWithTheBackground() throws {
    var doc = EditorDocument(base: solidImage(width: 100, height: 100))
    doc.canvasRect = CGRect(x: -20, y: -10, width: 140, height: 120)
    doc.background = RGBA(1, 1, 1)
    let image = try #require(AnnotationRenderer.flatten(doc))
    #expect(image.width == 140 && image.height == 120)
    #expect(isWhite(try pixel(image, x: 5, y: 5)))
    #expect(isRed(try pixel(image, x: 70, y: 60)))
    #expect(isWhite(try pixel(image, x: 135, y: 115)))
}

@Test func shrinkingPullsPaddingBackAsAnAnnotationMovesOrGoes() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    let label = Annotation(kind: .counter(1, center: CGPoint(x: 260, y: 50)), color: blue, lineWidth: 4)
    doc.annotations.append(label)
    doc.grow(toFit: label, margin: 10)
    #expect(doc.canvasRect.maxX > 200)

    doc.move(label.id, by: CGVector(dx: -40, dy: 0), margin: 10)
    #expect(doc.canvasRect.maxX < 270 && doc.canvasRect.maxX > 200)

    doc.move(label.id, by: CGVector(dx: -200, dy: 0), margin: 10)
    #expect(doc.canvasRect == doc.fullRect)

    doc.move(label.id, by: CGVector(dx: 200, dy: 0), margin: 10)
    doc.annotations.removeAll()
    doc.shrinkPadding(margin: 10)
    #expect(doc.canvasRect == doc.fullRect)
}

@Test func shrinkingKeepsACrop() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    doc.crop(to: CGRect(x: 50, y: 20, width: 100, height: 60))
    doc.shrinkPadding(margin: 10)
    #expect(doc.canvasRect == CGRect(x: 50, y: 20, width: 100, height: 60))
}
