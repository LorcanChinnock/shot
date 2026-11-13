import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import ShotCore

private let black = RGBA(0, 0, 0)

private func runs(_ pairs: (Int, CGFloat)...) -> TextRuns {
    TextRuns(pairs.map { TextRun(length: $0.0, size: $0.1) })
}

/// "Big small": "Big " at 48 pixels and "small" at 24, on an image of scale 2, so 24 and 12 points.
private func mixedText(width: CGFloat? = nil) -> Annotation {
    var text = Annotation(kind: .text("Big small", origin: CGPoint(x: 10, y: 10), fontSize: 48), color: black, lineWidth: 8)
    text.textWidth = width
    text.setTextRuns(runs((4, 48), (5, 24)))
    return text
}

// MARK: Runs

@Test func runsMergeNeighboursOfOneSizeAndDropEmptyOnes() {
    let merged = runs((2, 10), (0, 30), (3, 10), (1, 20))
    #expect(merged.runs == [TextRun(length: 5, size: 10), TextRun(length: 1, size: 20)])
    #expect(merged.length == 6)
    #expect(!merged.isUniform)
    #expect(TextRuns(length: 4, size: 12).isUniform)
    #expect(TextRuns([]).isUniform && TextRuns([]).largest == nil)
}

@Test func runsAnswerTheSizeAtAPlaceAndAcrossARange() {
    let sizes = runs((3, 10), (3, 20))
    #expect(sizes.size(at: 0) == 10 && sizes.size(at: 3) == 20 && sizes.size(at: 6) == nil)
    #expect(sizes.uniformSize(in: 0..<3) == 10)
    #expect(sizes.uniformSize(in: 2..<4) == nil)
    #expect(sizes.largest(in: 0..<4) == 20)
    #expect(sizes.largest == 20)
}

@Test func theCaretTakesTheSizeBeforeIt() {
    let sizes = runs((3, 10), (3, 20))
    #expect(sizes.caretSize(at: 0) == 10)
    #expect(sizes.caretSize(at: 3) == 10)
    #expect(sizes.caretSize(at: 4) == 20)
    #expect(sizes.caretSize(at: 99) == 20)
    #expect(sizes.uniformSize(in: 4..<4) == 20)
    #expect(TextRuns([]).caretSize(at: 0) == nil)
}

@Test func typingTakesTheSizeOfTheTextBeforeIt() {
    let sizes = runs((3, 10), (3, 20))
    #expect(sizes.replacing(1..<1, withCount: 2, fallback: 5) == runs((5, 10), (3, 20)))
    // At the end of a run, typing carries it on.
    #expect(sizes.replacing(3..<3, withCount: 1, fallback: 5) == runs((4, 10), (3, 20)))
    // At the very start, it takes the first run's size.
    #expect(sizes.replacing(0..<0, withCount: 1, fallback: 5) == runs((4, 10), (3, 20)))
    #expect(TextRuns([]).replacing(0..<0, withCount: 2, fallback: 5) == runs((2, 5)))
}

@Test func deletingShrinksRunsAndJoinsWhatsLeft() {
    let sizes = runs((2, 10), (2, 20), (2, 10))
    #expect(sizes.replacing(1..<2, withCount: 0, fallback: 5) == runs((1, 10), (2, 20), (2, 10)))
    #expect(sizes.replacing(2..<4, withCount: 0, fallback: 5) == runs((4, 10)))
    #expect(sizes.replacing(1..<5, withCount: 0, fallback: 5) == runs((2, 10)))
    #expect(sizes.replacing(0..<6, withCount: 0, fallback: 5) == TextRuns([]))
}

@Test func editingTextKeepsTheSizesOfWhatStays() {
    let sizes = runs((4, 48), (5, 24))
    #expect(sizes.edited(from: "Big small", to: "Big smaller", fallback: 1) == runs((4, 48), (7, 24)))
    #expect(sizes.edited(from: "Big small", to: "Bigger small", fallback: 1) == runs((7, 48), (5, 24)))
    #expect(sizes.edited(from: "Big small", to: "small", fallback: 1) == runs((5, 24)))
    #expect(sizes.edited(from: "Big small", to: "Big small", fallback: 1) == sizes)
    // An emoji is two UTF-16 code units, as the text field counts them.
    #expect(sizes.edited(from: "Big small", to: "Big 👋small", fallback: 1) == runs((6, 48), (5, 24)))
}

