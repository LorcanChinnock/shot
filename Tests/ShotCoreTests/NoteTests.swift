import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import ShotCore

private let yellow = RGBA.presets[2]

private func note(_ string: String, _ rect: CGRect, color: RGBA = yellow) -> Annotation {
    Annotation(kind: .note(string, rect: rect), color: color, lineWidth: 4)
}

private func layout(_ annotation: Annotation) throws -> NoteLayout {
    try #require(annotation.noteLayout)
}

private func contrast(_ a: RGBA, _ b: RGBA) -> CGFloat {
    let (hi, lo) = (max(a.relativeLuminance, b.relativeLuminance), min(a.relativeLuminance, b.relativeLuminance))
    return (hi + 0.05) / (lo + 0.05)
}

private let longText = "Sticky notes wrap their text to the width of the note, so a long comment stays readable."

// MARK: Colour

@Test func noteFillIsAPaleTintOfThePresetWithReadableText() {
    let fill = yellow.noteFill
    #expect(fill.r > 0.95 && fill.g > 0.9 && fill.b > 0.5 && fill.b < 0.8)
    for preset in RGBA.presets {
        #expect(contrast(preset.noteFill, preset.noteFill.contrastingInk) >= 4.5)
    }
}

@Test func textColourAdaptsToTheFill() {
    #expect(RGBA(0, 0, 0).contrastingInk == RGBA(1, 1, 1))
    #expect(RGBA(0.1, 0.1, 0.4).contrastingInk == RGBA(1, 1, 1))
    #expect(RGBA(1, 1, 1).contrastingInk != RGBA(1, 1, 1))
    #expect(RGBA(1, 0.95, 0.6).contrastingInk.relativeLuminance < 0.05)
}

// MARK: Layout

@Test func layoutWrapsToTheNoteWidth() throws {
    let wide = try layout(note(longText, CGRect(x: 10, y: 20, width: 600, height: 0)))
    let narrow = try layout(note(longText, CGRect(x: 10, y: 20, width: 160, height: 0)))
    #expect(narrow.lines.count > wide.lines.count)
    #expect(narrow.frame.origin == CGPoint(x: 10, y: 20))
    #expect(narrow.frame.width == 160)
    #expect(narrow.frame.height > wide.frame.height)
    for line in narrow.lines {
        #expect(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line)) <= narrow.textRect.width + 0.5)
    }
    #expect(narrow.frame.height == narrow.lineHeight * CGFloat(narrow.lines.count) + narrow.padding * 2)
}

@Test func layoutBreaksAWordLongerThanTheNote() throws {
    let l = try layout(note(String(repeating: "W", count: 40), CGRect(x: 0, y: 0, width: 120, height: 0)))
    #expect(l.lines.count > 1)
    for line in l.lines {
        #expect(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) <= l.textRect.width + 0.5)
    }
}

@Test func layoutKeepsNewlinesAndEmptyNotesHaveOneLine() throws {
    #expect(try layout(note("One\nTwo\n\nFour", CGRect(x: 0, y: 0, width: 400, height: 0))).lines.count == 4)
    let empty = try layout(note("", CGRect(x: 0, y: 0, width: 400, height: 0)))
    #expect(empty.lines.count == 1)
    #expect(empty.frame.height == empty.lineHeight + empty.padding * 2)
}

@Test func noteHeightIsTheRectOrTheTextWhicheverIsTaller() throws {
    let tall = try layout(note("Hi", CGRect(x: 0, y: 0, width: 200, height: 300)))
    #expect(tall.frame.height == 300)
    let short = try layout(note(longText, CGRect(x: 0, y: 0, width: 200, height: 10)))
    #expect(short.frame.height > 10)
    #expect(short.frame.height == short.lineHeight * CGFloat(short.lines.count) + short.padding * 2)
}

@Test func noteWidthNeverDropsBelowTheMinimum() throws {
    let l = try layout(note("Hi", CGRect(x: 0, y: 0, width: 5, height: 0)))
    #expect(l.frame.width == NoteLayout.minWidth(fontSize: l.fontSize))
    #expect(l.textRect.width > 0)
}

