import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let red = RGBA.presets[0]

private func annotation(_ kind: Annotation.Kind) -> Annotation {
    Annotation(kind: kind, color: red, lineWidth: 4)
}

@Test func hitTestLineAndArrow() {
    for kind in [Annotation.Kind.line(from: .zero, to: CGPoint(x: 100, y: 0)), .arrow(from: .zero, to: CGPoint(x: 100, y: 0))] {
        let a = annotation(kind)
        #expect(a.hitTest(CGPoint(x: 50, y: 3), tolerance: 2))
        #expect(!a.hitTest(CGPoint(x: 50, y: 20), tolerance: 2))
        #expect(!a.hitTest(CGPoint(x: 120, y: 0), tolerance: 2))
    }
}

@Test func hitTestRectAndEllipseStrokeOnly() {
    let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
    let r = annotation(.shape(.rectangle, rect: rect))
    #expect(r.hitTest(CGPoint(x: 0, y: 50), tolerance: 2))
    #expect(!r.hitTest(CGPoint(x: 50, y: 50), tolerance: 2))
    let e = annotation(.shape(.ellipse, rect: rect))
    #expect(e.hitTest(CGPoint(x: 50, y: 0), tolerance: 2))
    #expect(!e.hitTest(CGPoint(x: 50, y: 50), tolerance: 2))
    #expect(!e.hitTest(CGPoint(x: 2, y: 2), tolerance: 2))
}

@Test func hitTestFilledKinds() {
    let rect = CGRect(x: 10, y: 10, width: 50, height: 20)
    #expect(annotation(.highlight(rect)).hitTest(CGPoint(x: 30, y: 20), tolerance: 0))
    #expect(annotation(.pixelate(rect)).hitTest(CGPoint(x: 30, y: 20), tolerance: 0))
    #expect(!annotation(.pixelate(rect)).hitTest(CGPoint(x: 100, y: 20), tolerance: 0))
    let text = annotation(.text("Hello", origin: CGPoint(x: 10, y: 10), fontSize: 20))
    #expect(text.hitTest(CGPoint(x: 15, y: 20), tolerance: 0))
    #expect(!text.hitTest(CGPoint(x: 15, y: 60), tolerance: 0))
    let counter = annotation(.counter(1, center: CGPoint(x: 50, y: 50)))
    #expect(counter.hitTest(CGPoint(x: 55, y: 55), tolerance: 0))
    #expect(!counter.hitTest(CGPoint(x: 90, y: 90), tolerance: 0))
}

@Test func topmostHitWins() {
    let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
    let list = [annotation(.highlight(rect)), annotation(.pixelate(rect))]
    #expect(list.topmostIndex(at: CGPoint(x: 50, y: 50), tolerance: 0) == 1)
    #expect(list.nextCounterNumber == 1)
    #expect((list + [annotation(.counter(3, center: .zero))]).nextCounterNumber == 4)
}

@Test func exportSizeWithAndWithoutCrop() throws {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    #expect(doc.exportSize == CGSize(width: 200, height: 100))
    #expect(try #require(AnnotationRenderer.flatten(doc)).width == 200)
    doc.crop(to: CGRect(x: 20, y: 10, width: 80, height: 40))
    #expect(doc.exportSize == CGSize(width: 80, height: 40))
    let image = try #require(AnnotationRenderer.flatten(doc))
    #expect(image.width == 80)
    #expect(image.height == 40)
}

@Test func rendererUsesTopLeftImageCoordinates() throws {
    let white = { () -> CGImage in
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        return ctx.makeImage()!
    }()
    let blue = RGBA(0, 0, 1)
    let doc = EditorDocument(base: white, annotations: [Annotation(kind: .line(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 100, y: 10)), color: blue, lineWidth: 4)])
    let image = try #require(AnnotationRenderer.flatten(doc))
    let pixels = try #require(image.dataProvider?.data as Data?)
    func pixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let offset = y * image.bytesPerRow + x * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2])
    }
    // Row 10 from the top is blue; row 10 from the bottom stays white.
    #expect(pixel(x: 50, y: 10) == (0, 0, 255))
    #expect(pixel(x: 50, y: 89) == (255, 255, 255))
}

@Test func undoRedoStack() {
    var stack = UndoStack<Int>()
    var state = 0
    stack.record(state); state = 1
    stack.record(state); state = 2
    state = stack.undo(from: state)!
    #expect(state == 1)
    state = stack.undo(from: state)!
    #expect(state == 0)
    #expect(stack.undo(from: state) == nil)
    state = stack.redo(from: state)!
    #expect(state == 1)
    stack.record(state); state = 5
    #expect(!stack.canRedo)
}

private let shapeFrame = CGRect(x: 20, y: 20, width: 100, height: 60)

