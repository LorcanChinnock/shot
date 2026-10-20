import Foundation
import Testing
@testable import ShotCoreLinux

// ShotModelTests' TextLayout and NoteLayout tests run on a fake shaper with fixed widths. These run the same rules on
// PangoShaper, with widths measured from the font fontconfig picks, and draw its lines on CairoCanvas.

private let shaper = PangoShaper()
private let yellow = RGBA(1, 0.8, 0)

private func texts(_ lines: [any ShapedLine]) -> [String] {
    lines.compactMap { ($0 as? PangoLine)?.text }
}

private func width(_ string: String, size: CGFloat = 10, bold: Bool = false) -> CGFloat {
    shaper.line(string, font: TextFont(size: size, bold: bold), color: yellow).width
}

/// A note at font size 10, whose text wraps at `wrap`: the rect is 6 of padding wider on each side.
private func note(_ string: String, wrap: CGFloat, height: CGFloat = 0) -> NoteLayout {
    NoteLayout(string: string, rect: CGRect(x: 5, y: 7, width: wrap + 12, height: height), fontSize: 10, color: yellow, shaper: shaper)
}

@Test func pangoMeasuresTheFontInTheCanvasUnits() {
    let metrics = shaper.metrics(of: TextFont(size: 20))
    #expect(metrics.ascent > 12 && metrics.ascent < 24)
    #expect(metrics.descent > 2 && metrics.descent < 10)
    #expect(metrics.leading >= 0)
    let doubled = shaper.metrics(of: TextFont(size: 40))
    #expect(abs(doubled.ascent - metrics.ascent * 2) < 0.5)
    let line = shaper.line("Hello", font: TextFont(size: 20), color: yellow)
    #expect(abs(line.ascent - metrics.ascent) < 0.5 && abs(line.descent - metrics.descent) < 0.5)
    #expect(abs(width("Hello", size: 40) - width("Hello", size: 20) * 2) < 0.5)
    #expect(width("Hello", bold: true) > width("Hello"))
}

@Test func aPangoLineCountsItsTrailingWhitespace() {
    let line = shaper.line("Hi  ", font: TextFont(size: 10), color: yellow)
    #expect(abs(line.width - width("Hi") - line.trailingWhitespaceWidth) < 0.01)
    #expect(abs(line.trailingWhitespaceWidth - width("  ")) < 0.5)
    #expect(width("Hi").isFinite && shaper.line("Hi", font: TextFont(size: 10), color: yellow).trailingWhitespaceWidth == 0)
}

@Test func pangoTextHasOneBoldLinePerParagraphSizedToTheWidest() throws {
    let layout = TextLayout(string: "Hi there\nA", fontSize: 10, color: yellow, shaper: shaper)
    #expect(texts(layout.lines) == ["Hi there", "A"])
    #expect(try #require(layout.lines.first as? PangoLine).color == yellow)
    #expect(layout.size.width == width("Hi there", bold: true).rounded(.up))
    #expect(layout.size.height == layout.lineHeight * 2)
    #expect(texts(TextLayout(string: "", fontSize: 10, color: yellow, shaper: shaper).lines) == [" "])
}

@Test func aPangoNoteWrapsAtSpaces() {
    let wrap = width("one two three") + 1
    #expect(texts(note("one two three four", wrap: wrap).lines) == ["one two three ", "four"])
    // Spaces at the end of a line hang past it, however many.
    #expect(texts(note("one two three    four", wrap: wrap).lines) == ["one two three    ", "four"])
    #expect(texts(note("one two three four", wrap: width("one two three") - 1).lines) == ["one two ", "three four"])
}

@Test func aPangoNoteBreaksAWordWiderThanItBetweenCharacters() {
    let alphabet = "abcdefghijklmnopqrstuvwxyz", wrap = width("abcdefghijkl") + 0.5
    let lines = texts(note(alphabet, wrap: wrap).lines)
    #expect(lines.first == "abcdefghijkl")
    #expect(lines.joined() == alphabet && lines.count > 2)
    #expect(lines.allSatisfy { width($0) <= wrap })
    let first = texts(note("go \(alphabet)", wrap: wrap).lines).prefix(2)
    #expect(first == ["go ", "abcdefghijkl"])
}

@Test func aPangoParagraphNeverSplitsACharacterOrCluster() {
    // Each thumb is a surrogate pair and a skin tone, one cluster four code units long.
    let thumbs = String(repeating: "👍🏽", count: 6)
    let lines = texts(note(thumbs, wrap: 30).lines)
    #expect(lines.joined() == thumbs && lines.count > 1)
    #expect(lines.allSatisfy { $0.utf16.count % 4 == 0 && !$0.isEmpty })
    // A width narrower than one cluster still takes a whole one: é and an e with an accent combined onto it.
    let font = TextFont(size: 10)
    #expect(shaper.paragraph("éé", font: font, color: yellow).clusterBreak(from: 0, width: 1) == 1)
    #expect(shaper.paragraph("e\u{301}e\u{301}", font: font, color: yellow).clusterBreak(from: 0, width: 1) == 2)
    #expect(shaper.paragraph("e\u{301}e\u{301}", font: font, color: yellow).clusterBreak(from: 2, width: 100) == 2)
}

@Test func aPangoNoteKeepsNewlinesAndAnEmptyNoteHasOneLine() {
    #expect(texts(note("One\nTwo\n\nFour", wrap: 100).lines) == ["One", "Two", "", "Four"])
    let empty = note("", wrap: 100)
    #expect(texts(empty.lines) == [""])
    #expect(empty.frame.height == empty.lineHeight + empty.padding * 2)
}