@Test func aRangeTakesOneSizeOrIsScaled() {
    let sizes = runs((3, 10), (3, 20))
    #expect(sizes.setting(30, in: 2..<4) == runs((2, 10), (2, 30), (2, 20)))
    #expect(sizes.setting(10, in: 3..<6) == runs((6, 10)))
    #expect(sizes.mapping(in: 0..<6) { $0 * 2 } == runs((3, 20), (3, 40)))
    #expect(sizes.mapping(in: 4..<6) { $0 / 2 } == runs((3, 10), (1, 20), (2, 10)))
    #expect(sizes.setting(30, in: 4..<99) == runs((3, 10), (1, 20), (2, 30)))
}

// MARK: Annotations

@Test func textSavedBeforeSizesDifferedOpensAsOneSize() throws {
    let id = UUID()
    let json = """
    {"id":"\(id.uuidString)","kind":{"text":{"_0":"Hello","origin":[1,2],"fontSize":30}},"color":{"r":1,"g":0,"b":0,"a":1},"lineWidth":5}
    """
    let text = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
    #expect(text.textRuns == TextRuns(length: 5, size: 30))
    #expect(text.textSize == 30)
    #expect(text.bounds.size == TextLayout(string: "Hello", fontSize: 30, color: text.color).size)
    let note = try JSONDecoder().decode(Annotation.self, from: Data("""
    {"id":"\(id.uuidString)","kind":{"note":{"_0":"Hi","rect":[[0,0],[100,0]]}},"color":{"r":1,"g":1,"b":0,"a":1},"lineWidth":4}
    """.utf8))
    #expect(note.textRuns == TextRuns(length: 2, size: 20))
}

@Test func textInOneSizeSavesNoRuns() throws {
    var text = Annotation(kind: .text("Hello", origin: .zero, fontSize: 30), color: black, lineWidth: 5)
    text.setTextRuns(TextRuns(length: 5, size: 36))
    let json = try #require(String(data: JSONEncoder().encode(text), encoding: .utf8))
    #expect(!json.contains("sizeRuns"))
    #expect(text.textSize == 36 && text.lineWidth == 6)
}

@Test func textInMixedSizesRoundTrips() throws {
    let text = mixedText()
    let json = try JSONEncoder().encode(text)
    #expect(String(data: json, encoding: .utf8)?.contains("sizeRuns") == true)
    let decoded = try JSONDecoder().decode(Annotation.self, from: json)
    #expect(decoded == text)
    #expect(decoded.textRuns == runs((4, 48), (5, 24)))
    // Copying a mark onto the pasteboard keeps its sizes too.
    #expect(try AnnotationClipboard.annotation(from: AnnotationClipboard.data(for: text)).textRuns == text.textRuns)
}

@Test func runsThatDontFitTheTextAreDroppedOnOpening() throws {
    let id = UUID()
    let json = """
    {"id":"\(id.uuidString)","kind":{"text":{"_0":"Hello","origin":[1,2],"fontSize":30}},"color":{"r":1,"g":0,"b":0,"a":1},"lineWidth":5,
     "sizeRuns":[{"length":2,"scale":0.5},{"length":9,"scale":1}]}
    """
    let text = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
    #expect(text.textRuns == TextRuns(length: 5, size: 30))
    #expect(text == Annotation(id: id, kind: .text("Hello", origin: CGPoint(x: 1, y: 2), fontSize: 30), color: RGBA(1, 0, 0), lineWidth: 5))
}

@Test func theLargestPartSetsTheTextsSize() {
    let text = mixedText()
    #expect(text.textSize == 48 && text.lineWidth == 8)
    var smaller = text
    smaller.setTextRuns(runs((4, 12), (5, 24)))
    #expect(smaller.textSize == 24 && smaller.lineWidth == 4)
    #expect(smaller.textRuns == runs((4, 12), (5, 24)))
    var note = Annotation(kind: .note("Big small", rect: CGRect(x: 0, y: 0, width: 300, height: 0)), color: RGBA.presets[2], lineWidth: 4)
    note.setTextRuns(runs((4, 32), (5, 20)))
    #expect(note.noteFontSize == 32 && note.textRuns == runs((4, 32), (5, 20)))
}

@Test func runsThatDontCoverTheTextChangeNothing() {
    var text = mixedText()
    text.setTextRuns(runs((3, 10)))
    #expect(text.textRuns == runs((4, 48), (5, 24)) && text.textSize == 48)
    var arrow = Annotation(kind: .arrow(from: .zero, to: CGPoint(x: 9, y: 9)), color: black, lineWidth: 4)
    arrow.setTextRuns(runs((1, 10)))
    #expect(arrow.textRuns == nil && arrow.lineWidth == 4)
}

