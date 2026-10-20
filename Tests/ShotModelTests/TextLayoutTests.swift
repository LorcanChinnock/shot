import Foundation
import Testing
@testable import ShotModel

/// A shaper with fixed glyph widths: a space is a quarter of the font size wide, anything else half, or 0.6 in bold.
/// It breaks lines only at spaces, so a word wider than the line overflows it, as some libraries' word breaks do.
private struct FakeShaper: TextShaper {
    func metrics(of font: TextFont) -> TextMetrics {
        TextMetrics(ascent: font.size * 0.8, descent: font.size * 0.2, leading: font.size * 0.05)
    }

    func line(_ string: String, font: TextFont, color: RGBA) -> any ShapedLine {
        FakeLine(text: string, font: font, color: color)
    }

    func paragraph(_ string: String, font: TextFont, color: RGBA) -> any ShapedParagraph {
        FakeParagraph(units: Array(string.utf16), font: font, color: color)
    }
}

private struct FakeLine: ShapedLine {
    let text: String
    let font: TextFont
    let color: RGBA

    static func width(of unit: UInt16, in font: TextFont) -> CGFloat {
        unit == 32 ? font.size / 4 : font.size * (font.bold ? 0.6 : 0.5)
    }

    var width: CGFloat { text.utf16.reduce(0) { $0 + Self.width(of: $1, in: font) } }
    var trailingWhitespaceWidth: CGFloat { CGFloat(text.utf16.reversed().prefix { $0 == 32 }.count) * font.size / 4 }
    var ascent: CGFloat { font.size * 0.8 }
    var descent: CGFloat { font.size * 0.2 }
}

private struct FakeParagraph: ShapedParagraph {
    let units: [UInt16]
    let font: TextFont
    let color: RGBA

    var length: Int { units.count }

    func lineBreak(from start: Int, width: CGFloat) -> Int {
        var lastBreak: Int?, index = start
        while index < units.count {
            if units[index] == 32 {
                index += 1
                lastBreak = index
                continue
            }
            let used = units[start...index].reduce(0) { $0 + FakeLine.width(of: $1, in: font) }
            if used > width, let lastBreak {
                return lastBreak - start
            }
            index += 1
        }
        return units.count - start
    }

    func clusterBreak(from start: Int, width: CGFloat) -> Int {
        var used: CGFloat = 0, count = 0
        for unit in units[start...] {
            used += FakeLine.width(of: unit, in: font)
            guard used <= width else {
                break
            }
            count += 1
        }
        return count
    }

    func line(from start: Int, count: Int) -> any ShapedLine {
        FakeLine(text: String(decoding: units[start..<start + count], as: UTF16.self), font: font, color: color)
    }
}

private let shaper = FakeShaper()
private let yellow = RGBA(1, 0.8, 0)

private func texts(_ lines: [any ShapedLine]) -> [String] {
    lines.compactMap { ($0 as? FakeLine)?.text }
}

// MARK: Text

@Test func textHasOneBoldLinePerParagraphSizedToTheWidest() throws {
    let layout = TextLayout(string: "Hi there\nA", fontSize: 10, color: yellow, shaper: shaper)
    #expect(texts(layout.lines) == ["Hi there", "A"])
    let first = try #require(layout.lines.first as? FakeLine)
    #expect(first.font == TextFont(size: 10, bold: true))
    #expect(first.color == yellow)
    // Seven letters at 6 and a space at 2.5.
    #expect(layout.size == CGSize(width: 45, height: 22))
    #expect(layout.ascent == 8)
    #expect(layout.lineHeight == 11)
}

@Test func emptyTextIsOneBlankLine() {
    let layout = TextLayout(string: "", fontSize: 10, color: yellow, shaper: shaper)
    #expect(texts(layout.lines) == [" "])
    #expect(layout.size == CGSize(width: 3, height: 11))
}

@Test func aLineIsAsTallAsTheFontRoundedUpToAWholePoint() {
    #expect(TextMetrics(ascent: 8.2, descent: 2.1, leading: 0.3).lineHeight == 11)
    #expect(TextMetrics(ascent: 8, descent: 2, leading: 1).lineHeight == 11)
}

// MARK: Notes

/// A note at font size 10: 6 of padding on each side, so a 72 wide note wraps at 60, twelve letters.
private func note(_ string: String, width: CGFloat = 72, height: CGFloat = 0) -> NoteLayout {
    NoteLayout(string: string, rect: CGRect(x: 5, y: 7, width: width, height: height), fontSize: 10, color: yellow, shaper: shaper)
}

@Test func noteWrapsAtSpacesInRegularInk() throws {
    let layout = note("one two three four")
    #expect(texts(layout.lines) == ["one two three ", "four"])
    let first = try #require(layout.lines.first as? FakeLine)
    #expect(first.font == TextFont(size: 10))
    #expect(first.color == yellow.noteFill.contrastingInk)
    #expect(layout.frame == CGRect(x: 5, y: 7, width: 72, height: 11 * 2 + 12))
}

@Test func noteBreaksAWordWiderThanItBetweenCharacters() {
    #expect(texts(note("abcdefghijklmnopqrstuvwxyz").lines) == ["abcdefghijkl", "mnopqrstuvwx", "yz"])
    #expect(texts(note("go abcdefghijklmnop").lines) == ["go ", "abcdefghijkl", "mnop"])
}

@Test func noteKeepsNewlinesAndAnEmptyNoteHasOneLine() {
    #expect(texts(note("One\nTwo\n\nFour").lines) == ["One", "Two", "", "Four"])
    let empty = note("")
    #expect(texts(empty.lines) == [""])
    #expect(empty.frame.height == empty.lineHeight + empty.padding * 2)
}

@Test func noteHeightIsTheRectOrTheTextWhicheverIsTaller() {
    #expect(note("Hi", height: 300).frame.height == 300)
    let short = note("one two three four five", height: 10)
    #expect(short.frame.height == short.lineHeight * CGFloat(short.lines.count) + short.padding * 2)
}

@Test(arguments: [(VerticalTextAlign.top, 0.0), (.middle, 0.5), (.bottom, 1.0)])
func noteTextSitsAtTheTopMiddleOrBottomOfATallNote(alignment: VerticalTextAlign, share: CGFloat) {
    let layout = NoteLayout(string: "Hi", rect: CGRect(x: 5, y: 7, width: 72, height: 100), fontSize: 10, color: yellow, verticalAlignment: alignment, shaper: shaper)
    let spare = layout.textRect.height - layout.lineHeight
    #expect(layout.alignedTextRect.minY == layout.textRect.minY + spare * share)
    #expect(layout.alignedTextRect.maxY == layout.textRect.maxY)
    #expect(layout.alignedTextRect.minX == layout.textRect.minX && layout.alignedTextRect.width == layout.textRect.width)
}

@Test(arguments: VerticalTextAlign.allCases)
func noteTextThatFillsTheNoteDoesntMove(alignment: VerticalTextAlign) {
    let layout = NoteLayout(string: "one two three four", rect: CGRect(x: 5, y: 7, width: 72, height: 0), fontSize: 10, color: yellow, verticalAlignment: alignment, shaper: shaper)
    #expect(layout.alignedTextRect == layout.textRect)
}

@Test func noteWidthNeverDropsBelowTheMinimum() {
    let layout = note("Hi", width: 5)
    #expect(layout.frame.width == NoteLayout.minWidth(fontSize: 10))
    #expect(layout.textRect.width == 30)
}

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