@Test func layoutScalesWithTheLineWidth() throws {
    let small = Annotation(kind: .note("Hi", rect: CGRect(x: 0, y: 0, width: 300, height: 0)), color: yellow, lineWidth: 2)
    let large = Annotation(kind: .note("Hi", rect: CGRect(x: 0, y: 0, width: 300, height: 0)), color: yellow, lineWidth: 8)
    #expect(try layout(large).fontSize > layout(small).fontSize)
    #expect(try layout(large).frame.height > layout(small).frame.height)
    #expect(Annotation(kind: .shape(.rectangle, rect: .zero), color: yellow, lineWidth: 4).noteLayout == nil)
}

// MARK: Placement

@Test func clickPlacesADefaultWidthNoteAndDragSetsItsSize() {
    let font: CGFloat = 20
    let click = NoteLayout.placementRect(from: CGPoint(x: 50, y: 60), to: CGPoint(x: 51, y: 61), fontSize: font)
    #expect(click == CGRect(x: 50, y: 60, width: NoteLayout.defaultWidth(fontSize: font), height: 0))
    let drag = NoteLayout.placementRect(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 100), fontSize: font)
    #expect(drag == CGRect(x: 100, y: 100, width: 200, height: 100))
    let thin = NoteLayout.placementRect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 110, y: 160), fontSize: font)
    #expect(thin.width == NoteLayout.minWidth(fontSize: font))
    #expect(thin.height == 60)
}

// MARK: Bounds and hit-testing

@Test func boundsAreTheLaidOutFrame() throws {
    let n = note(longText, CGRect(x: 10, y: 20, width: 160, height: 0))
    #expect(n.bounds == (try layout(n)).frame)
}

@Test func hitTestCoversTheWholeNote() {
    let n = note("Hello", CGRect(x: 100, y: 100, width: 200, height: 100))
    #expect(n.hitTest(CGPoint(x: 200, y: 150), tolerance: 0))
    #expect(n.hitTest(CGPoint(x: 295, y: 195), tolerance: 0))
    #expect(n.hitTest(CGPoint(x: 98, y: 150), tolerance: 3))
    #expect(!n.hitTest(CGPoint(x: 90, y: 150), tolerance: 3))
    #expect(!n.hitTest(CGPoint(x: 200, y: 260), tolerance: 3))
    let list = [Annotation(kind: .highlight(CGRect(x: 0, y: 0, width: 400, height: 400)), color: yellow, lineWidth: 4), n]
    #expect(list.topmostIndex(at: CGPoint(x: 200, y: 150), tolerance: 0) == 1)
}

@Test func paintedBoundsHoldTheShadow() throws {
    let n = note("Hello", CGRect(x: 100, y: 100, width: 200, height: 100))
    let l = try layout(n)
    #expect(n.paintedBounds.contains(n.bounds))
    #expect(n.paintedBounds.maxY >= n.bounds.maxY + l.shadowOffset + l.shadowBlur)
    #expect(n.paintedBounds.minX <= n.bounds.minX - l.shadowBlur)
}

@Test func moveOffsetsTheNote() {
    var n = note("Hello", CGRect(x: 100, y: 100, width: 200, height: 100))
    n.offset(by: CGVector(dx: -30, dy: 15))
    #expect(n.kind == .note("Hello", rect: CGRect(x: 70, y: 115, width: 200, height: 100)))
}

@Test func setTextChangesNotes() {
    var n = note("Hello", CGRect(x: 0, y: 0, width: 200, height: 0))
    n.setText("Bye")
    #expect(n.kind == .note("Bye", rect: CGRect(x: 0, y: 0, width: 200, height: 0)))
    var r = Annotation(kind: .shape(.rectangle, rect: .zero), color: yellow, lineWidth: 4)
    r.setText("Nope")
    #expect(r.kind == .shape(.rectangle, rect: .zero))
}

// MARK: Resize handles

@Test func handlesSitOnTheCornersOfTheNote() {
    let n = note("Hello", CGRect(x: 100, y: 100, width: 200, height: 100))
    #expect(n.handle(at: CGPoint(x: 101, y: 99), tolerance: 4) == .topLeft)
    #expect(n.handle(at: CGPoint(x: 300, y: 100), tolerance: 4) == .topRight)
    #expect(n.handle(at: CGPoint(x: 97, y: 203), tolerance: 4) == .bottomLeft)
    #expect(n.handle(at: CGPoint(x: 300, y: 200), tolerance: 4) == .bottomRight)
    #expect(n.handle(at: CGPoint(x: 200, y: 150), tolerance: 4) == nil)
}

