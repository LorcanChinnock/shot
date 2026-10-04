import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let red = RGBA.presets[0]

/// One of every kind, inside a 400 × 300 image.
private let everyKind: [Annotation] = [
    Annotation(kind: .arrow(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 70)), color: red, lineWidth: 4),
    Annotation(kind: .line(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 70)), color: red, lineWidth: 4),
    Annotation(kind: .rect(CGRect(x: 100, y: 100, width: 80, height: 40)), color: red, lineWidth: 4),
    Annotation(kind: .ellipse(CGRect(x: 100, y: 100, width: 80, height: 40)), color: red, lineWidth: 4),
    Annotation(kind: .highlight(CGRect(x: 100, y: 100, width: 80, height: 40)), color: red, lineWidth: 4),
    Annotation(kind: .pixelate(CGRect(x: 100, y: 100, width: 80, height: 40)), color: red, lineWidth: 4),
    Annotation(kind: .blur(CGRect(x: 100, y: 100, width: 80, height: 40)), color: red, lineWidth: 4),
    Annotation(kind: .spotlight(CGRect(x: 100, y: 100, width: 80, height: 40)), color: red, lineWidth: 4),
    Annotation(kind: .text("Hello\nthere", origin: CGPoint(x: 50, y: 60), fontSize: 24), color: red, lineWidth: 4),
    Annotation(kind: .counter(3, center: CGPoint(x: 200, y: 150)), color: red, lineWidth: 4),
    Annotation(kind: .note("Remember", rect: CGRect(x: 40, y: 40, width: 160, height: 0)), color: RGBA.presets[2], lineWidth: 8),
]

private func document(_ annotations: [Annotation] = []) -> EditorDocument {
    EditorDocument(base: solidImage(width: 400, height: 300), annotations: annotations)
}

/// `annotation` moved by `dx`, `dy`, keeping its id, for comparing shapes.
private func moved(_ annotation: Annotation, _ dx: CGFloat, _ dy: CGFloat) -> Annotation {
    var copy = annotation
    copy.offset(by: CGVector(dx: dx, dy: dy))
    return copy
}

// MARK: Serialisation

@Test(arguments: everyKind)
func everyKindSurvivesTheClipboard(annotation: Annotation) throws {
    let data = try AnnotationClipboard.data(for: annotation)
    #expect(try AnnotationClipboard.annotation(from: data) == annotation)
}

@Test func clipboardRejectsOtherData() {
    #expect(throws: (any Error).self) { try AnnotationClipboard.annotation(from: Data("not an annotation".utf8)) }
    #expect(throws: (any Error).self) { try AnnotationClipboard.annotation(from: Data()) }
}

// MARK: Pasting

@Test(arguments: everyKind)
func pastingAddsAnOffsetCopyWithANewID(annotation: Annotation) throws {
    var doc = document([annotation])
    let id = doc.paste(annotation, step: 10, margin: 16)
    #expect(doc.annotations.count == 2)
    #expect(doc.annotations[0] == annotation)
    let pasted = try #require(doc.annotations.last)
    #expect(pasted.id == id)
    #expect(pasted.id != annotation.id)
    #expect(pasted.color == annotation.color)
    #expect(pasted.lineWidth == annotation.lineWidth)
    #expect(pasted.bounds.origin == CGPoint(x: annotation.bounds.minX + 10, y: annotation.bounds.minY + 10))
    if case .counter = annotation.kind {
        #expect(pasted.kind == .counter(4, center: CGPoint(x: 210, y: 160)))
    } else {
        #expect(pasted.kind == moved(annotation, 10, 10).kind)
    }
}

@Test func pastingAgainCascadesInsteadOfStacking() throws {
    let rect = Annotation(kind: .rect(CGRect(x: 100, y: 100, width: 80, height: 40)), color: red, lineWidth: 4)
    var doc = document([rect])
    doc.paste(rect, step: 10, margin: 16)
    doc.paste(rect, step: 10, margin: 16)
    doc.paste(rect, step: 10, margin: 16)
    #expect(doc.annotations.map { $0.bounds.origin } == [100, 110, 120, 130].map { CGPoint(x: $0, y: $0) })
    #expect(Set(doc.annotations.map(\.id)).count == 4)
}

@Test func duplicatingTheDuplicateStepsOnFromIt() throws {
    let line = Annotation(kind: .line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50)), color: red, lineWidth: 4)
    var doc = document([line])
    let first = doc.paste(line, step: 10, margin: 16)
    let copy = try #require(doc.annotations.first { $0.id == first })
    doc.paste(copy, step: 10, margin: 16)
    #expect(doc.annotations.last?.kind == .line(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 70, y: 70)))
}

