import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let black = RGBA(0, 0, 0)
private let sentence = "The balance on this invoice is wrong and should be checked"

private func wrapped(_ string: String = sentence, width: CGFloat? = 160) -> Annotation {
    var text = Annotation(kind: .text(string, origin: CGPoint(x: 40, y: 30), fontSize: 20), color: black, lineWidth: 4)
    text.textWidth = width
    return text
}

@Test func aClickPlacesTextAsWideAsWhatsTyped() {
    let placed = TextLayout.placement(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: 11), fontSize: 20, threshold: 4)
    #expect(placed.origin == CGPoint(x: 10, y: 10))
    #expect(placed.width == nil)
}

@Test func aDragPlacesABoxFromItsLeftEdgeAsWideAsTheDrag() {
    let placed = TextLayout.placement(from: CGPoint(x: 200, y: 50), to: CGPoint(x: 80, y: 90), fontSize: 20, threshold: 4)
    #expect(placed.origin == CGPoint(x: 80, y: 50))
    #expect(placed.width == 120)
}

@Test func aNarrowDragStillGivesRoomForAFewLetters() {
    let placed = TextLayout.placement(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: 80), fontSize: 20, threshold: 4)
    #expect(placed.width == TextLayout.minWidth(fontSize: 20))
}

@Test func textInABoxWrapsToItsWidth() {
    let plain = wrapped(width: nil)
    let boxed = wrapped()
    #expect(plain.bounds.width > 160)
    #expect(boxed.bounds.width == 160)
    #expect(boxed.bounds.height > plain.bounds.height * 2)
    let layout = TextLayout(string: sentence, fontSize: 20, color: black, width: 160)
    #expect(layout.lines.allSatisfy { $0.width - $0.trailingWhitespaceWidth <= 160 })
    #expect(layout.lines.count > 2)
}

@Test func aLineBreakInABoxStartsANewLine() {
    let one = TextLayout(string: "Hi", fontSize: 20, color: black, width: 160)
    let two = TextLayout(string: "Hi\nthere", fontSize: 20, color: black, width: 160)
    #expect(two.lines.count == one.lines.count + 1)
}

@Test func theWrappedTextIsHitWhereItsLowerLinesAre() {
    let boxed = wrapped()
    let lowLeft = CGPoint(x: boxed.bounds.minX + 4, y: boxed.bounds.maxY - 4)
    #expect(boxed.hitTest(lowLeft, tolerance: 0))
    #expect(!wrapped(width: nil).hitTest(lowLeft, tolerance: 0))
    #expect(!boxed.hitTest(CGPoint(x: boxed.bounds.maxX + 20, y: boxed.bounds.minY + 4), tolerance: 0))
}

@Test func onlyATextBoxHasSideHandles() {
    #expect(wrapped(width: nil).handles.isEmpty)
    let boxed = wrapped()
    #expect(boxed.handles.map(\.handle) == [.left, .right])
}

@Test func draggingATextBoxsSideRewrapsIt() {
    let boxed = wrapped()
    var wider = boxed
    wider.resize(.right, to: CGPoint(x: boxed.bounds.maxX + 200, y: 0), tolerance: 4)
    #expect(wider.textWidth == 360)
    #expect(wider.bounds.minX == boxed.bounds.minX)
    #expect(wider.bounds.height < boxed.bounds.height)

    var fromLeft = boxed
    fromLeft.resize(.left, to: CGPoint(x: 0, y: 0), tolerance: 4)
    #expect(fromLeft.bounds.minX == 0 && fromLeft.bounds.maxX == boxed.bounds.maxX)
    #expect(fromLeft.textWidth == 200)
}

@Test func aTextBoxNeverFlipsOrGetsNarrowerThanItsMinimum() {
    let boxed = wrapped()
    var squeezed = boxed
    squeezed.resize(.left, to: CGPoint(x: boxed.bounds.maxX + 100, y: 0), tolerance: 4)
    #expect(squeezed.textWidth == TextLayout.minWidth(fontSize: 20))
    #expect(squeezed.bounds.maxX == boxed.bounds.maxX)
}

@Test func theTextBoxsWidthIsSavedAndOlderTextStillOpens() throws {
    let boxed = wrapped()
    #expect(try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(boxed)) == boxed)
    let plain = wrapped(width: nil)
    let saved = try JSONEncoder().encode(plain)
    #expect(!String(decoding: saved, as: UTF8.self).contains("wrapWidth"))
    #expect(try JSONDecoder().decode(Annotation.self, from: saved).textWidth == nil)
}

@Test func onlyTextTakesAWrapWidth() {
    var counter = Annotation(kind: .counter(1, center: .zero), color: black, lineWidth: 4)
    counter.textWidth = 100
    #expect(counter.textWidth == nil)
}

@Test func aWrappedTextBoxIsDrawnOnItsLowerLines() throws {
    let boxed = wrapped(String(repeating: "W ", count: 30), width: 120)
    let doc = EditorDocument(base: solidImage(width: 300, height: 400), annotations: [boxed])
    let image = try #require(AnnotationRenderer.flatten(doc))
    let bounds = boxed.bounds
    // The last line's band holds dark ink somewhere; past the box's right side there's none.
    let lastLine = (Int(bounds.minX)..<Int(bounds.maxX)).map { try? pixel(image, CGFloat($0), bounds.maxY - 10) }
    #expect(lastLine.contains { ($0?[0] ?? 1) < 0.5 })
    let pastRight = (Int(bounds.maxX + 4)..<Int(bounds.maxX + 60)).map { try? pixel(image, CGFloat($0), bounds.minY + 10) }
    #expect(!pastRight.contains { ($0?[0] ?? 1) < 0.5 })
}

@Test func scalingATextBoxScalesItsWidth() {
    let boxed = wrapped()
    #expect(boxed.scaled(by: 2).textWidth == 320)
}

@Test func theTextToolsHintSaysADragMakesABox() {
    let hint = CanvasHint.hint(tool: .text, selection: [], isTyping: false)
    #expect(hint?.parts.map(\.action) == ["drag for a text box"])
}