@Test func onlyShapesTakeAFill() {
    for shape in BoxShape.allCases {
        #expect(annotation(.shape(shape, rect: shapeFrame)).supportsFill)
    }
    #expect(!annotation(.arrow(from: .zero, to: CGPoint(x: 9, y: 9))).supportsFill)
}

@Test func onlyDrawnMarksTakeAColourAndWidth() {
    #expect(EditorTool.allCases.filter { !$0.isStyled } == [.select, .highlight, .spotlight, .redact, .crop])
    #expect(annotation(.freehand([.zero, CGPoint(x: 9, y: 9)])).isStyled)
    #expect(annotation(.note("Hi", rect: shapeFrame)).isStyled)
    for kind in [Annotation.Kind.highlight(shapeFrame), .pixelate(shapeFrame), .blur(shapeFrame), .spotlight(shapeFrame, style: SpotlightStyle())] {
        #expect(!annotation(kind).isStyled)
    }
}

@Test func aFilledShapeIsHitInside() {
    let centre = CGPoint(x: shapeFrame.midX, y: shapeFrame.midY)
    for kind in BoxShape.allCases.map({ Annotation.Kind.shape($0, rect: shapeFrame) }) {
        #expect(!annotation(kind).hitTest(centre, tolerance: 2))
        #expect(Annotation(kind: kind, color: red, fill: RGBA(0, 0, 1), lineWidth: 4).hitTest(centre, tolerance: 2))
    }
}

@Test func fillPaintsInsideAndTheBorderOverIt() throws {
    let ctx = CGContext(data: nil, width: 140, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 140, height: 100))
    let doc = EditorDocument(base: ctx.makeImage()!, annotations: [Annotation(kind: .shape(.rectangle, rect: shapeFrame), color: red, fill: RGBA(0, 0, 1), lineWidth: 4)])
    let image = try #require(AnnotationRenderer.flatten(doc))
    let pixels = try #require(image.dataProvider?.data as Data?)
    func pixel(x: Int, y: Int) -> [UInt8] {
        let offset = y * image.bytesPerRow + x * 4
        return Array(pixels[offset ..< offset + 3])
    }
    #expect(pixel(x: 70, y: 50) == [0, 0, 255])
    #expect(pixel(x: 20, y: 50)[0] > 240 && pixel(x: 20, y: 50)[2] < 100)
    #expect(pixel(x: 5, y: 5) == [255, 255, 255])
}

@Test func recentColorsKeepNewestFirstWithoutPresetsOrRepeats() {
    let a = RGBA(0.1, 0.2, 0.3), b = RGBA(0.4, 0.5, 0.6)
    var recents = EditorStyle.recents(adding: a, to: [])
    recents = EditorStyle.recents(adding: b, to: recents)
    recents = EditorStyle.recents(adding: a, to: recents)
    recents = EditorStyle.recents(adding: RGBA.presets[0], to: recents)
    #expect(recents == [a, b])
    let many = (0 ..< 10).reduce([RGBA]()) { EditorStyle.recents(adding: RGBA(CGFloat($1) / 20, 0.5, 0.5), to: $0) }
    #expect(many.count == EditorStyle.maxRecentColors)
}

@Test(arguments: [Annotation.Kind.arrow(from: .zero, to: CGPoint(x: 100, y: 0)), .line(from: .zero, to: CGPoint(x: 100, y: 0))])
func draggingTheMidpointBendsIt(kind: Annotation.Kind) {
    var a = annotation(kind)
    #expect(a.handle(at: CGPoint(x: 50, y: 0), tolerance: 6) == .mid)
    a.resize(.mid, to: CGPoint(x: 50, y: 40))
    #expect(a.handles.first { $0.handle == .mid }?.point == CGPoint(x: 50, y: 40))
    #expect(a.hitTest(CGPoint(x: 50, y: 40), tolerance: 3))
    #expect(!a.hitTest(CGPoint(x: 50, y: 0), tolerance: 3))
    #expect(a.bounds.maxY == 40)
    a.offset(by: CGVector(dx: 10, dy: 10))
    #expect(a.handles.first { $0.handle == .mid }?.point == CGPoint(x: 60, y: 50))
    a.resize(.mid, to: CGPoint(x: 60, y: 10))
    #expect(a.bend == nil)
}