@Test func resizingChangesTheWrapWidthAndKeepsTheOppositeCorner() throws {
    var n = note(longText, CGRect(x: 100, y: 100, width: 400, height: 0))
    let before = try layout(n)
    n.resize(.bottomRight, to: CGPoint(x: 260, y: 100))
    let after = try layout(n)
    #expect(after.frame.minX == 100 && after.frame.minY == 100)
    #expect(after.frame.width == 160)
    #expect(after.lines.count > before.lines.count)

    var left = note("Hi", CGRect(x: 100, y: 100, width: 200, height: 100))
    left.resize(.topLeft, to: CGPoint(x: 50, y: 80))
    #expect(left.bounds == CGRect(x: 50, y: 80, width: 250, height: 120))
}

@Test func resizingClampsAtTheMinimumAndNeverFlips() throws {
    var n = note("Hi", CGRect(x: 100, y: 100, width: 200, height: 100))
    let font = try layout(n).fontSize
    n.resize(.bottomRight, to: CGPoint(x: 0, y: 0))
    #expect(n.bounds.minX == 100 && n.bounds.minY == 100)
    #expect(n.bounds.width == NoteLayout.minWidth(fontSize: font))

    var top = note("Hi", CGRect(x: 100, y: 100, width: 200, height: 100))
    top.resize(.topLeft, to: CGPoint(x: 400, y: 400))
    #expect(top.bounds.maxX == 300 && top.bounds.maxY == 200)
    #expect(top.bounds.width == NoteLayout.minWidth(fontSize: font))
    // The top edge stops where the text would no longer fit above the fixed bottom.
    #expect(top.bounds.height == (try layout(top)).lineHeight + (try layout(top)).padding * 2)
}

// MARK: Canvas and undo

@Test func aNotePastTheImageEdgeGrowsTheCanvas() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    let n = note(longText, CGRect(x: 150, y: 40, width: 180, height: 0))
    doc.annotations.append(n)
    doc.grow(toFit: n, margin: 10)
    #expect(doc.canvasRect.contains(n.paintedBounds.insetBy(dx: -10, dy: -10)))
    #expect(doc.canvasRect.minX == 0 && doc.canvasRect.minY == 0)
}

@Test func editsResizesAndDeletesUndo() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    var stack = UndoStack<EditorSnapshot>()
    let n = note("Hello", CGRect(x: 20, y: 20, width: 120, height: 0))
    stack.record(doc.snapshot)
    doc.annotations.append(n)
    let added = doc.snapshot

    stack.record(doc.snapshot)
    doc.annotations[0].setText("Hello there")
    stack.record(doc.snapshot)
    doc.annotations[0].resize(.bottomRight, to: CGPoint(x: 400, y: 20))
    doc.grow(toFit: doc.annotations[0], margin: 10)
    let resized = doc.snapshot
    #expect(resized.canvasRect.maxX > 400)
    stack.record(doc.snapshot)
    doc.annotations.removeAll()

    doc.restore(stack.undo(from: doc.snapshot)!)
    #expect(doc.snapshot == resized)
    doc.restore(stack.undo(from: doc.snapshot)!)
    #expect(doc.annotations[0].kind == .note("Hello there", rect: CGRect(x: 20, y: 20, width: 120, height: 0)))
    #expect(doc.canvasRect == doc.fullRect)
    doc.restore(stack.undo(from: doc.snapshot)!)
    #expect(doc.snapshot == added)
    doc.restore(stack.undo(from: doc.snapshot)!)
    #expect(doc.annotations.isEmpty)
}

// MARK: Rendering

