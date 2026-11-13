import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let blue = RGBA(0, 0, 1)

private func line(_ dash: LineDash, arrow: Bool = false, bend: CGVector? = nil) -> Annotation {
    let from = CGPoint(x: 10, y: 20), to = CGPoint(x: 190, y: 20)
    var annotation = Annotation(kind: arrow ? .arrow(from: from, to: to) : .line(from: from, to: to), color: blue, lineWidth: 6)
    annotation.bend = bend
    annotation.lineDash = dash
    return annotation
}

/// Whether the pixel at (`x`, 20) of `annotation` drawn over a red image is the line's blue.
private func inksAt(_ xs: [CGFloat], of annotation: Annotation) throws -> [Bool] {
    let doc = EditorDocument(base: solidImage(width: 200, height: 40), annotations: [annotation])
    let image = try #require(AnnotationRenderer.flatten(doc))
    let pixels = try #require(image.dataProvider?.data as Data?)
    return xs.map { x in
        let offset = 20 * image.bytesPerRow + Int(x) * 4
        return pixels[offset + 2] > 200 && pixels[offset] < 60
    }
}

@Test func aSolidLineHasNoPattern() {
    #expect(LineDash.solid.pattern(width: 4, length: 100) == nil)
    #expect(LineDash.dashed.pattern(width: 0, length: 100) == nil)
    #expect(LineDash.dotted.pattern(width: 4, length: 0) == nil)
}

@Test func dashesScaleWithTheWidthAndStartAndEndTheLine() throws {
    for width in [2.0, 4.0, 9.0] {
        for length in [100.0, 333.0, 1000.0] {
            let pattern = try #require(LineDash.dashed.pattern(width: width, length: length))
            let (dash, gap) = (pattern[0], pattern[1])
            // Shown with round caps, a dash is about 3 widths long and a gap about 2, stretched by at most a fifth or so.
            #expect(abs((dash + width) / width - 3) < 0.8, "\(width) \(length)")
            #expect(abs(gap / dash - 1.5) < 0.0001)
            let count = ((length + gap) / (dash + gap)).rounded()
            #expect(abs(count * dash + (count - 1) * gap - length) < 0.0001, "the last dash ends at the end")
        }
    }
}

@Test func dotsAreRoundAndEvenlySpacedFromEndToEnd() throws {
    let pattern = try #require(LineDash.dotted.pattern(width: 4, length: 96))
    #expect(pattern[0] == 0)
    #expect(abs(pattern[1] - 8) < 0.01, "two widths apart")
    // Otherwise a whole number of spaces near two widths, so a dot lands on each end.
    let stretched = try #require(LineDash.dotted.pattern(width: 4, length: 100))
    #expect(abs(stretched[1] - 100.0 / 13) < 0.01)
}

@Test func aShortLineIsOneDash() throws {
    #expect(try #require(LineDash.dashed.pattern(width: 4, length: 5)) == [5, 7.5])
}

@Test func aBentLineIsMeasuredAlongItsCurve() {
    let straight = CGMutablePath()
    straight.move(to: .zero)
    straight.addLine(to: CGPoint(x: 100, y: 0))
    #expect(LineDash.length(of: straight) == 100)
    let arc = CGMutablePath()
    arc.move(to: .zero)
    arc.addQuadCurve(to: CGPoint(x: 100, y: 0), control: CGPoint(x: 50, y: 50))
    // The exact length of this parabola is about 114.8.
    #expect(abs(LineDash.length(of: arc) - 114.8) < 0.5)
}

@Test func aDashedLineLeavesGapsAndADottedOneDots() throws {
    let xs: [CGFloat] = [10, 30, 100, 190]
    #expect(try inksAt(xs, of: line(.solid)) == [true, true, true, true])
    // 180 long and 6 wide: seven dashes of 11.25 with gaps of 16.9, the gaps' middles at 29.7 and 113.8.
    #expect(try inksAt([12, 30, 100, 114, 188], of: line(.dashed)) == [true, false, true, false, true])
    // Fifteen spaces of 12: dots at 10, 22, 34 …, spaces between them.
    #expect(try inksAt([10, 16, 22, 28, 190], of: line(.dotted)) == [true, false, true, false, true])
}

