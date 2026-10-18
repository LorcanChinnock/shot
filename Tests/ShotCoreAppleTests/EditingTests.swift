import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let red = RGBA.presets[0]
private let box = CGRect(x: 100, y: 100, width: 200, height: 100)

private func annotation(_ kind: Annotation.Kind, lineWidth: CGFloat = 4) -> Annotation {
    Annotation(kind: kind, color: red, lineWidth: lineWidth)
}

private let boxKinds: [Annotation.Kind] = [.shape(.rectangle, rect: box), .shape(.ellipse, rect: box), .highlight(box), .pixelate(box), .blur(box), .spotlight(box, style: SpotlightStyle())]

/// The rect a box kind holds.
private func rect(_ annotation: Annotation) -> CGRect? {
    switch annotation.kind {
    case let .shape(_, rect), let .highlight(rect), let .pixelate(rect, _), let .blur(rect, _), let .spotlight(rect, _):
        return rect
    default:
        return nil
    }
}

// MARK: Handles

@Test func linesAndArrowsHaveAHandleAtEachEndAndTheMiddle() {
    let from = CGPoint(x: 10, y: 20), to = CGPoint(x: 110, y: 70)
    for kind in [Annotation.Kind.line(from: from, to: to), .arrow(from: from, to: to)] {
        let a = annotation(kind)
        #expect(a.handles.map { $0.handle } == [.start, .end, .mid])
        #expect(a.handles.map { $0.point } == [from, to, CGPoint(x: 60, y: 45)])
    }
}

@Test(arguments: boxKinds)
func boxesHaveHandlesOnTheirCornersAndEdges(kind: Annotation.Kind) {
    let a = annotation(kind)
    let points = Dictionary(uniqueKeysWithValues: a.handles.map { ($0.handle, $0.point) })
    #expect(points.count == 8)
    #expect(points[.topLeft] == CGPoint(x: 100, y: 100))
    #expect(points[.top] == CGPoint(x: 200, y: 100))
    #expect(points[.topRight] == CGPoint(x: 300, y: 100))
    #expect(points[.right] == CGPoint(x: 300, y: 150))
    #expect(points[.bottomRight] == CGPoint(x: 300, y: 200))
    #expect(points[.bottom] == CGPoint(x: 200, y: 200))
    #expect(points[.bottomLeft] == CGPoint(x: 100, y: 200))
    #expect(points[.left] == CGPoint(x: 100, y: 150))
}

@Test func notesHaveHandlesOnTheirFrame() {
    let n = annotation(.note("Hello", rect: box))
    #expect(n.handles.count == 8)
    #expect(n.handles.first { $0.handle == .bottom }?.point == CGPoint(x: n.bounds.midX, y: n.bounds.maxY))
}

@Test func textAndCountersHaveNoHandles() {
    #expect(annotation(.text("Hi", origin: .zero, fontSize: 20)).handles.isEmpty)
    #expect(annotation(.counter(1, center: CGPoint(x: 50, y: 50))).handles.isEmpty)
    #expect(annotation(.counter(1, center: CGPoint(x: 50, y: 50))).handle(at: CGPoint(x: 50, y: 50), tolerance: 100) == nil)
}

// MARK: Hit-testing handles

@Test func handleHitTestFindsCornersEdgesAndEnds() {
    let r = annotation(.shape(.rectangle, rect: box))
    #expect(r.handle(at: CGPoint(x: 103, y: 97), tolerance: 4) == .topLeft)
    #expect(r.handle(at: CGPoint(x: 201, y: 203), tolerance: 4) == .bottom)
    #expect(r.handle(at: CGPoint(x: 296, y: 150), tolerance: 4) == .right)
    #expect(r.handle(at: CGPoint(x: 200, y: 150), tolerance: 4) == nil)
    #expect(r.handle(at: CGPoint(x: 150, y: 100), tolerance: 4) == nil)
    #expect(r.handle(at: CGPoint(x: 106, y: 100), tolerance: 4) == nil)

    let line = annotation(.line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)))
    #expect(line.handle(at: CGPoint(x: 2, y: -2), tolerance: 4) == .start)
    #expect(line.handle(at: CGPoint(x: 99, y: 3), tolerance: 4) == .end)
    #expect(line.handle(at: CGPoint(x: 50, y: 0), tolerance: 4) == .mid)
}

