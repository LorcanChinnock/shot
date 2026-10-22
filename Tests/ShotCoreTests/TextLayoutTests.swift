import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import ShotCore

private let yellow = RGBA(1, 0.8, 0)

/// The text of each of `lines`, laid out from `string`: a line that starts its paragraph begins at 0.
private func texts(_ lines: [CoreTextLine], of string: String) -> [String] {
    var paragraphs = string.components(separatedBy: "\n").map { Array($0.utf16) }[...]
    var paragraph: [UInt16] = []
    return lines.map { line in
        let range = CTLineGetStringRange(line.line)
        if range.location == 0 {
            paragraph = paragraphs.popFirst() ?? []
        }
        let end = min(paragraph.count, range.location + range.length)
        return String(decoding: paragraph[min(range.location, end)..<end], as: UTF16.self)
    }
}

/// The font and colour of `line`'s first glyph run.
private func style(of line: CoreTextLine) throws -> (font: CTFont, color: CGColor) {
    let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] ?? []
    let attributes = try #require(runs.first.map { CTRunGetAttributes($0) as NSDictionary })
    let font = try #require(attributes[kCTFontAttributeName] as! CTFont?)
    let color = try #require(attributes[kCTForegroundColorAttributeName] as! CGColor?)
    return (font, color)
}

// MARK: Text

@Test func textHasOneBoldLinePerParagraphSizedToTheWidest() throws {
    let layout = TextLayout(string: "Hi there\nA", fontSize: 10, color: yellow)
    #expect(texts(layout.lines, of: "Hi there\nA") == ["Hi there", "A"])
    let (font, color) = try style(of: try #require(layout.lines.first))
    #expect(CTFontGetSize(font) == 10)
    #expect(CTFontGetSymbolicTraits(font).contains(.traitBold))
    #expect(color == yellow.cgColor)
    let bold = TextFont(size: 10, bold: true)
    let widest = max(CoreTextShaper.line("Hi there", font: bold, color: yellow).width, CoreTextShaper.line("A", font: bold, color: yellow).width)
    let metrics = CoreTextShaper.metrics(of: bold)
    #expect(layout.size == CGSize(width: widest.rounded(.up), height: metrics.lineHeight * 2))
    #expect(layout.ascent == metrics.ascent)
    #expect(layout.lineHeight == metrics.lineHeight)
}

@Test func emptyTextIsOneBlankLine() {
    let layout = TextLayout(string: "", fontSize: 10, color: yellow)
    #expect(texts(layout.lines, of: " ") == [" "])
    let bold = TextFont(size: 10, bold: true)
    #expect(layout.size == CGSize(width: CoreTextShaper.line(" ", font: bold, color: yellow).width.rounded(.up), height: CoreTextShaper.metrics(of: bold).lineHeight))
}

@Test func aLineIsAsTallAsTheFontRoundedUpToAWholePoint() {
    #expect(TextMetrics(ascent: 8.2, descent: 2.1, leading: 0.3).lineHeight == 11)
    #expect(TextMetrics(ascent: 8, descent: 2, leading: 1).lineHeight == 11)
}

// MARK: Notes

/// A note at font size 10: 6 of padding on each side, so a 72 wide note wraps at 60.
private func note(_ string: String, width: CGFloat = 72, height: CGFloat = 0) -> NoteLayout {
    NoteLayout(string: string, rect: CGRect(x: 5, y: 7, width: width, height: height), fontSize: 10, color: yellow)
}

/// Every line fits the note's text width, not counting the spaces it ends with.
private func expectEachLineFits(_ layout: NoteLayout) {
    for line in layout.lines {
        #expect(line.width - line.trailingWhitespaceWidth <= layout.textRect.width)
    }
}

@Test func noteWrapsAtSpacesInRegularInk() throws {
    let string = "one two three four five six"
    let layout = note(string)
    let lines = texts(layout.lines, of: string)
    #expect(lines.count > 1)
    #expect(lines.joined() == string)
    // Each line but the last ends at a space, so no word is split.
    #expect(lines.dropLast().allSatisfy { $0.hasSuffix(" ") })
    expectEachLineFits(layout)
    let (font, color) = try style(of: try #require(layout.lines.first))
    #expect(CTFontGetSize(font) == 10)
    #expect(!CTFontGetSymbolicTraits(font).contains(.traitBold))
    #expect(color == yellow.noteFill.contrastingInk.cgColor)
    let lineHeight = CoreTextShaper.metrics(of: TextFont(size: 10)).lineHeight
    #expect(layout.frame == CGRect(x: 5, y: 7, width: 72, height: lineHeight * CGFloat(lines.count) + 12))
}

@Test func noteBreaksAWordWiderThanItBetweenCharacters() {
    let alphabet = "abcdefghijklmnopqrstuvwxyz"
    let long = note(alphabet)
    let lines = texts(long.lines, of: alphabet)
    #expect(lines.count > 1)
    #expect(lines.joined() == alphabet)
    #expect(!lines.contains(""))
    expectEachLineFits(long)

    let after = note("go abcdefghijklmnop")
    let split = texts(after.lines, of: "go abcdefghijklmnop")
    #expect(split.first == "go ")
    #expect(split.count > 2)
    #expect(split.dropFirst().joined() == "abcdefghijklmnop")
    expectEachLineFits(after)
}

@Test func noteKeepsNewlinesAndAnEmptyNoteHasOneLine() {
    #expect(texts(note("One\nTwo\n\nFour").lines, of: "One\nTwo\n\nFour") == ["One", "Two", "", "Four"])
    let empty = note("")
    #expect(texts(empty.lines, of: "") == [""])
    #expect(empty.frame.height == empty.lineHeight + empty.padding * 2)
}

@Test func noteHeightIsTheRectOrTheTextWhicheverIsTaller() {
    #expect(note("Hi", height: 300).frame.height == 300)
    let short = note("one two three four five", height: 10)
    #expect(short.frame.height == short.lineHeight * CGFloat(short.lines.count) + short.padding * 2)
}

@Test(arguments: [(VerticalTextAlign.top, 0.0), (.middle, 0.5), (.bottom, 1.0)])
func noteTextSitsAtTheTopMiddleOrBottomOfATallNote(alignment: VerticalTextAlign, share: CGFloat) {
    let layout = NoteLayout(string: "Hi", rect: CGRect(x: 5, y: 7, width: 72, height: 100), fontSize: 10, color: yellow, verticalAlignment: alignment)
    let spare = layout.textRect.height - layout.lineHeight
    #expect(layout.alignedTextRect.minY == layout.textRect.minY + spare * share)
    #expect(layout.alignedTextRect.maxY == layout.textRect.maxY)
    #expect(layout.alignedTextRect.minX == layout.textRect.minX && layout.alignedTextRect.width == layout.textRect.width)
}

@Test(arguments: VerticalTextAlign.allCases)
func noteTextThatFillsTheNoteDoesntMove(alignment: VerticalTextAlign) {
    let layout = NoteLayout(string: "one two three four", rect: CGRect(x: 5, y: 7, width: 72, height: 0), fontSize: 10, color: yellow, verticalAlignment: alignment)
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