@Test func anArrowsHeadStaysSolid() throws {
    // The head is 24 long, from 166 to the tip at 190.
    #expect(try inksAt([170, 175, 180, 185], of: line(.dotted, arrow: true)) == [true, true, true, true])
    #expect(try inksAt([170, 175, 180, 185], of: line(.dashed, arrow: true)) == [true, true, true, true])
}

@Test func aBentDashedLineStillDashes() throws {
    var bent = line(.dashed, bend: CGVector(dx: 0, dy: 0.001))
    #expect(try inksAt([12, 30], of: bent) == [true, false])
    bent.lineDash = .solid
    #expect(try inksAt([12, 30], of: bent) == [true, true])
}

@Test func onlyArrowsAndLinesTakeADash() {
    #expect(EditorTool.allCases.filter(\.takesLineDash) == [.arrow, .line])
    var box = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 0, y: 0, width: 20, height: 20)), color: blue, lineWidth: 4)
    box.lineDash = .dashed
    #expect(box.lineDash == .solid)
}

@Test func aLineSavedBeforeDashesIsSolidAndADashedOneRoundTrips() throws {
    let json = #"{"id":"9F0C1E2A-3B4C-4D5E-8F60-718293A4B5C6","kind":{"line":{"from":[0,0],"to":[100,0]}},"color":{"r":1,"g":0,"b":0,"a":1},"lineWidth":4}"#
    let old = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
    #expect(old.lineDash == .solid)
    #expect(try !String(decoding: JSONEncoder().encode(old), as: UTF8.self).contains("dash"), "solid saves nothing")
    var dotted = old
    dotted.lineDash = .dotted
    #expect(try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(dotted)) == dotted)
    let newer = json.replacingOccurrences(of: #""lineWidth":4"#, with: #""lineWidth":4,"dash":"wavy""#)
    #expect(try JSONDecoder().decode(Annotation.self, from: Data(newer.utf8)).lineDash == .solid)
}

@Test func aNewArrowOrLineTakesTheChosenDash() throws {
    let style = AnnotationDraft.Style(
        color: blue, fill: nil, noteColor: RGBA.presets[2], lineWidth: 4, shape: .rectangle, redaction: .blur, redactionAmount: 0.01,
        spotlight: SpotlightStyle(), alignment: .left, noteAlignment: .center, verticalAlignment: .middle, lineDash: .dashed
    )
    for tool in [EditorTool.arrow, .line, .shape] {
        let drawn = try #require(AnnotationDraft.annotation(
            tool: tool, from: .zero, to: CGPoint(x: 50, y: 30), previous: nil, constrain: false, fromCenter: false, minDistance: 1, style: style
        ))
        #expect(drawn.lineDash == (tool == .shape ? .solid : .dashed), "\(tool)")
    }
}

@Test func theStyleBarSetsAndResetsTheDash() {
    let arrow = Annotation(kind: .arrow(from: .zero, to: CGPoint(x: 100, y: 0)), color: blue, lineWidth: 8)
    func palette(tool: EditorTool, selection: Annotation? = nil) -> AnnotationPalette {
        AnnotationPalette(style: EditorStyle(tool: tool), editingText: nil, editingTextIsNew: false, selection: selection, tool: tool, scale: 2, imageLength: 1000, sharedSpotlight: nil)
    }
    #expect(palette(tool: .arrow).lineDash == .solid)
    #expect(palette(tool: .line).lineDash == .solid)
    #expect(palette(tool: .shape).lineDash == nil)
    #expect(palette(tool: .pen).lineDash == nil)
    #expect(palette(tool: .shape).controlRows == [[.width], [.outline]])

    var drawn = palette(tool: .arrow, selection: arrow)
    drawn.setLineDash(.dotted)
    #expect(drawn.selection?.lineDash == .dotted)
    #expect(drawn.style.lineDash == .dotted)
    #expect(drawn.canReset)
    drawn.reset()
    #expect(drawn.selection?.lineDash == .solid)
    #expect(drawn.style.lineDash == .solid)

    // One picked with the select tool restyles alone.
    var picked = palette(tool: .select, selection: arrow)
    picked.setLineDash(.dashed)
    #expect(picked.lineDash == .dashed)
    #expect(picked.style.lineDash == .solid)
}