@Test func overlappingHandlesPickTheNearest() {
    let tiny = annotation(.shape(.rectangle, rect: CGRect(x: 100, y: 100, width: 6, height: 6)))
    #expect(tiny.handle(at: CGPoint(x: 106, y: 106), tolerance: 8) == .bottomRight)
    #expect(tiny.handle(at: CGPoint(x: 103, y: 99), tolerance: 8) == .top)
    let short = annotation(.arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 4, y: 0)))
    #expect(short.handle(at: CGPoint(x: 3.5, y: 0), tolerance: 8) == .end)
}

@Test func theMiddleOfASmallShapeStillMovesIt() {
    // Every point of these shapes is within the tolerance of a handle, but the middle grabs none.
    let tiny = annotation(.shape(.rectangle, rect: CGRect(x: 100, y: 100, width: 6, height: 6)))
    #expect(tiny.handle(at: CGPoint(x: 103, y: 103), tolerance: 8) == nil)
    #expect(tiny.handle(at: CGPoint(x: 102, y: 104), tolerance: 8) == nil)
    let short = annotation(.line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 6, y: 0)))
    #expect(short.handle(at: CGPoint(x: 3, y: 0), tolerance: 8) == nil)
    #expect(short.handle(at: CGPoint(x: 0.5, y: 1), tolerance: 8) == .start)
}

// MARK: Resizing

@Test func draggingAnEndMovesOnlyThatEnd() {
    var line = annotation(.line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)))
    line.resize(.end, to: CGPoint(x: 80, y: 60))
    #expect(line.kind == .line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 80, y: 60)))
    var arrow = annotation(.arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)))
    arrow.resize(.start, to: CGPoint(x: -20, y: 30))
    #expect(arrow.kind == .arrow(from: CGPoint(x: -20, y: 30), to: CGPoint(x: 100, y: 0)))
    // A box handle means nothing to a line.
    arrow.resize(.topLeft, to: CGPoint(x: 500, y: 500))
    #expect(arrow.kind == .arrow(from: CGPoint(x: -20, y: 30), to: CGPoint(x: 100, y: 0)))
}

@Test(arguments: boxKinds)
func draggingACornerKeepsTheOppositeCorner(kind: Annotation.Kind) {
    var a = annotation(kind)
    a.resize(.bottomRight, to: CGPoint(x: 350, y: 260))
    #expect(rect(a) == CGRect(x: 100, y: 100, width: 250, height: 160))
    var b = annotation(kind)
    b.resize(.topLeft, to: CGPoint(x: 50, y: 80))
    #expect(rect(b) == CGRect(x: 50, y: 80, width: 250, height: 120))
}

@Test(arguments: boxKinds)
func draggingAnEdgeChangesOneSide(kind: Annotation.Kind) {
    var a = annotation(kind)
    a.resize(.right, to: CGPoint(x: 400, y: 999))
    #expect(rect(a) == CGRect(x: 100, y: 100, width: 300, height: 100))
    var b = annotation(kind)
    b.resize(.top, to: CGPoint(x: -999, y: 40))
    #expect(rect(b) == CGRect(x: 100, y: 40, width: 200, height: 160))
    var c = annotation(kind)
    c.resize(.left, to: CGPoint(x: 150, y: 0))
    #expect(rect(c) == CGRect(x: 150, y: 100, width: 150, height: 100))
    var d = annotation(kind)
    d.resize(.bottom, to: CGPoint(x: 0, y: 120))
    #expect(rect(d) == CGRect(x: 100, y: 100, width: 200, height: 20))
}

@Test func draggingPastTheOppositeSideFlipsTheBox() {
    var a = annotation(.shape(.rectangle, rect: box))
    a.resize(.right, to: CGPoint(x: 40, y: 0))
    #expect(rect(a) == CGRect(x: 40, y: 100, width: 60, height: 100))
    var b = annotation(.shape(.ellipse, rect: box))
    b.resize(.topLeft, to: CGPoint(x: 320, y: 230))
    #expect(rect(b) == CGRect(x: 300, y: 200, width: 20, height: 30))
    // Lines and text keep their kind when resized.
    var line = annotation(.line(from: .zero, to: CGPoint(x: 10, y: 10)))
    line.resize(.right, to: CGPoint(x: 99, y: 99))
    #expect(line.kind == .line(from: .zero, to: CGPoint(x: 10, y: 10)))
}

