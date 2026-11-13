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

private func box(_ string: String = sentence, width: CGFloat = 160, height: CGFloat = 200) -> Annotation {
    var text = wrapped(string, width: width)
    text.textBoxHeight = height
    return text
}

@Test func aClickPlacesTextAsWideAsWhatsTyped() {
    #expect(TextLayout.box(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: 11), fontSize: 20, threshold: 4) == nil)
}

@Test func aDragPlacesABoxFromCornerToCorner() {
    let dragged = TextLayout.box(from: CGPoint(x: 200, y: 90), to: CGPoint(x: 80, y: 50), fontSize: 20, threshold: 4)
    #expect(dragged == CGRect(x: 80, y: 50, width: 120, height: 40))
}

@Test func aNarrowDragStillGivesRoomForAFewLetters() {
    let dragged = TextLayout.box(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: 80), fontSize: 20, threshold: 4)
    #expect(dragged == CGRect(x: 10, y: 10, width: TextLayout.minWidth(fontSize: 20), height: 70))
}

@Test func aTextBoxIsAsTallAsItsDragUntilTheTextNeedsMore() {
    #expect(TextLayout.boxSize(text: CGSize(width: 100, height: 30), minHeight: 80) == CGSize(width: 100, height: 80))
    #expect(TextLayout.boxSize(text: CGSize(width: 100, height: 120), minHeight: 80) == CGSize(width: 100, height: 120))
    #expect(TextLayout.boxSize(text: CGSize(width: 100, height: 30), minHeight: nil) == CGSize(width: 100, height: 30))

    let short = box("Hi", height: 200)
    #expect(short.bounds == CGRect(x: 40, y: 30, width: 160, height: 200))
    let long = box(String(repeating: sentence + " ", count: 4), height: 20)
    #expect(long.bounds.height > 20)
}

@Test func theWholeTextBoxIsHitNotJustItsText() {
    let short = box("Hi", height: 200)
    let emptyCorner = CGPoint(x: short.bounds.maxX - 4, y: short.bounds.maxY - 4)
    #expect(short.hitTest(emptyCorner, tolerance: 0))
    #expect(!wrapped("Hi").hitTest(emptyCorner, tolerance: 0))
}

@Test func aFilledTextBoxFillsTheWholeBox() throws {
    var short = box("Hi", height: 200)
    short.fill = RGBA(0, 0, 1)
    let box = try #require(short.textBox)
    #expect(box.contains(CGPoint(x: 190, y: 225)))
}

@Test func aTextBoxsHeightIsSavedAndOlderTextStillOpens() throws {
    let tall = box()
    #expect(try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(tall)) == tall)
    let saved = try JSONEncoder().encode(wrapped())
    #expect(!String(decoding: saved, as: UTF8.self).contains("boxHeight"))
    #expect(try JSONDecoder().decode(Annotation.self, from: saved).textBoxHeight == nil)
    var counter = Annotation(kind: .counter(1, center: .zero), color: black, lineWidth: 4)
    counter.textBoxHeight = 100
    #expect(counter.textBoxHeight == nil)
}

@Test func draggingATextBoxsTopOrBottomChangesTheHeightItKeepsNotTheTextSize() {
    let tall = box("Hi", height: 200)
    var taller = tall
    taller.resize(.bottom, to: CGPoint(x: 0, y: 330), tolerance: 4)
    #expect(taller.bounds == CGRect(x: 40, y: 30, width: 160, height: 300))
    #expect(taller.textSize == 20)

    var fromTop = tall
    fromTop.resize(.top, to: CGPoint(x: 0, y: 130), tolerance: 4)
    #expect(fromTop.bounds == CGRect(x: 40, y: 130, width: 160, height: 100))

    // Neither side goes past the text, and the box never flips.
    let line = TextLayout(string: "Hi", fontSize: 20, color: black, width: 160).size.height
    var squashed = tall
    squashed.resize(.bottom, to: CGPoint(x: 0, y: 0), tolerance: 4)
    #expect(squashed.bounds.minY == 30 && squashed.bounds.height == line)
    var pushedDown = tall
    pushedDown.resize(.top, to: CGPoint(x: 0, y: 1000), tolerance: 4)
    #expect(pushedDown.bounds.maxY == 230 && pushedDown.bounds.height == line)
}

@Test func aTextBoxsCornerChangesItsWidthAndHeight() {
    var resized = box("Hi", height: 200)
    resized.resize(.bottomRight, to: CGPoint(x: 400, y: 330), tolerance: 4)
    #expect(resized.bounds == CGRect(x: 40, y: 30, width: 360, height: 300))
    #expect(resized.textSize == 20)

    // Shift keeps its proportions, as a shape's corner does.
    var constrained = box("Hi", width: 160, height: 200)
    constrained.resize(.bottomRight, to: CGPoint(x: 360, y: 260), tolerance: 4, constrain: true)
    #expect(constrained.bounds == CGRect(x: 40, y: 30, width: 320, height: 400))
}

@Test func aTextBoxsSideKeepsTheHeightItWasGiven() {
    var wider = box("Hi", height: 200)
    wider.resize(.right, to: CGPoint(x: 400, y: 0), tolerance: 4)
    #expect(wider.textBoxHeight == 200)
    #expect(wider.bounds.height == 200)
}

@Test func scalingATextBoxScalesItsHeight() {
    #expect(box(height: 200).scaled(by: 2).textBoxHeight == 400)
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

@Test func onlyATextBoxHasHandlesOnEveryCornerAndSide() {
    #expect(wrapped(width: nil).handles.isEmpty)
    let boxed = wrapped()
    #expect(boxed.handles.map(\.handle) == AnnotationHandle.box)
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
