import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let style = AnnotationDraft.Style(
    color: RGBA(1, 0, 0), fill: RGBA(0, 0, 1), noteColor: RGBA(1, 1, 0), lineWidth: 4, cornerRadius: 12, shape: .rounded,
    redaction: .pixelate, redactionAmount: 0.02, spotlight: SpotlightStyle(shape: .ellipse, effect: .blur, strength: 0.7), alignment: .center
)

private func draft(
    _ tool: EditorTool, from start: CGPoint = .zero, to point: CGPoint, previous: Annotation? = nil,
    constrain: Bool = false, fromCenter: Bool = false, minDistance: CGFloat = 1
) -> Annotation? {
    AnnotationDraft.annotation(tool: tool, from: start, to: point, previous: previous, constrain: constrain, fromCenter: fromCenter, minDistance: minDistance, style: style)
}

private func isClose(_ a: CGPoint, _ b: CGPoint) -> Bool { hypot(a.x - b.x, a.y - b.y) < 0.001 }

@Test func shiftSnapsArrowsAndLinesTo45Degrees() throws {
    for tool in [EditorTool.arrow, .line] {
        let snapped = try #require(draft(tool, to: CGPoint(x: 100, y: 90), constrain: true))
        switch snapped.kind {
        case let .arrow(from, to), let .line(from, to):
            #expect(from == .zero)
            #expect(abs(to.x - to.y) < 0.001)
            #expect(abs(hypot(to.x, to.y) - (100.0 * 100.0 + 90.0 * 90.0).squareRoot()) < 0.001)
        default:
            Issue.record("\(tool) drew \(snapped.kind)")
        }
        let free = try #require(draft(tool, to: CGPoint(x: 100, y: 90)))
        #expect(free.kind == (tool == .arrow ? .arrow(from: .zero, to: CGPoint(x: 100, y: 90)) : .line(from: .zero, to: CGPoint(x: 100, y: 90))))
    }
}

@Test func shiftSquaresBoxes() throws {
    let square = try #require(draft(.shape, to: CGPoint(x: 100, y: -40), constrain: true))
    #expect(square.kind == .shape(.rounded, rect: CGRect(x: 0, y: -40, width: 40, height: 40)))
    let redaction = try #require(draft(.redact, to: CGPoint(x: -30, y: 80), constrain: true))
    #expect(redaction.kind == .pixelate(CGRect(x: -30, y: 0, width: 30, height: 30), amount: 0.02))
}

@Test func optionDrawsBoxesFromTheCentre() throws {
    let centred = try #require(draft(.shape, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 80, y: 60), fromCenter: true))
    #expect(centred.kind == .shape(.rounded, rect: CGRect(x: 20, y: 40, width: 60, height: 20)))
    let both = try #require(draft(.shape, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 80, y: 60), constrain: true, fromCenter: true))
    #expect(both.kind == .shape(.rounded, rect: CGRect(x: 40, y: 40, width: 20, height: 20)))
}

@Test func highlighterIsStraightWithShift() throws {
    let wobbly = Annotation(kind: .marker([.zero, CGPoint(x: 10, y: 3), CGPoint(x: 20, y: -2)]), color: style.color, lineWidth: 4)
    let straight = try #require(draft(.highlight, to: CGPoint(x: 100, y: 4), previous: wobbly, constrain: true))
    guard case let .marker(points) = straight.kind else {
        Issue.record("drew \(straight.kind)")
        return
    }
    #expect(points.count == 2)
    #expect(isClose(points[1], CGPoint(x: (100.0 * 100.0 + 4.0 * 4.0).squareRoot(), y: 0)))
    #expect(straight.id == wobbly.id)
}

@Test func strokePointsCloserThanMinDistanceAreDropped() throws {
    for tool in [EditorTool.pen, .highlight] {
        let first = try #require(draft(tool, to: CGPoint(x: 10, y: 0), minDistance: 2))
        let near = try #require(draft(tool, to: CGPoint(x: 11, y: 0), previous: first, minDistance: 2))
        let far = try #require(draft(tool, to: CGPoint(x: 13, y: 0), previous: near, minDistance: 2))
        switch (first.kind, near.kind, far.kind) {
        case let (.freehand(a), .freehand(b), .freehand(c)), let (.marker(a), .marker(b), .marker(c)):
            #expect(a == [.zero, CGPoint(x: 10, y: 0)])
            #expect(b == a)
            #expect(c == a + [CGPoint(x: 13, y: 0)])
        default:
            Issue.record("\(tool) drew \(first.kind)")
        }
        #expect(far.id == first.id)
    }
}

@Test func spotlightAndRedactionDraftsTakeTheNextStyle() throws {
    let spotlight = try #require(draft(.spotlight, to: CGPoint(x: 40, y: 30)))
    #expect(spotlight.kind == .spotlight(CGRect(x: 0, y: 0, width: 40, height: 30), style: style.spotlight))
    #expect(spotlight.cornerRadius == style.cornerRadius)
    let redaction = try #require(draft(.redact, to: CGPoint(x: 40, y: 30)))
    #expect(redaction.redaction == .pixelate)
    #expect(redaction.kind == .pixelate(CGRect(x: 0, y: 0, width: 40, height: 30), amount: 0.02))
}

@Test func shapesTakeTheFillAndCornersButLinesDoNot() throws {
    let shape = try #require(draft(.shape, to: CGPoint(x: 40, y: 30)))
    #expect(shape.fill == style.fill)
    #expect(shape.cornerRadius == style.cornerRadius)
    #expect(shape.color == style.color)
    #expect(shape.lineWidth == style.lineWidth)
    let line = try #require(draft(.line, to: CGPoint(x: 40, y: 30)))
    #expect(line.fill == nil)
}

@Test func notesTakeTheNoteColourAndAlignment() throws {
    let note = try #require(draft(.note, to: CGPoint(x: 200, y: 100)))
    #expect(note.color == style.noteColor)
    #expect(note.alignment == .center)
    #expect(note.text == "")
}

@Test func toolsThatDontDragDrawNothing() {
    for tool in [EditorTool.select, .hand, .crop, .counter, .text] {
        #expect(draft(tool, to: CGPoint(x: 40, y: 30)) == nil)
    }
}