@Test func pastingIntoAnEmptyDocumentStillOffsets() {
    let rect = Annotation(kind: .rect(CGRect(x: 100, y: 100, width: 80, height: 40)), color: red, lineWidth: 4)
    var doc = document()
    doc.paste(rect, step: 10, margin: 16)
    #expect(doc.annotations.first?.bounds.origin == CGPoint(x: 110, y: 110))
}

@Test func pasteThatWouldLandOffTheCanvasIsCentredOnIt() throws {
    // Copied from a bigger screenshot, far past this one's edge.
    let far = Annotation(kind: .rect(CGRect(x: 2000, y: 1500, width: 80, height: 40)), color: red, lineWidth: 4)
    var doc = document()
    doc.paste(far, step: 10, margin: 16)
    let pasted = try #require(doc.annotations.first)
    #expect(pasted.bounds == CGRect(x: 160, y: 130, width: 80, height: 40))
    #expect(doc.canvasRect == doc.fullRect)
    // A second paste of the same thing cascades from the centred copy.
    doc.paste(far, step: 10, margin: 16)
    #expect(doc.annotations.last?.bounds.origin == CGPoint(x: 170, y: 140))
}

@Test func pasteThatCrossesTheEdgeGrowsTheCanvas() throws {
    let edge = Annotation(kind: .rect(CGRect(x: 340, y: 100, width: 50, height: 40)), color: red, lineWidth: 4)
    var doc = document([edge])
    doc.paste(edge, step: 20, margin: 16)
    let pasted = try #require(doc.annotations.last)
    #expect(pasted.bounds.maxX == 410)
    #expect(doc.canvasRect.contains(pasted.paintedBounds.insetBy(dx: -16, dy: -16)))
    #expect(doc.canvasRect.minX == 0 && doc.canvasRect.minY == 0 && doc.canvasRect.maxY == 300)
}

@Test func pastedNotesAndBoxesKeepTheirResizeHandles() throws {
    let note = everyKind.last!
    var doc = document([note])
    let id = doc.paste(note, step: 10, margin: 16)
    let pasted = try #require(doc.annotations.first { $0.id == id })
    #expect(pasted.handles.map(\.handle) == note.handles.map(\.handle))
    #expect(zip(pasted.handles, note.handles).allSatisfy { $0.point == CGPoint(x: $1.point.x + 10, y: $1.point.y + 10) })
}

// MARK: Nudging

@Test(arguments: [(NudgeDirection.left, CGVector(dx: -1, dy: 0)), (.right, CGVector(dx: 1, dy: 0)), (.up, CGVector(dx: 0, dy: -1)), (.down, CGVector(dx: 0, dy: 1))])
func nudgesOnePixelOrTenWithShift(direction: NudgeDirection, unit: CGVector) {
    #expect(direction.offset(large: false) == unit)
    #expect(direction.offset(large: true) == CGVector(dx: unit.dx * 10, dy: unit.dy * 10))
}

@Test(arguments: everyKind)
func nudgingMovesOnlyThatAnnotation(annotation: Annotation) {
    let other = Annotation(kind: .rect(CGRect(x: 5, y: 5, width: 20, height: 20)), color: red, lineWidth: 4)
    var doc = document([other, annotation])
    doc.move(annotation.id, by: CGVector(dx: -10, dy: 1), margin: 16)
    #expect(doc.annotations == [other, moved(annotation, -10, 1)])
}

@Test func nudgingPastTheEdgeGrowsTheCanvas() {
    let rect = Annotation(kind: .rect(CGRect(x: 0, y: 100, width: 50, height: 40)), color: red, lineWidth: 4)
    var doc = document([rect])
    doc.move(rect.id, by: CGVector(dx: -1, dy: 0), margin: 16)
    #expect(doc.canvasRect.minX == -19)
    #expect(doc.canvasRect.maxX == 400)
}

@Test func nudgingAMissingAnnotationChangesNothing() {
    let rect = Annotation(kind: .rect(CGRect(x: 0, y: 100, width: 50, height: 40)), color: red, lineWidth: 4)
    var doc = document([rect])
    let before = doc.snapshot
    doc.move(UUID(), by: CGVector(dx: 10, dy: 10), margin: 16)
    #expect(doc.snapshot == before)
}