@Test func aBentLineIsDrawnAlongItsCurve() throws {
    var line = annotation(.line(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 10)))
    line.lineWidth = 4
    line.resize(.mid, to: CGPoint(x: 50, y: 50))
    let ctx = try #require(CGContext(data: nil, width: 100, height: 60, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 60))
    let base = try #require(ctx.makeImage())
    let image = try #require(AnnotationRenderer.flatten(EditorDocument(base: base, annotations: [line])))
    let pixels = try #require(image.dataProvider?.data as Data?)
    func green(x: Int, y: Int) -> UInt8 { pixels[y * image.bytesPerRow + x * 4 + 1] }
    // The curve passes through the dragged midpoint, not along the chord.
    #expect(green(x: 50, y: 50) < 100)
    #expect(green(x: 50, y: 10) > 200)
}

@Test func everyShapeIsHitOnItsOutlineAndNotInsideUnlessFilled() {
    let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    for shape in BoxShape.allCases {
        let outline = annotation(.shape(shape, rect: frame))
        // Every shape's outline touches the top edge's midpoint.
        #expect(outline.hitTest(CGPoint(x: 50, y: 1), tolerance: 2), "\(shape)")
        #expect(!outline.hitTest(CGPoint(x: 50, y: 60), tolerance: 2), "\(shape)")
        #expect(Annotation(kind: outline.kind, color: red, fill: red, lineWidth: 4).hitTest(CGPoint(x: 50, y: 60), tolerance: 2), "\(shape)")
    }
}

@Test func switchingARedactionKeepsItsRect() {
    var a = annotation(.blur(shapeFrame))
    #expect(a.redaction == .blur)
    a.setRedaction(.pixelate)
    #expect(a.kind == .pixelate(shapeFrame))
    var arrow = annotation(.arrow(from: .zero, to: CGPoint(x: 9, y: 9)))
    arrow.setRedaction(.blur)
    #expect(arrow.redaction == nil)
}

@Test func aRedactionKeepsItsAmountWithinTheRangeAndWhenSwitched() {
    var a = annotation(.blur(shapeFrame))
    a.setRedactionAmount(0.012)
    a.setRedaction(.pixelate)
    #expect(a.kind == .pixelate(shapeFrame, amount: 0.012))
    a.offset(by: CGVector(dx: 5, dy: 5))
    #expect(a.redactionAmount(imageLength: 1000) == 0.012)
    a.setRedactionAmount(1)
    #expect(a.redactionAmount(imageLength: 1000) == Redaction.amounts.upperBound)
    a.setRedactionAmount(0)
    #expect(a.redactionAmount(imageLength: 1000) == Redaction.amounts.lowerBound)
    #expect(Redaction.amounts.contains(Redaction.defaultAmount))
    var arrow = annotation(.arrow(from: .zero, to: CGPoint(x: 9, y: 9)))
    arrow.setRedactionAmount(0.01)
    #expect(arrow.redactionAmount(imageLength: 1000) == nil)
}

@Test func aRedactionWithoutAnAmountShowsTheOneThatDrawsItAsBefore() {
    // Before the amount, a pixelate's blocks were a 20th of its width, at least 8, and a blur's radius a quarter of its
    // shorter side, at least 12.
    let wide = CGRect(x: 0, y: 0, width: 300, height: 40)
    #expect(annotation(.pixelate(wide)).redactionAmount(imageLength: 1500) == 0.01)
    #expect(annotation(.blur(wide)).redactionAmount(imageLength: 1500) == 0.008)
    #expect(AnnotationRenderer.redactionSize(annotation(.pixelate(wide)), base: solidImage(width: 1500, height: 900)) == 15)
    #expect(AnnotationRenderer.redactionSize(annotation(.blur(wide)), base: solidImage(width: 1500, height: 900)) == 12)
    // Past the slider's range, it's the nearest end.
    #expect(annotation(.pixelate(wide)).redactionAmount(imageLength: 4000) == Redaction.amounts.lowerBound)
    #expect(annotation(.pixelate(CGRect(x: 0, y: 0, width: 900, height: 40))).redactionAmount(imageLength: 1000) == Redaction.amounts.upperBound)
}

@Test func aRedactionSavedBeforeTheAmountDecodesWithoutOne() throws {
    let json = #"{"id":"9F0C1E2A-3B4C-4D5E-8F60-718293A4B5C6","kind":{"pixelate":{"_0":[[20,20],[100,60]]}},"color":{"r":1,"g":0,"b":0,"a":1},"lineWidth":4}"#
    let decoded = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
    #expect(decoded.kind == .pixelate(shapeFrame, amount: nil))
    let saved = annotation(.blur(shapeFrame, amount: 0.007))
    #expect(try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(saved)) == saved)
}

@Test func onlyTextNotesAndCountersSizeText() {
    #expect(EditorTool.allCases.filter(\.sizesText) == [.text, .note, .counter])
    #expect(annotation(.counter(1, center: .zero)).sizesText)
    #expect(!annotation(.line(from: .zero, to: CGPoint(x: 9, y: 9))).sizesText)
}
