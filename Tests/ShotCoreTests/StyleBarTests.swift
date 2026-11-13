import CoreGraphics
import Testing
@testable import ShotCore

private let canvas = CGSize(width: 800, height: 500)
private let bar = CGSize(width: 260, height: 32)

@Test func theBarSitsAtTheTopCentreWithNoMark() {
    #expect(StyleBarPlacement.origin(bar: bar, mark: nil, in: canvas) == CGPoint(x: 270, y: 12))
}

@Test func theBarSitsCentredAboveTheMark() {
    let mark = CGRect(x: 300, y: 200, width: 120, height: 80)
    let origin = StyleBarPlacement.origin(bar: bar, mark: mark, in: canvas)
    #expect(origin == CGPoint(x: 230, y: 200 - 10 - 32))
}

@Test func theBarGoesBelowAMarkAtTheTop() {
    let mark = CGRect(x: 300, y: 20, width: 120, height: 80)
    #expect(StyleBarPlacement.origin(bar: bar, mark: mark, in: canvas) == CGPoint(x: 230, y: 110))
}

@Test func theBarGoesBesideAMarkAsTallAsTheCanvas() {
    let right = StyleBarPlacement.origin(bar: bar, mark: CGRect(x: 100, y: 10, width: 200, height: 480), in: canvas)
    #expect(right == CGPoint(x: 310, y: 234))
    let left = StyleBarPlacement.origin(bar: bar, mark: CGRect(x: 500, y: 10, width: 200, height: 480), in: canvas)
    #expect(left == CGPoint(x: 230, y: 234))
}

@Test func theBarSlidesAlongTheEdgeToStayInTheCanvas() {
    let nearLeft = StyleBarPlacement.origin(bar: bar, mark: CGRect(x: 0, y: 200, width: 40, height: 40), in: canvas)
    #expect(nearLeft.x == 12)
    let nearRight = StyleBarPlacement.origin(bar: bar, mark: CGRect(x: 780, y: 200, width: 40, height: 40), in: canvas)
    #expect(nearRight.x == 528)
}

@Test func theBarNeverCoversAMarkThatLeavesRoom() {
    let marks = [
        CGRect(x: 0, y: 0, width: 60, height: 60), CGRect(x: 740, y: 440, width: 60, height: 60),
        CGRect(x: 100, y: 30, width: 400, height: 440), CGRect(x: 350, y: 0, width: 100, height: 500),
        CGRect(x: -200, y: -100, width: 300, height: 200),
    ]
    for mark in marks {
        let frame = CGRect(origin: StyleBarPlacement.origin(bar: bar, mark: mark, in: canvas), size: bar)
        #expect(!frame.intersects(mark), "\(mark)")
        #expect(CGRect(origin: .zero, size: canvas).insetBy(dx: 12, dy: 12).contains(frame), "\(mark)")
    }
}

@Test func aMarkFillingTheCanvasGetsTheBarAtTheTop() {
    let mark = CGRect(x: -50, y: -50, width: 900, height: 600)
    #expect(StyleBarPlacement.origin(bar: bar, mark: mark, in: canvas) == CGPoint(x: 270, y: 12))
}

@Test func aCanvasNarrowerThanTheBarKeepsItAtTheInset() {
    #expect(StyleBarPlacement.origin(bar: bar, mark: nil, in: CGSize(width: 200, height: 300)) == CGPoint(x: 12, y: 12))
}

@Test func theBarShowsWhatTheOptionsRowDid() {
    #expect(StyleBarContent.content(showsStyle: true, tool: .arrow, showsRedaction: false, showsSpotlight: false) == .colorAndWidth)
    #expect(StyleBarContent.content(showsStyle: false, tool: .redact, showsRedaction: true, showsSpotlight: false) == .redaction)
    #expect(StyleBarContent.content(showsStyle: false, tool: .spotlight, showsRedaction: false, showsSpotlight: true) == .spotlight)
    #expect(StyleBarContent.content(showsStyle: false, tool: .select, showsRedaction: false, showsSpotlight: false) == nil)
    #expect(StyleBarContent.content(showsStyle: false, tool: .hand, showsRedaction: false, showsSpotlight: false) == nil)
}

@Test func cropModeHasNoStyleBarSinceTheCropBarTakesItsPlace() {
    #expect(StyleBarContent.content(showsStyle: false, tool: .crop, showsRedaction: false, showsSpotlight: false) == nil)
    #expect(StyleBarContent.content(showsStyle: true, tool: .crop, showsRedaction: true, showsSpotlight: true) == nil)
}

@Test func onlyAFillClearsToNone() {
    #expect(StyleBarColorRow.fill.clearsToNone)
    for row in [StyleBarColorRow.line, .text, .noteText, .paper, .counter] {
        #expect(!row.clearsToNone)
    }
}