private func whiteImage(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

/// Renders `doc` at `scale` the way the editor view does: a context scaled up from the export.
private func render(_ doc: EditorDocument, scale: CGFloat) throws -> CGImage {
    let size = doc.exportSize
    let ctx = try #require(CGContext(
        data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    ctx.scaleBy(x: scale, y: scale)
    AnnotationRenderer.render(doc, into: ctx)
    return try #require(ctx.makeImage())
}

private func pixel(_ image: CGImage, _ x: CGFloat, _ y: CGFloat, scale: CGFloat = 1) throws -> [CGFloat] {
    let data = try #require(image.dataProvider?.data as Data?)
    let offset = Int(y * scale) * image.bytesPerRow + Int(x * scale) * 4
    return data[offset..<offset + 4].map { CGFloat($0) / 255 }
}

@Test(arguments: [1.0, 2.0])
func noteRendersTheSameInTheEditorAndTheExport(scale: CGFloat) throws {
    let n = note("Hello world", CGRect(x: 20, y: 20, width: 160, height: 60))
    let l = try layout(n)
    let doc = EditorDocument(base: whiteImage(width: 240, height: 140), annotations: [n])
    let image = try render(doc, scale: scale)
    if scale == 1 {
        let flat = try #require(AnnotationRenderer.flatten(doc))
        #expect(try pixel(flat, 150, 70) == pixel(image, 150, 70))
    }

    // Paper in an empty part of the note.
    let paper = try pixel(image, l.frame.maxX - l.padding / 2, l.frame.maxY - l.padding / 2, scale: scale)
    let fill = yellow.noteFill
    #expect(abs(paper[0] - fill.r) < 0.03 && abs(paper[1] - fill.g) < 0.03 && abs(paper[2] - fill.b) < 0.03)

    // Ink somewhere along the first line of text.
    let baseline = l.textRect.minY + l.ascent * 0.6
    var darkest: CGFloat = 1
    for x in stride(from: l.textRect.minX, to: l.textRect.minX + 60, by: 0.5) {
        darkest = min(darkest, try pixel(image, x, baseline, scale: scale)[1])
    }
    #expect(darkest < 0.4)

    // A soft shadow just under the bottom edge, at the same spot whatever the scale.
    let shadow = try pixel(image, l.frame.midX, l.frame.maxY + l.shadowOffset, scale: scale)
    #expect(shadow[0] < 0.97 && shadow[0] > 0.5)
    #expect(try pixel(image, l.frame.midX, l.frame.maxY + l.shadowOffset + l.shadowBlur + 4, scale: scale)[0] > 0.99)
}

@Test func shadowKeepsItsShapeWhenZoomed() throws {
    let n = note("Hello", CGRect(x: 20, y: 20, width: 160, height: 60))
    let l = try layout(n)
    let doc = EditorDocument(base: whiteImage(width: 240, height: 140), annotations: [n])
    let one = try render(doc, scale: 1), two = try render(doc, scale: 2)
    for dy in [l.shadowOffset, l.shadowOffset + l.shadowBlur / 2] {
        let y = l.frame.maxY + dy
        #expect(abs(try pixel(one, l.frame.midX, y)[0] - pixel(two, l.frame.midX, y, scale: 2)[0]) < 0.04)
    }
}

@Test func roundedCornersLeaveTheImageShowing() throws {
    let n = note("Hi", CGRect(x: 20, y: 20, width: 160, height: 80))
    let doc = EditorDocument(base: whiteImage(width: 240, height: 140), annotations: [Annotation(kind: n.kind, color: RGBA.presets[4], lineWidth: 4)])
    let image = try render(doc, scale: 1)
    // The very corner is outside the rounding, so it isn't the blue paper.
    let corner = try pixel(image, 20.5, 20.5)
    let fill = RGBA.presets[4].noteFill
    #expect(abs(corner[0] - fill.r) > 0.05)
    #expect(abs((try pixel(image, 100, 60))[0] - fill.r) < 0.03)
}

@Test func aNoteOutsideTheImageExportsOnThePadding() throws {
    var doc = EditorDocument(base: solidImage(width: 100, height: 100))
    let n = note("Outside", CGRect(x: 130, y: 20, width: 120, height: 0))
    doc.annotations.append(n)
    doc.grow(toFit: n, margin: 8)
    let image = try #require(AnnotationRenderer.flatten(doc))
    #expect(CGSize(width: image.width, height: image.height) == doc.exportSize)
    let l = try layout(n)
    let origin = doc.canvasRect.origin
    let paper = try pixel(image, l.frame.maxX - l.padding / 2 - origin.x, l.frame.maxY - l.padding / 2 - origin.y)
    #expect(paper[3] == 1)
    #expect(abs(paper[2] - yellow.noteFill.b) < 0.05)
}
