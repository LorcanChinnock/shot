import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let red = RGBA.presets[0]

@Test func everyKindMapsToItsMarkType() throws {
    let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = AnnotationImage(try #require(context.makeImage()))
    let kinds: [(Annotation.Kind, String)] = [
        (.arrow(from: .zero, to: CGPoint(x: 10, y: 10)), "arrow"),
        (.line(from: .zero, to: CGPoint(x: 10, y: 10)), "line"),
        (.shape(.ellipse, rect: CGRect(x: 0, y: 0, width: 10, height: 10)), "ellipse"),
        (.highlight(CGRect(x: 0, y: 0, width: 10, height: 10)), "highlight"),
        (.pixelate(CGRect(x: 0, y: 0, width: 10, height: 10)), "pixelate"),
        (.blur(CGRect(x: 0, y: 0, width: 10, height: 10)), "blur"),
        (.spotlight(CGRect(x: 0, y: 0, width: 10, height: 10), style: SpotlightStyle()), "spotlight"),
        (.text("Hi", origin: .zero, fontSize: 20), "text"),
        (.counter(3, center: CGPoint(x: 5, y: 5)), "counter"),
        (.note("Fix", rect: CGRect(x: 0, y: 0, width: 100, height: 40)), "note"),
        (.freehand([.zero, CGPoint(x: 10, y: 4)]), "pen"),
        (.marker([.zero, CGPoint(x: 10, y: 4)]), "marker"),
        (.image(image, rect: CGRect(x: 0, y: 0, width: 10, height: 10)), "image"),
    ]
    let annotations = kinds.map { Annotation(kind: $0.0, color: red, lineWidth: 4) }
    let mapped = CaptureMark.mapping(annotations, canvas: CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(mapped.map(\.type) == kinds.map(\.1))
    #expect(mapped.map(\.id) == annotations.map(\.id.uuidString))
}

@Test func redactionsGiveOnlyWhereTheyAreAndHowStrong() {
    let blur = CaptureMark.mapping([Annotation(kind: .blur(CGRect(x: 40, y: 40, width: 300, height: 30), amount: 0.012), color: red, lineWidth: 4)], canvas: CGRect(x: 0, y: 0, width: 400, height: 400))[0]
    #expect(blur.amount.map { abs($0 - 0.012) < 1e-9 } == true)
    #expect(blur == CaptureMark(id: blur.id, type: "blur", rect: [40, 40, 300, 30], note: "redacted, content hidden", lineWidth: 4, amount: blur.amount))
}

@Test func marksCarryWhatTheEditorNeedsToRebuildThem() {
    var arrow = Annotation(kind: .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 10)), color: red, lineWidth: 6)
    arrow.bend = CGVector(dx: 0, dy: -8)
    var box = Annotation(kind: .shape(.rounded, rect: CGRect(x: 0, y: 0, width: 40, height: 20)), color: red, fill: RGBA.presets[2], lineWidth: 4)
    box.cornerRadius = 6
    let pen = Annotation(kind: .freehand([CGPoint(x: 20, y: 20), CGPoint(x: 30, y: 25)]), color: red, lineWidth: 4)
    let text = Annotation(kind: .text("Hi", origin: CGPoint(x: 20, y: 30), fontSize: 18), color: red, lineWidth: 4)
    // A half-size Retina save halves widths, sizes and points along with positions.
    let mapped = CaptureMark.mapping([arrow, box, pen, text], canvas: CGRect(x: 0, y: 0, width: 200, height: 200), scale: 0.5)
    #expect(mapped[0].lineWidth == 3)
    #expect(mapped[0].bend == [0, -4])
    #expect(mapped[1].fill == RGBA.presets[2].hex)
    #expect(mapped[1].cornerRadius == 3)
    #expect(mapped[2].points == [[10, 10], [15, 12.5]])
    #expect(mapped[3].fontSize == 9)
    #expect(mapped[3].rect?.prefix(2) == [10, 15])
}