@Test func draggingANoteEdgeChangesOnlyThatSide() throws {
    let text = "Sticky notes wrap their text to the width of the note, so a long comment stays readable."
    var wide = annotation(.note(text, rect: CGRect(x: 100, y: 100, width: 400, height: 0)))
    let before = try #require(wide.noteLayout)
    wide.resize(.right, to: CGPoint(x: 260, y: 999))
    let after = try #require(wide.noteLayout)
    #expect(after.frame.minX == 100 && after.frame.minY == 100 && after.frame.width == 160)
    #expect(after.lines.count > before.lines.count)

    var left = annotation(.note("Hi", rect: box))
    left.resize(.left, to: CGPoint(x: 60, y: -999))
    #expect(left.bounds == CGRect(x: 60, y: 100, width: 240, height: 100))

    var tall = annotation(.note("Hi", rect: box))
    tall.resize(.bottom, to: CGPoint(x: 999, y: 300))
    #expect(tall.bounds == CGRect(x: 100, y: 100, width: 200, height: 200))

    var top = annotation(.note("Hi", rect: box))
    top.resize(.top, to: CGPoint(x: 999, y: 60))
    #expect(top.bounds == CGRect(x: 100, y: 60, width: 200, height: 140))
    // Pushed past the bottom, the top edge stops where the text still fits.
    top.resize(.top, to: CGPoint(x: 0, y: 500))
    let layout = try #require(top.noteLayout)
    #expect(top.bounds.maxY == 200)
    #expect(top.bounds.height == layout.lineHeight + layout.padding * 2)
}

@Test func aResizePastTheImageGrowsTheCanvasAndUndoes() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    var stack = UndoStack<EditorSnapshot>()
    doc.annotations.append(annotation(.shape(.rectangle, rect: CGRect(x: 20, y: 20, width: 40, height: 40))))
    let placed = doc.snapshot

    stack.record(doc.snapshot)
    doc.annotations[0].resize(.bottomRight, to: CGPoint(x: 260, y: 140))
    doc.grow(toFit: doc.annotations[0], margin: 10)
    #expect(doc.canvasRect.contains(doc.annotations[0].paintedBounds.insetBy(dx: -10, dy: -10)))
    #expect(doc.canvasRect.minX == 0 && doc.canvasRect.minY == 0)

    doc.restore(stack.undo(from: doc.snapshot)!)
    #expect(doc.snapshot == placed)
}

// MARK: Corner radius

@Test func everyShapeWithCornersAndBigEnoughHasRadiusHandles() {
    #expect(annotation(.shape(.rectangle, rect: box)).radiusHandles(tolerance: 4).map(\.handle) == (0..<4).map { .radius($0) })
    #expect(annotation(.spotlight(box, style: SpotlightStyle(shape: .rectangle))).radiusHandles(tolerance: 4).count == 4)
    #expect(annotation(.shape(.triangle, rect: box)).radiusHandles(tolerance: 4).count == 3)
    #expect(annotation(.shape(.diamond, rect: box)).radiusHandles(tolerance: 4).count == 4)
    // A star has handles in its five points only.
    #expect(annotation(.shape(.star, rect: box)).radiusHandles(tolerance: 4).map(\.handle) == [0, 2, 4, 6, 8].map { .radius($0) })
    #expect(annotation(.shape(.ellipse, rect: box)).radiusHandles(tolerance: 4).isEmpty)
    #expect(annotation(.spotlight(box, style: SpotlightStyle(shape: .ellipse))).radiusHandles(tolerance: 4).isEmpty)
    #expect(annotation(.shape(.rectangle, rect: CGRect(x: 0, y: 0, width: 200, height: 39))).radiusHandles(tolerance: 4).isEmpty)
    #expect(annotation(.shape(.rectangle, rect: box)).handles.count == 8)
}

@Test func radiusHandlesSitInsideTheCornersAndFollowTheRadius() {
    var rounded = annotation(.shape(.rectangle, rect: box))
    #expect(rounded.radiusHandles(tolerance: 4)[0].point == CGPoint(x: 108, y: 108))
    #expect(rounded.handle(at: CGPoint(x: 109, y: 107), tolerance: 4) == .radius(0))
    #expect(rounded.handle(at: CGPoint(x: 101, y: 101), tolerance: 4) == .topLeft)
    rounded.cornerRadius = 20
    let point = rounded.radiusHandles(tolerance: 4)[2].point
    #expect(abs(point.x - 282) < 0.001 && abs(point.y - 182) < 0.001)
}

@Test func aTrianglesRadiusHandlesSitOnTheLineToTheCentre() throws {
    let triangle = annotation(.shape(.triangle, rect: box))
    let apex = try #require(triangle.radiusHandles(tolerance: 4).first)
    #expect(apex.handle == .radius(0))
    // The apex is at the top middle, so its handle is straight down from it, inside the shape.
    #expect(abs(apex.point.x - 200) < 0.001 && apex.point.y > 100 && apex.point.y < 150)
    for (_, point) in triangle.radiusHandles(tolerance: 4) {
        #expect(BoxShape.triangle.path(in: box).contains(point))
    }
}