@Test func aPangoNoteIsAsTallAsItsLines() {
    let layout = note("one two three four five six", wrap: width("one two") + 1)
    #expect(layout.lines.count == 4)
    #expect(layout.frame.height == layout.lineHeight * 4 + layout.padding * 2)
    #expect(note("Hi", wrap: 100, height: 300).frame.height == 300)
}

@Test func pangoShapesOnManyThreadsAtOnce() async {
    let widths = await withTaskGroup(of: CGFloat.self) { group in
        for _ in 0..<16 {
            group.addTask { PangoShaper().paragraph("one two three", font: TextFont(size: 12), color: yellow).line(from: 4, count: 3).width }
        }
        return await group.reduce(into: []) { $0.append($1) }
    }
    #expect(Set(widths).count == 1)
    #expect(widths.first == width("two", size: 12))
}

// MARK: Drawing

/// `string` drawn by `draw` at `position` on a 60 × 30 canvas turned to have y down, as the renderer turns it.
private func drawn(_ string: String, size: CGFloat = 20, at position: CGPoint = CGPoint(x: 4, y: 22), color: RGBA = RGBA(1, 0, 0),
                   _ setUp: (CairoCanvas) -> Void = { _ in }, outlined: Bool = false) throws -> Bitmap {
    let canvas = try #require(CairoCanvas(width: 60, height: 30, format: .sRGB))
    canvas.translateBy(x: 0, y: 30)
    canvas.scaleBy(x: 1, y: -1)
    setUp(canvas)
    canvas.draw(shaper.line(string, font: TextFont(size: size, bold: true), color: color), at: position, outlined: outlined)
    return try #require(canvas.makeBitmap())
}

/// The rows and columns with ink in them, and the most opaque pixel's colour.
private func ink(_ bitmap: Bitmap) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>, strongest: (r: UInt8, g: UInt8, b: UInt8, a: UInt8))? {
    var rows: [Int] = [], columns: [Int] = [], strongest: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) = (0, 0, 0, 0)
    for y in 0..<bitmap.height {
        for x in 0..<bitmap.width where bitmap[x, y].a > 0 {
            rows.append(y)
            columns.append(x)
            if bitmap[x, y].a > strongest.a {
                strongest = bitmap[x, y]
            }
        }
    }
    guard let top = rows.min(), let bottom = rows.max(), let left = columns.min(), let right = columns.max() else {
        return nil
    }
    return (top...bottom, left...right, strongest)
}

@Test func cairoDrawsAPangoLineUprightOnItsBaselineInItsColour() throws {
    let line = shaper.line("Ty", font: TextFont(size: 20, bold: true), color: RGBA(1, 0, 0))
    let found = try #require(ink(try drawn("Ty")))
    // The T reaches up from the baseline at 22 and the y's tail down past it.
    #expect(found.rows.lowerBound >= Int(22 - line.ascent) - 1 && found.rows.lowerBound < 10)
    #expect(found.rows.upperBound > 22 && found.rows.upperBound <= Int(22 + line.descent) + 1)
    #expect(found.columns.lowerBound >= 4 && found.columns.upperBound <= Int(4 + line.width) + 1)
    #expect(found.strongest == (255, 0, 0, 255))
    // Upright: the T's bar is at the top, so the top row has more ink than the bottom.
    let bitmap = try drawn("T")
    let bar = (0..<60).filter { bitmap[$0, found.rows.lowerBound + 1].a > 128 }.count
    let stem = (0..<60).filter { bitmap[$0, 20].a > 128 }.count
    #expect(bar > stem * 2)
}

@Test func anOutlinedPangoLineIsStrokedInTheStrokeColourAndWidth() throws {
    func outlined(_ lineWidth: CGFloat) throws -> Bitmap {
        try drawn("O", { canvas in
            canvas.setStrokeColor(RGBA(0, 0, 1))
            canvas.setLineWidth(lineWidth)
        }, outlined: true)
    }
    let thin = try outlined(1), thick = try outlined(4)
    #expect(try #require(ink(thick)).strongest == (0, 0, 255, 255))
    let covered = { (bitmap: Bitmap) in (0..<bitmap.height).reduce(0) { sum, y in sum + (0..<bitmap.width).filter { bitmap[$0, y].a > 128 }.count } }
    #expect(covered(thick) > covered(thin) * 2)
    // The O's middle stays clear, unlike a filled one's edges.
    let filled = try drawn("O")
    #expect(covered(thin) < covered(filled))
}

@Test func aTranslucentOrShadowedPangoLineIsFadedAndShadowedAsAWhole() throws {
    let faded = try drawn("H", { $0.setAlpha(0.5) })
    #expect(try #require(ink(faded)).strongest.a == 128)
    let shadowed = try drawn("H", { $0.setShadow(offset: CGSize(width: 6, height: 0), blur: 0, color: RGBA(0, 0, 0)) })
    let plain = try #require(ink(try drawn("H")))
    #expect(try #require(ink(shadowed)).columns.upperBound >= plain.columns.upperBound + 5)
}

@Test func pangoFindsNoColourEmojiFontWhereOnlyDejaVuIsInstalled() {
    // The test image installs fonts-dejavu-core and nothing else, and DejaVu's emoji are black and white.
    #expect(!PangoShaper.hasColorEmoji)
}