@Test func marksSayWhatTheySayAndTheirColour() {
    let mapped = CaptureMark.mapping([
        Annotation(kind: .arrow(from: CGPoint(x: 410, y: 220), to: CGPoint(x: 612, y: 388)), color: red, lineWidth: 4),
        Annotation(kind: .counter(1, center: CGPoint(x: 300, y: 120)), color: RGBA(0.1, 0.45, 0.95), lineWidth: 4),
        Annotation(kind: .note("too tight here", rect: CGRect(x: 600, y: 450, width: 180, height: 32)), color: RGBA.presets[2], lineWidth: 4),
    ], canvas: CGRect(x: 0, y: 0, width: 2000, height: 2000))
    #expect(mapped[0].from == [410, 220])
    #expect(mapped[0].to == [612, 388])
    #expect(mapped[0].color == "red")
    #expect(mapped[0].hex == "#FF3B30")
    #expect(mapped[1].number == 1)
    #expect(mapped[1].center == [300, 120])
    // Not a preset, so it's named after the nearest one.
    #expect(mapped[1].color == "blue")
    #expect(mapped[2].text == "too tight here")
    #expect(mapped[2].rect?.first == 600)
}

@Test func coordinatesAreInTheSavedFilesPixels() {
    let arrow = Annotation(kind: .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 50)), color: red, lineWidth: 4)
    let box = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 10, y: 20, width: 30, height: 40)), color: red, lineWidth: 4)
    // Padding of 20 on the left and 10 on top moves everything right and down; a half-size Retina save halves it.
    let padded = CaptureMark.mapping([arrow, box], canvas: CGRect(x: -20, y: -10, width: 200, height: 200))
    #expect(padded[0].from == [20, 10])
    #expect(padded[0].to == [120, 60])
    #expect(padded[1].rect == [30, 30, 30, 40])
    let cropped = CaptureMark.mapping([box], canvas: CGRect(x: 10, y: 10, width: 50, height: 50), scale: 0.5)
    #expect(cropped[0].rect == [0, 5, 15, 20])
}

/// The acceptance check from #355: the record's pixels line up with the saved image's.
@Test func recordCoordinatesLandOnTheMarksInTheSavedImage() throws {
    let context = try #require(CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
    let base = try #require(context.makeImage())
    let annotations = [
        Annotation(kind: .shape(.rectangle, rect: CGRect(x: 60, y: 60, width: 40, height: 30)), color: red, lineWidth: 4),
        Annotation(kind: .arrow(from: CGPoint(x: 120, y: 120), to: CGPoint(x: 140, y: 140)), color: red, lineWidth: 4),
        Annotation(kind: .counter(1, center: CGPoint(x: 100, y: 100)), color: red, lineWidth: 4),
        Annotation(kind: .text("Hi", origin: CGPoint(x: 70, y: 110), fontSize: 14), color: red, lineWidth: 4),
    ]
    // Cropped to the middle, so every coordinate moves by 50 in the saved file.
    let canvas = CGRect(x: 50, y: 50, width: 100, height: 100)
    let saved = try #require(AnnotationRenderer.flatten(EditorDocument(base: base, annotations: annotations, canvasRect: canvas)))
    #expect(saved.width == 100 && saved.height == 100)
    let mapped = CaptureMark.mapping(annotations, canvas: canvas)
    func isRed(_ x: Double, _ y: Double) throws -> Bool {
        let p = try pixel(saved, CGFloat(x), CGFloat(y))
        return p[0] > 0.85 && p[1] < 0.45 && p[3] > 0.9
    }
    let box = try #require(mapped[0].rect)
    #expect(box == [10, 10, 40, 30])
    // The middle of the box's left edge is on its stroke; the middle of the box is not.
    #expect(try isRed(box[0], box[1] + box[3] / 2))
    #expect(try !isRed(box[0] + box[2] / 2, box[1] + box[3] / 2))
    let from = try #require(mapped[1].from), to = try #require(mapped[1].to)
    #expect(from == [70, 70] && to == [90, 90])
    #expect(try isRed((from[0] + to[0]) / 2, (from[1] + to[1]) / 2))
    let center = try #require(mapped[2].center)
    #expect(center == [50, 50])
    // Inside the counter's circle, clear of the white digit in its middle.
    #expect(try isRed(center[0] - annotations[2].counterRadius * 0.6, center[1]))
    let text = try #require(mapped[3].rect)
    #expect(text[0] >= 0 && text[1] >= 0 && text[0] + text[2] <= 100 && text[1] + text[3] <= 100)
}

@Test func annotationsCroppedOutAreLeftOut() {
    let inside = Annotation(kind: .counter(1, center: CGPoint(x: 50, y: 50)), color: red, lineWidth: 4)
    let outside = Annotation(kind: .counter(2, center: CGPoint(x: 500, y: 500)), color: red, lineWidth: 4)
    #expect(CaptureMark.mapping([inside, outside], canvas: CGRect(x: 0, y: 0, width: 100, height: 100)).map(\.number) == [1])
}