@Test func draggingARadiusHandleSetsOneRadiusUpToAPill() {
    let start = {
        var rounded = annotation(.shape(.rectangle, rect: box))
        rounded.cornerRadius = 20
        return rounded
    }()
    var a = start
    // The handle starts 18 in from the corner: 8 for the tolerance plus half the radius of 20.
    a.resize(.radius(0), to: CGPoint(x: 130, y: 130), tolerance: 4)
    #expect(a.cornerRadius == 44)
    #expect(a.cornerBox?.rect == box)
    var b = start
    b.resize(.radius(2), to: CGPoint(x: 280, y: 180), tolerance: 4)
    #expect(b.cornerRadius == 24)
    var c = start
    c.resize(.radius(1), to: CGPoint(x: 100, y: 300), tolerance: 4)
    #expect(c.cornerRadius == 50)
    var d = start
    d.resize(.radius(3), to: CGPoint(x: 0, y: 300), tolerance: 4)
    #expect(d.cornerRadius == 0)
}

@Test func aNewShapeIsSquareAndAnyShapeWithCornersCanBeRounded() {
    for shape in BoxShape.allCases where shape.hasCorners {
        var a = annotation(.shape(shape, rect: box))
        #expect(a.cornerRadius == nil && a.cornerBox?.radius == 0)
        let handle = a.radiusHandles(tolerance: 4)[0]
        a.resize(handle.handle, to: CGPoint(x: handle.point.x + 6, y: handle.point.y + 6), tolerance: 4)
        #expect((a.cornerRadius ?? 0) > 0, "\(shape)")
    }
    var ellipse = annotation(.shape(.ellipse, rect: box))
    ellipse.resize(.radius(0), to: CGPoint(x: 150, y: 150), tolerance: 4)
    #expect(ellipse.cornerRadius == nil)
}

@Test func theRadiusSurvivesResizingAndKeepsWithinTheBox() {
    var a = annotation(.shape(.rectangle, rect: box))
    a.cornerRadius = 30
    a.resize(.right, to: CGPoint(x: 500, y: 150))
    #expect(a.cornerBox?.radius == 30)
    a.resize(.bottom, to: CGPoint(x: 0, y: 120))
    #expect(a.cornerBox?.radius == 10)
    // A radius bigger than the box allows draws a pill rather than failing.
    _ = BoxShape.rectangle.path(in: CGRect(x: 0, y: 0, width: 10, height: 4), cornerRadius: 100)
}

@Test func scalingARoundedBoxScalesItsRadius() {
    var a = annotation(.shape(.rectangle, rect: box))
    a.cornerRadius = 10
    #expect(a.scaled(by: 2).cornerRadius == 20)
}

@Test func aShapesRadiusAndAnImagesAreSeparate() throws {
    var shape = annotation(.shape(.triangle, rect: box))
    shape.cornerRadius = 9
    let decoded = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(shape))
    #expect(decoded == shape && decoded.cornerRadius == 9)
}

// MARK: Rounded rectangles saved by older versions

/// `annotation` as an older version saved it: the shape named `rounded`, and its radius under `cornerRadius`.
private func legacyJSON(_ annotation: Annotation, radius: CGFloat?) throws -> Data {
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(annotation)) as? [String: Any])
    object["boxRadius"] = nil
    object["cornerRadius"] = radius
    var text = try #require(String(data: JSONSerialization.data(withJSONObject: object), encoding: .utf8))
    text = text.replacingOccurrences(of: "\"rectangle\"", with: "\"rounded\"")
    return Data(text.utf8)
}

@Test func aRoundedRectangleSavedByAnOlderVersionIsARectangleWithItsRadius() throws {
    let legacy = annotation(.shape(.rectangle, rect: box))
    let decoded = try JSONDecoder().decode(Annotation.self, from: legacyJSON(legacy, radius: 20))
    #expect(decoded.kind == .shape(.rectangle, rect: box))
    #expect(decoded.cornerRadius == 20)
    #expect(decoded.cornerBox?.radius == 20)
}

@Test func aRoundedBoxWithNoRadiusKeepsItsOldLook() throws {
    let legacy = annotation(.shape(.rectangle, rect: box))
    let decoded = try JSONDecoder().decode(Annotation.self, from: legacyJSON(legacy, radius: nil))
    // A fifth of the shorter side, as it was drawn.
    #expect(decoded.cornerBox?.radius == 20)
    let spotlight = annotation(.spotlight(box, style: SpotlightStyle(shape: .rectangle)))
    let decodedSpotlight = try JSONDecoder().decode(Annotation.self, from: legacyJSON(spotlight, radius: 14))
    #expect(decodedSpotlight.kind == .spotlight(box, style: SpotlightStyle(shape: .rectangle)))
    #expect(decodedSpotlight.cornerBox?.radius == 14)
}