@Test func theWidthsStepEvenlyThroughTheOldPresets() {
    let widths = EditorStyle.widths
    #expect(widths == widths.sorted())
    for preset in EditorStyle.presetWidths {
        #expect(widths.contains(preset))
    }
    #expect(widths.contains(EditorStyle.defaultWidth))
    for (thinner, thicker) in zip(widths, widths.dropFirst()) {
        let ratio = thicker / thinner
        #expect(ratio >= 1.2 && ratio <= 1.5, "\(thinner) to \(thicker)")
    }
    #expect(EditorStyle.step(from: 7.2, up: true) == 8)
    #expect(EditorStyle.step(from: 7.2, up: false) == 6)
    #expect(EditorStyle.step(from: 16, up: true) == nil)
    #expect(EditorStyle.step(from: 1, up: false) == nil)
    #expect(EditorStyle.clampedWidth(100) == 16)
}

@Test func theTextSizesAreTheOldPresetsAndStepEvenly() {
    let sizes = EditorStyle.widths.map { EditorStyle.shownSize(width: $0, sizing: .text) }
    // Small, Medium and Large were 12, 24 and 48 points.
    for size in [12.0, 24, 48] {
        #expect(sizes.contains(CGFloat(size)))
    }
    #expect(sizes.first == 6)
    #expect(sizes.last == 96)
    #expect(EditorStyle.shownSize(width: 4, sizing: .note) == 20)
    #expect(EditorStyle.shownSize(width: 4, sizing: .line) == 4)
}

@Test func theBarOffersEveryPresetColourWhiteIncluded() {
    #expect(StyleBarSwatches.colors == RGBA.presets)
    #expect(StyleBarSwatches.contains(RGBA(1, 1, 1)))
    #expect(!StyleBarSwatches.contains(RGBA(0.5, 0.2, 0.9)))
}

@Test func theBarKeepsClearOfTheControlsAtTheFoot() {
    // Below this mark fits the canvas, but would cover the zoom control and hint, so the bar goes to its right.
    let mark = CGRect(x: 300, y: 12, width: 120, height: 388)
    #expect(StyleBarPlacement.origin(bar: bar, mark: mark, in: canvas) == CGPoint(x: 230, y: 410))
    #expect(StyleBarPlacement.origin(bar: bar, mark: mark, in: canvas, bottom: 60) == CGPoint(x: 430, y: 190))
}

@Test func besideAMarkTheBarSlidesUpAboveTheControls() {
    let mark = CGRect(x: 100, y: 40, width: 200, height: 860)
    #expect(StyleBarPlacement.origin(bar: bar, mark: mark, in: canvas) == CGPoint(x: 310, y: 454))
    #expect(StyleBarPlacement.origin(bar: bar, mark: mark, in: canvas, bottom: 60) == CGPoint(x: 310, y: 408))
}

@Test func aTwoRowBarKeepsClearOfTheMarkAndTheFoot() {
    let tall = CGSize(width: 433, height: 66)
    let marks = [
        CGRect(x: 300, y: 200, width: 120, height: 80), CGRect(x: 300, y: 20, width: 120, height: 80),
        CGRect(x: 100, y: 10, width: 200, height: 480),
    ]
    for mark in marks {
        let frame = CGRect(origin: StyleBarPlacement.origin(bar: tall, mark: mark, in: canvas, bottom: 60), size: tall)
        #expect(!frame.intersects(mark), "\(mark)")
        #expect(CGRect(x: 12, y: 12, width: canvas.width - 24, height: canvas.height - 12 - 60).contains(frame), "\(mark)")
    }
}

@Test func aBarThatFitsOnlyInTheInsetsIsCentredSoAllOfItShows() {
    let wide = CGSize(width: 507, height: 66)
    let narrow = CGSize(width: 516, height: 500)
    #expect(StyleBarPlacement.origin(bar: wide, mark: nil, in: narrow).x == 4.5)
    let beside = StyleBarPlacement.origin(bar: wide, mark: CGRect(x: 0, y: 300, width: 40, height: 40), in: narrow)
    #expect(beside.x == 4.5)
}

@Test func aBarThatFitsOnlyInTheInsetsStillGoesAboveTheMark() {
    let wide = CGSize(width: 507, height: 66)
    let mark = CGRect(x: 200, y: 200, width: 100, height: 80)
    #expect(StyleBarPlacement.origin(bar: wide, mark: mark, in: CGSize(width: 516, height: 500)) == CGPoint(x: 4.5, y: 124))
}

@Test func theSizeBoxReadsANumberTypedEitherWay() {
    #expect(SizeInput.parse("12") == 12)
    #expect(SizeInput.parse(" 12,5 ") == 12.5)
    #expect(SizeInput.parse("10.5pt") == 10.5)
    #expect(SizeInput.parse("18 PT") == 18)
    #expect(SizeInput.parse("") == nil)
    #expect(SizeInput.parse("big") == nil)
    #expect(SizeInput.parse("-3") == nil)
    #expect(SizeInput.parse("0") == nil)
    #expect(SizeInput.parse("inf") == nil)
}