@Test func hiddenAnnotationsAreLeftOut() {
    var hidden = Annotation(kind: .counter(1, center: .zero), color: red, lineWidth: 4)
    hidden.isHidden = true
    let shown = Annotation(kind: .counter(2, center: .zero), color: red, lineWidth: 4)
    #expect(CaptureMark.mapping([hidden, shown], canvas: CGRect(x: 0, y: 0, width: 10, height: 10)).map(\.number) == [2])
}

@Test func everyPresetIsNamedAfterItself() {
    #expect(RGBA.presets.map(\.nearestPresetName) == RGBA.presetNames.map { $0.lowercased() })
}

/// Every mark type an agent or a saved version can give comes back as the annotation it was written from.
@Test func everyRebuildableKindRoundTripsThroughItsMark() throws {
    var arrow = Annotation(kind: .arrow(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 90, y: 60)), color: red, lineWidth: 6)
    arrow.bend = CGVector(dx: 3, dy: -8)
    var rounded = Annotation(kind: .shape(.rounded, rect: CGRect(x: 5, y: 5, width: 40, height: 20)), color: RGBA.presets[4], fill: RGBA.presets[2], lineWidth: 2)
    rounded.cornerRadius = 7
    let annotations = [
        arrow,
        Annotation(kind: .line(from: CGPoint(x: 1, y: 2), to: CGPoint(x: 3, y: 4)), color: red, lineWidth: 4),
        rounded,
        Annotation(kind: .shape(.star, rect: CGRect(x: 50, y: 50, width: 30, height: 30)), color: red, lineWidth: 4),
        Annotation(kind: .highlight(CGRect(x: 0, y: 0, width: 10, height: 5)), color: RGBA.presets[2], lineWidth: 4),
        Annotation(kind: .blur(CGRect(x: 40, y: 40, width: 30, height: 10), amount: 0.012), color: red, lineWidth: 4),
        Annotation(kind: .pixelate(CGRect(x: 40, y: 60, width: 30, height: 10)), color: red, lineWidth: 4),
        Annotation(kind: .text("too tight", origin: CGPoint(x: 20, y: 70), fontSize: 24), color: red, lineWidth: 4),
        Annotation(kind: .counter(3, center: CGPoint(x: 15, y: 15)), color: red, lineWidth: 4),
        Annotation(kind: .note("Fix this", rect: CGRect(x: 60, y: 10, width: 120, height: 40)), color: RGBA.presets[2], lineWidth: 4),
        Annotation(kind: .freehand([CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 14), CGPoint(x: 30, y: 12)]), color: red, lineWidth: 8),
        Annotation(kind: .marker([CGPoint(x: 10, y: 80), CGPoint(x: 60, y: 80)]), color: RGBA.presets[2], lineWidth: 4),
    ]
    // Cropped and padded at once, so the canvas offset has to come back off.
    let canvas = CGRect(x: -10, y: 4, width: 200, height: 120)
    let marks = CaptureMark.mapping(annotations, canvas: canvas)
    #expect(marks.count == annotations.count)
    for (annotation, mark) in zip(annotations, marks) {
        let rebuilt = try #require(Annotation(mark: mark, origin: canvas.origin))
        #expect(rebuilt.id == annotation.id)
        #expect(rebuilt.lineWidth == annotation.lineWidth)
        #expect(rebuilt.bend == annotation.bend)
        #expect(rebuilt.cornerRadius == annotation.cornerRadius)
        #expect(rebuilt.color.hex == annotation.color.hex)
        #expect(rebuilt.fill?.hex == annotation.fill?.hex)
        // Positions are rounded to a tenth of a pixel, which drawing can't show.
        #expect(abs(rebuilt.bounds.minX - annotation.bounds.minX) < 0.06 && abs(rebuilt.bounds.minY - annotation.bounds.minY) < 0.06)
        #expect(abs(rebuilt.bounds.width - annotation.bounds.width) < 0.11 && abs(rebuilt.bounds.height - annotation.bounds.height) < 0.11)
        #expect(CaptureMark.mapping([rebuilt], canvas: canvas) == [mark])
    }
    #expect(CaptureMark.rebuildExactly(annotations, canvas: canvas))
}