@Test func aSquareShapeSavedByAnOlderVersionStaysSquare() throws {
    // Older versions stored a radius of 12 on every shape, and drew only a rounded rectangle's.
    for shape in BoxShape.allCases {
        let saved = annotation(.shape(shape, rect: box))
        let decoded = try JSONDecoder().decode(Annotation.self, from: legacyJSON(saved, radius: 12).replacingRounded(with: shape))
        #expect(decoded.cornerRadius == nil, "\(shape)")
        #expect(decoded.cornerBox?.radius ?? 0 == 0, "\(shape)")
    }
}

private extension Data {
    /// This JSON with the shape `rounded` named `shape` instead.
    func replacingRounded(with shape: BoxShape) -> Data {
        Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: "\"rounded\"", with: "\"\(shape.rawValue)\"").utf8)
    }
}

@Test func anImagesRadiusStillReadsFromItsOldKey() throws {
    let image = Annotation(kind: .image(AnnotationImage(solidImage(width: 60, height: 40)), rect: box), color: red, lineWidth: 4)
    var rounded = image
    rounded.cornerRadius = 11
    let decoded = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(rounded))
    #expect(decoded.cornerRadius == 11)
    let json = try #require(String(data: JSONEncoder().encode(rounded), encoding: .utf8))
    #expect(json.contains("\"cornerRadius\":11"))
}

@Test func theRoundedShapeNameStillDecodesAsARectangle() throws {
    #expect(try JSONDecoder().decode(BoxShape.self, from: Data("\"rounded\"".utf8)) == .rectangle)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(BoxShape.self, from: Data("\"hexagon\"".utf8)) }
    #expect(!BoxShape.allCases.map(\.rawValue).contains("rounded") && !BoxShape.spotlightShapes.map(\.rawValue).contains("rounded"))
}

// MARK: Restyling

@Test func changingTheLineWidthScalesTextAndKeepsOtherGeometry() {
    var text = annotation(.text("Hi", origin: CGPoint(x: 10, y: 10), fontSize: 24))
    text.setLineWidth(8)
    #expect(text.lineWidth == 8)
    #expect(text.kind == .text("Hi", origin: CGPoint(x: 10, y: 10), fontSize: 48))

    var r = annotation(.shape(.rectangle, rect: box))
    r.setLineWidth(2)
    #expect(r.lineWidth == 2 && r.kind == .shape(.rectangle, rect: box))

    let counter = annotation(.counter(1, center: CGPoint(x: 50, y: 50)))
    var bigger = counter
    bigger.setLineWidth(8)
    #expect(bigger.bounds.width > counter.bounds.width)
}

@Test func aBiggerStyleNearTheEdgeGrowsTheCanvas() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    doc.annotations.append(annotation(.counter(1, center: CGPoint(x: 180, y: 50)), lineWidth: 2))
    doc.annotations[0].setLineWidth(8)
    doc.annotations[0].color = RGBA.presets[4]
    doc.grow(toFit: doc.annotations[0], margin: 10)
    #expect(doc.canvasRect.maxX >= doc.annotations[0].paintedBounds.maxX + 10)
}

// MARK: Editing text

@Test func setTextReplacesTextAndKeepsItsPlace() {
    var text = annotation(.text("Hello", origin: CGPoint(x: 10, y: 20), fontSize: 24))
    text.setText("Bye")
    #expect(text.kind == .text("Bye", origin: CGPoint(x: 10, y: 20), fontSize: 24))
    var counter = annotation(.counter(2, center: .zero))
    counter.setText("Nope")
    #expect(counter.kind == .counter(2, center: .zero))
}

@Test func editedTextUndoes() {
    var doc = EditorDocument(base: solidImage(width: 200, height: 100))
    var stack = UndoStack<EditorSnapshot>()
    doc.annotations.append(annotation(.text("Hello", origin: CGPoint(x: 10, y: 20), fontSize: 24)))
    let placed = doc.snapshot
    stack.record(doc.snapshot)
    doc.annotations[0].setText("Hello, world")
    stack.record(doc.snapshot)
    doc.annotations[0].color = RGBA.presets[4]
    doc.restore(stack.undo(from: doc.snapshot)!)
    #expect(doc.annotations[0].color == red)
    doc.restore(stack.undo(from: doc.snapshot)!)
    #expect(doc.snapshot == placed)
}