@Test func changingTheTextKeepsTheSizesOfWhatStays() {
    var text = mixedText()
    text.setText("Big smallest")
    #expect(text.textRuns == runs((4, 48), (8, 24)))
    text.setText("smallest")
    #expect(text.textRuns == runs((8, 24)))
    #expect(text.textSize == 24)
}

@Test func scalingMixedTextScalesEveryPart() {
    let text = mixedText()
    var widened = text
    widened.setLineWidth(12)
    #expect(widened.textRuns == runs((4, 72), (5, 36)))
    let animated = text.scaled(by: 0.5)
    #expect(animated.textRuns == runs((4, 24), (5, 12)))
}

// MARK: Layout

@Test func textInOneSizeLaysOutAsBefore() {
    let plain = TextLayout(string: "One\nTwo", fontSize: 30, color: black)
    let withRuns = TextLayout(string: "One\nTwo", fontSize: 30, color: black, runs: TextRuns(length: 7, size: 30))
    #expect(plain.size == withRuns.size)
    #expect(plain.baselines == [plain.ascent, plain.ascent + plain.lineHeight])
    #expect(withRuns.baselines == plain.baselines)
}

@Test func aLineIsAsTallAsTheLargestTextInIt() {
    let big = TextLayout.lineHeight(fontSize: 48), small = TextLayout.lineHeight(fontSize: 24)
    let layout = TextLayout(string: "Big\nsmall", fontSize: 48, color: black, runs: runs((4, 48), (5, 24)))
    #expect(layout.lines.count == 2)
    #expect(layout.size.height == big + small)
    #expect(layout.baselines[0] == CoreTextShaper.metrics(of: TextFont(size: 48, bold: true)).ascent)
    #expect(layout.baselines[1] == big + CoreTextShaper.metrics(of: TextFont(size: 24, bold: true)).ascent)
    let oneLine = TextLayout(string: "Big small", fontSize: 48, color: black, runs: runs((4, 48), (5, 24)))
    #expect(oneLine.size.height == big)
    // Smaller text takes less room across than the same text all at the larger size.
    #expect(oneLine.size.width < TextLayout(string: "Big small", fontSize: 48, color: black).size.width)
    #expect(oneLine.size.width > TextLayout(string: "Big small", fontSize: 24, color: black).size.width)
}

@Test func mixedTextWrapsByTheWidthOfEachPart() {
    // At 24, "small small" fits on a line a wrap width this narrow holds; at 48 it wouldn't.
    let width = TextLayout(string: "small small", fontSize: 24, color: black).size.width + 2
    let mixed = TextLayout(string: "Big small small", fontSize: 48, color: black, width: width, runs: runs((4, 48), (11, 24)))
    let large = TextLayout(string: "Big small small", fontSize: 48, color: black, width: width)
    #expect(mixed.lines.count == 2)
    #expect(large.lines.count > 2)
    #expect(mixed.size.height == TextLayout.lineHeight(fontSize: 48) + TextLayout.lineHeight(fontSize: 24))
}

@Test func anEmptyLineIsAsTallAsItsLineBreak() {
    let layout = TextLayout(string: "a\n\nb", fontSize: 40, color: black, width: 400, runs: runs((1, 40), (1, 20), (1, 10), (1, 40)))
    #expect(layout.lines.count == 3)
    #expect(layout.size.height == TextLayout.lineHeight(fontSize: 40) * 2 + TextLayout.lineHeight(fontSize: 10))
}

@Test func mixedTextsBoundsAndHitTestingFollowItsLayout() {
    let text = mixedText()
    let layout = TextLayout(string: "Big small", fontSize: 48, color: black, runs: text.textRuns)
    #expect(text.bounds == CGRect(origin: CGPoint(x: 10, y: 10), size: layout.size))
    #expect(text.hitTest(CGPoint(x: 10 + layout.size.width - 2, y: 20), tolerance: 0))
    #expect(!text.hitTest(CGPoint(x: 10 + layout.size.width + 4, y: 20), tolerance: 0))
    let box = mixedText(width: 120)
    #expect(box.bounds.width == 120)
    #expect(box.bounds.height == TextLayout(string: "Big small", fontSize: 48, color: black, width: 120, runs: box.textRuns).size.height)
}

@Test func aNoteFitsItsMixedText() throws {
    var note = Annotation(kind: .note("Big\nsmall", rect: CGRect(x: 0, y: 0, width: 300, height: 0)), color: RGBA.presets[2], lineWidth: 8)
    let plain = try #require(note.noteLayout)
    note.setTextRuns(runs((4, 32), (5, 16)))
    let mixed = try #require(note.noteLayout)
    #expect(mixed.fontSize == 32 && mixed.padding == plain.padding)
    #expect(mixed.textHeight == TextLayout.lineHeight(fontSize: 32) + CoreTextShaper.metrics(of: TextFont(size: 16)).lineHeight)
    #expect(mixed.frame.height == mixed.textHeight + mixed.padding * 2)
    #expect(mixed.frame.height < plain.frame.height)
}