@Test func placedImagesSpotlightsStylesAndHiddenLayersAreNotRebuiltExactly() throws {
    let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let canvas = CGRect(x: 0, y: 0, width: 100, height: 100)
    let image = Annotation(kind: .image(AnnotationImage(try #require(context.makeImage())), rect: CGRect(x: 0, y: 0, width: 10, height: 10)), color: red, lineWidth: 4)
    let spotlight = Annotation(kind: .spotlight(CGRect(x: 0, y: 0, width: 10, height: 10), style: SpotlightStyle()), color: red, lineWidth: 4)
    var styled = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 0, y: 0, width: 10, height: 10)), color: red, lineWidth: 4)
    styled.style.shadow = ShadowPreset.allCases[1].shadow(scale: 1)
    var hidden = Annotation(kind: .counter(1, center: CGPoint(x: 5, y: 5)), color: red, lineWidth: 4)
    hidden.isHidden = true
    let outside = Annotation(kind: .counter(1, center: CGPoint(x: 500, y: 500)), color: red, lineWidth: 4)
    for annotation in [image, spotlight, styled, hidden, outside] {
        #expect(!CaptureMark.rebuildExactly([annotation], canvas: canvas))
    }
    #expect(Annotation(mark: CaptureMark(type: "image", rect: [0, 0, 10, 10])) == nil)
}

@Test func aMarkMissingWhatItsTypeNeedsGivesNothing() {
    #expect(Annotation(mark: CaptureMark(type: "arrow", from: [0, 0])) == nil)
    #expect(Annotation(mark: CaptureMark(type: "rectangle", rect: [0, 0, -5, 5])) == nil)
    #expect(Annotation(mark: CaptureMark(type: "pen")) == nil)
    #expect(Annotation(mark: CaptureMark(type: "text", rect: [0, 0, 1, 1])) == nil)
    #expect(Annotation(mark: CaptureMark(type: "squiggle", rect: [0, 0, 1, 1])) == nil)
    #expect(Annotation(mark: CaptureMark(type: "line", from: [0, .infinity], to: [1, 1])) == nil)
}

@Test func anAgentsBareMarkTakesTheEditorsDefaults() throws {
    let box = try #require(Annotation(mark: CaptureMark(type: "rectangle", rect: [10, 10, 50, 20], color: "Blue")))
    #expect(box.color == RGBA.presets[4])
    #expect(box.lineWidth == EditorStyle.widths[1])
    let text = try #require(Annotation(mark: CaptureMark(type: "text", rect: [5, 6, 0, 0], text: "Hi"), lineWidth: 8))
    #expect(text.kind == .text("Hi", origin: CGPoint(x: 5, y: 6), fontSize: 48))
    #expect(text.color == RGBA.presets[0])
    let counter = try #require(Annotation(mark: CaptureMark(type: "counter", center: [4, 4], hex: "#00FF00")))
    #expect(counter.kind == .counter(1, center: CGPoint(x: 4, y: 4)))
    #expect(counter.color.hex == "#00FF00")
}

@Test func onlyAnEditableRecordOfTheWholeCanvasReopensLive() throws {
    let marks = [CaptureMark(id: UUID().uuidString, type: "counter", center: [10, 10], number: 1, color: "red", hex: RGBA.presets[0].hex, lineWidth: 4)]
    func record(editable: Bool?, original: String? = "Shot.png", size: Int = 100, canvas: [Double]? = [20, 30, 100, 100]) -> CaptureRecord {
        CaptureRecord(original: original, kind: "image", created: Date(), size: .init(width: size, height: size), scale: 1, canvas: canvas, editable: editable, annotations: marks)
    }
    let layers = try #require(record(editable: true).editableLayers)
    #expect(layers.canvas == CGRect(x: 20, y: 30, width: 100, height: 100))
    // The mark is in the version's pixels, so the canvas offset puts it back on the original.
    #expect(layers.annotations.map(\.kind) == [.counter(1, center: CGPoint(x: 30, y: 40))])
    #expect(record(editable: nil).editableLayers == nil)
    #expect(record(editable: false).editableLayers == nil)
    #expect(record(editable: true, original: nil).editableLayers == nil)
    #expect(record(editable: true, size: 140).editableLayers == nil)
    #expect(record(editable: true, canvas: nil).editableLayers == nil)
}
