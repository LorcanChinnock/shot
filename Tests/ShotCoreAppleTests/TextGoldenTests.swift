import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

// Golden tests for #650: text annotations, counters and notes lay out and draw the same through `CoreTextShaper` as
// through Core Text called straight, `LegacyText`. They go with it once #650 has landed.

private let red = RGBA.presets[0], yellow = RGBA.presets[2], blue = RGBA.presets[4], black = RGBA.presets[5], white = RGBA.presets[6]

/// Strings that take every branch of the layout: empty, blank and trailing-space lines, words that need breaking
/// between characters, and text that shapes in other ways, such as ligatures, combining marks, emoji, and right-to-left
/// and CJK scripts, where a break between characters falls inside a cluster.
private let strings = [
    "", " ", "Hello", "Left\nand two lines", "Trailing spaces   \nnext", "\n\nAfter two blank lines\n",
    "office ﬁnal affine", "Cafe\u{301} cre\u{300}me", "Wave 👋🏽 and 👨‍👩‍👧 family", "שלום עולם and English", "日本語のテキストを折り返す",
    String(repeating: "W", count: 40), String(repeating: "👍🏾", count: 20),
    "Sticky notes wrap their text to the width of the note, so a long comment stays readable.",
]

private func mark(_ kind: Annotation.Kind, color: RGBA = red, width: CGFloat = 4, _ change: (inout Annotation) -> Void = { _ in }) -> Annotation {
    var annotation = Annotation(kind: kind, color: color, lineWidth: width)
    change(&annotation)
    return annotation
}

private func fixtures() -> [(name: String, annotation: Annotation)] {
    var fixtures: [(String, Annotation)] = []
    for (index, string) in strings.enumerated() {
        for alignment in TextAlign.allCases {
            let fontSize: CGFloat = [12, 18, 24.5, 40][index % 4]
            fixtures.append(("text \(index) \(alignment)", mark(.text(string, origin: CGPoint(x: 10.3, y: 12.6), fontSize: fontSize)) { $0.alignment = alignment }))
            let rect = CGRect(x: 8, y: 6.5, width: [60, 140, 230][index % 3], height: index % 2 == 0 ? 0 : 90)
            let color = [yellow, blue, black, white][index % 4]
            fixtures.append(("note \(index) \(alignment)", mark(.note(string, rect: rect), color: color, width: [2, 4, 7][index % 3]) { $0.alignment = alignment }))
        }
        let outline = Border(kind: .outline, lineWidth: [2, 3, 5][index % 3], color: blue)
        fixtures.append(("outlined \(index)", mark(.text(string, origin: CGPoint(x: 14, y: 20), fontSize: 30)) { $0.style = ObjectStyle(border: outline) }))
    }
    for (index, number) in [1, 7, 12, 99, 100, 1234].enumerated() {
        fixtures.append(("counter \(number)", mark(.counter(number, center: CGPoint(x: 60.5, y: 50.25)), color: [red, black, yellow][index % 3], width: [2, 4, 9][index % 3])))
    }
    return fixtures
}

/// `annotation` drawn by `draw` in a clear top-left-origin context `scale` pixels to a point, as its bytes.
private func pixels(of annotation: Annotation, scale: CGFloat, _ draw: (Annotation, CGContext) -> Void) -> Data {
    let width = Int(320 * scale), height = Int(260 * scale)
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: scale, y: -scale)
    draw(annotation, ctx)
    return ctx.makeImage()!.dataProvider!.data! as Data
}

private let base = CGCanvas(width: 1, height: 1, format: .sRGB)!.makeImage()!

@Test(arguments: [0.5, 1, 1.5, 2])
func textDrawsTheSamePixelsAsCoreTextCalledStraight(scale: CGFloat) {
    for (name, annotation) in fixtures() {
        let new = pixels(of: annotation, scale: scale) { AnnotationRenderer.draw($0, base: base, in: $1) }
        let old = pixels(of: annotation, scale: scale) { LegacyText.draw($0, in: CGCanvas($1)) }
        #expect(new == old, "\(name) at \(scale)×")
        // A fixture that draws nothing would pass without showing anything.
        #expect(new.contains { $0 != 0 } || annotation.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "", "\(name) drew nothing")
    }
}

private func expectSame(_ new: [any ShapedLine], _ old: [CTLine], _ name: String) throws {
    #expect(new.count == old.count, "\(name)")
    for (index, (line, legacy)) in zip(new, old).enumerated() {
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(legacy, &ascent, &descent, nil)
        #expect(line.width == width && line.ascent == ascent && line.descent == descent, "\(name) line \(index)")
        let trailing: CGFloat = CTLineGetTrailingWhitespaceWidth(legacy)
        #expect(line.trailingWhitespaceWidth == trailing, "\(name) line \(index)")
        let range = CTLineGetStringRange(try #require(line as? CoreTextLine).line)
        let legacyRange = CTLineGetStringRange(legacy)
        #expect(range.location == legacyRange.location && range.length == legacyRange.length, "\(name) line \(index)")
    }
}

@Test func textLaysOutTheSameAsCoreTextCalledStraight() throws {
    for (name, annotation) in fixtures() {
        switch annotation.kind {
        case let .text(string, origin, fontSize):
            let new = TextLayout(string: string, fontSize: fontSize, color: annotation.color)
            let old = LegacyTextLayout(string: string, fontSize: fontSize, color: annotation.color)
            #expect(new.size == old.size && new.ascent == old.ascent && new.lineHeight == old.lineHeight, "\(name)")
            try expectSame(new.lines, old.lines, name)
            #expect(annotation.bounds == CGRect(origin: origin, size: old.size), "\(name)")
        case let .note(string, rect):
            let new = try #require(annotation.noteLayout)
            let old = LegacyNoteLayout(string: string, rect: rect, fontSize: annotation.noteFontSize, color: annotation.color)
            #expect(new.frame == old.frame && new.ascent == old.ascent && new.lineHeight == old.lineHeight, "\(name)")
            try expectSame(new.lines, old.lines, name)
        case let .counter(number, _):
            let radius = annotation.counterRadius
            let new = TextLayout(string: "\(number)", fontSize: radius * 1.1, color: white)
            try expectSame(new.lines, LegacyTextLayout(string: "\(number)", fontSize: radius * 1.1, color: white).lines, name)
        default:
            Issue.record("\(name) isn't text")
        }
    }
}