// MARK: Drawing

/// The x of the leftmost dark pixel in the topmost row with any, and the lowest row with any, in a white image.
private func ink(_ image: CGImage) throws -> (topX: Int, bottom: Int) {
    var topX: Int?, bottom = 0
    for y in 0..<image.height {
        for x in 0..<image.width where try pixelBytes(image, x, y)[0] < 100 {
            topX = topX ?? x
            bottom = y
        }
    }
    return (try #require(topX), bottom)
}

/// Checks `image` shows `smallThenLarge`: the tallest ink starts where the small letters end, not where they would at the
/// large size, and both sit on the large size's baseline.
private func expectSmallThenLarge(_ image: CGImage) throws {
    func width(_ size: CGFloat) -> CGFloat { CoreTextShaper.line("aa", font: TextFont(size: size, bold: true), color: black).width }
    let found = try ink(image)
    #expect(CGFloat(found.topX) >= (4 + width(10)).rounded(.down))
    #expect(CGFloat(found.topX) < 4 + width(40) - 2)
    let baseline = 4 + CoreTextShaper.metrics(of: TextFont(size: 40, bold: true)).ascent
    #expect(abs(CGFloat(found.bottom) - baseline) < 3)
}

private func whiteImage(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

/// "aaHH" with the capitals four times the size of the small letters: the tallest ink is in its right half.
private func smallThenLarge() -> Annotation {
    var text = Annotation(kind: .text("aaHH", origin: CGPoint(x: 4, y: 4), fontSize: 40), color: black, lineWidth: 40 / 6.0)
    text.setTextRuns(runs((2, 10), (2, 40)))
    return text
}

@Test func theImageEditorDrawsEachPartInItsSize() throws {
    let doc = EditorDocument(base: whiteImage(width: 120, height: 60), annotations: [smallThenLarge()])
    let image = try #require(AnnotationRenderer.flatten(doc))
    try expectSmallThenLarge(image)
}

@Test func theVideoCompositorDrawsEachPartInItsSize() throws {
    let canvas = CGRect(x: 0, y: 0, width: 120, height: 60)
    let context = CIContext()
    let white = CIImage(color: .white).cropped(to: canvas)
    let frame = AnnotationFrame.apply([AnnotationFrame.Item(annotation: smallThenLarge())], to: white, canvas: canvas, context: context)
    let image = try #require(context.createCGImage(frame, from: canvas, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
    try expectSmallThenLarge(image)
}

// MARK: The size box

private func sizing(editing: Annotation? = nil, selection: Range<Int>? = nil, selected: Annotation? = nil, tool: EditorTool = .text) -> AnnotationPalette {
    AnnotationPalette(
        style: EditorStyle(tool: tool), editingText: editing, editingTextIsNew: false, editingSelection: selection, selection: selected,
        tool: tool, scale: 2, imageLength: 1000, sharedSpotlight: nil
    )
}

@Test func theSizeBoxShowsTheSizeSelectedOrADashForMixed() {
    let text = mixedText()
    #expect(sizing(editing: text, selection: 4..<9).shownSize == 12)
    #expect(sizing(editing: text, selection: 0..<3).shownSize == 24)
    #expect(sizing(editing: text, selection: 2..<6).shownSize == nil)
    #expect(sizing(editing: text, selection: 0..<9).shownSize == nil)
    #expect(sizing(selected: text, tool: .select).shownSize == nil)
    // With a caret, the size there.
    #expect(sizing(editing: text, selection: 6..<6).shownSize == 12)
    #expect(sizing(editing: text, selection: 2..<2).shownSize == 24)
    #expect(sizing(editing: text, selection: 0..<0).shownSize == 24)
    // Text in one size shows it, as it always has.
    let plain = Annotation(kind: .text("Hello", origin: .zero, fontSize: 48), color: black, lineWidth: 8)
    #expect(sizing(editing: plain, selection: 0..<5).shownSize == 24)
    #expect(sizing(editing: plain, selection: 1..<3).shownSize == 24)
}

@Test func aSizeTypedForPartOfTheTextSizesOnlyThatPart() throws {
    var palette = sizing(editing: mixedText(), selection: 4..<9)
    palette.setShownSize(18)
    #expect(palette.editingText?.textRuns == runs((4, 48), (5, 36)))
    #expect(palette.style.width == EditorStyle().width)
    // A mixed part all takes the size typed.
    var mixed = sizing(editing: mixedText(), selection: 2..<6)
    mixed.setShownSize(30)
    #expect(mixed.editingText?.textRuns == runs((2, 48), (4, 60), (3, 24)))
    #expect(mixed.editingText?.textSize == 60)
    // Part of text in one size, too.
    var plain = sizing(editing: Annotation(kind: .text("Hello", origin: .zero, fontSize: 48), color: black, lineWidth: 8), selection: 0..<2)
    plain.setShownSize(12)
    #expect(plain.editingText?.textRuns == runs((2, 24), (3, 48)))
}

@Test func theArrowsStepPartOfTheTextAndScaleAMixedPart() {
    var part = sizing(editing: mixedText(), selection: 4..<9)
    part.stepLineWidth(by: 1)
    #expect(part.editingText?.textRuns == runs((4, 48), (5, 36)))
    part.stepLineWidth(by: -1)
    part.stepLineWidth(by: -1)
    #expect(part.editingText?.textRuns == runs((4, 48), (5, 18)))
    // A mixed part steps its largest and keeps the rest in proportion.
    var mixed = sizing(editing: mixedText(), selection: 2..<6)
    mixed.stepLineWidth(by: 1)
    #expect(mixed.editingText?.textRuns == runs((2, 48), (2, 60), (2, 30), (3, 24)))
}

@Test func withNothingOrEverythingSelectedTheWholeTextScales() {
    // Everything selected: the largest part becomes the size typed.
    var all = sizing(editing: mixedText(), selection: 0..<9)
    all.setShownSize(36)
    #expect(all.editingText?.textRuns == runs((4, 72), (5, 36)))
    // A caret steps the size at the caret, and the rest keeps its proportion.
    var caret = sizing(editing: mixedText(), selection: 6..<6)
    caret.stepLineWidth(by: 1)
    #expect(caret.editingText?.textRuns == runs((4, 72), (5, 36)))
    // A selected mark that isn't being edited steps its largest part.
    var mark = sizing(selected: mixedText(), tool: .select)
    #expect(mark.canStepLineWidth(by: -1))
    mark.stepLineWidth(by: -1)
    #expect(mark.selection?.textRuns == runs((4, 36), (5, 18)))
}

@Test func scaledPartsStayWithinTheSizesAndOnHalfPoints() {
    // 6 is the smallest text size, so scaling 24 and 12 down to 6 leaves both at 6.
    var smallest = sizing(editing: mixedText(), selection: 0..<9)
    smallest.setShownSize(6)
    #expect(smallest.editingText?.textRuns == runs((9, 12)))
    // 13 scaled by 30/24 is 16.25, which shows as 16.5.
    var text = mixedText()
    text.setTextRuns(runs((4, 48), (5, 26)))
    var stepped = sizing(editing: text, selection: 0..<0)
    stepped.stepLineWidth(by: 1)
    #expect(stepped.editingText?.textRuns == runs((4, 60), (5, 33)))
    // Text whose largest part is the largest size can't step larger.
    var largest = mixedText()
    largest.setTextRuns(runs((4, 192), (5, 24)))
    #expect(!sizing(editing: largest, selection: 0..<9).canStepLineWidth(by: 1))
    #expect(sizing(editing: largest, selection: 4..<9).canStepLineWidth(by: 1))
}

@Test func aNotesPartsShowInTheNotesSizes() throws {
    // A note at width 4 on a 2x image: 32 pixels, which shows as 20.
    var note = Annotation(kind: .note("Big small", rect: CGRect(x: 0, y: 0, width: 300, height: 0)), color: RGBA.presets[2], lineWidth: 8)
    var palette = sizing(editing: note, selection: 4..<9, tool: .note)
    #expect(palette.shownSize == 20)
    palette.setShownSize(14)
    #expect(palette.editingText?.textRuns == runs((4, 32), (5, 20)))
    note = try #require(palette.editingText)
    #expect(sizing(editing: note, selection: 4..<9, tool: .note).shownSize == 14)
    #expect(sizing(editing: note, selection: 0..<9, tool: .note).shownSize == nil)
}

@Test func resetPutsMixedTextBackInOneSize() {
    var palette = sizing(selected: mixedText(), tool: .select)
    palette.reset()
    #expect(palette.selection?.textRuns?.isUniform == true)
    #expect(palette.selection?.textSize == EditorStyle.defaultWidth * 6 * 2)
}
