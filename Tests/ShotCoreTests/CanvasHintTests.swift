import CoreGraphics
import Testing
@testable import ShotCore

private func mark(_ kind: Annotation.Kind, locked: Bool = false) -> Annotation {
    var annotation = Annotation(kind: kind, color: RGBA(1, 0, 0), lineWidth: 4)
    annotation.isLocked = locked
    return annotation
}

private let arrow = mark(.arrow(from: .zero, to: CGPoint(x: 100, y: 60)))

@Test func aSelectedArrowOffersDeleteAndTheSnap() throws {
    let hint = try #require(CanvasHint.hint(tool: .arrow, selection: [arrow], isTyping: false))
    #expect(hint.lead == "Arrow selected")
    #expect(hint.parts == [CanvasHint.Part(.delete, "delete"), CanvasHint.Part(.shift, "snap 45°")])
}

@Test func aSelectedMarkSaysWhatShiftDoesToItsHandles() {
    let image = mark(.image(AnnotationImage(solidImage(width: 4, height: 4)), rect: CGRect(x: 0, y: 0, width: 40, height: 40)))
    #expect(CanvasHint.hint(tool: .select, selection: [image], isTyping: false)?.parts.last == CanvasHint.Part(.shift, "resize freely"))
    let box = mark(.shape(.rectangle, rect: CGRect(x: 0, y: 0, width: 40, height: 30)))
    #expect(CanvasHint.hint(tool: .select, selection: [box], isTyping: false)?.parts.last == CanvasHint.Part(.shift, "keep proportions"))
    let step = mark(.counter(1, center: .zero))
    #expect(CanvasHint.hint(tool: .counter, selection: [step], isTyping: false)?.parts.last == CanvasHint.Part(.escape, "deselect"))
}

@Test func aLockedMarkPointsToLayers() throws {
    let hint = try #require(CanvasHint.hint(tool: .select, selection: [mark(.arrow(from: .zero, to: CGPoint(x: 9, y: 9)), locked: true)], isTyping: false))
    #expect(hint.lead == "Arrow locked")
    #expect(hint.parts == [CanvasHint.Part(nil, "unlock it in Layers")])
}

@Test func severalMarksCountAndOfferDelete() throws {
    let hint = try #require(CanvasHint.hint(tool: .select, selection: [arrow, arrow], isTyping: false))
    #expect(hint.lead == "2 selected")
    #expect(hint.parts.first == CanvasHint.Part(.delete, "delete"))
}

@Test func typingComesBeforeTheSelection() {
    #expect(CanvasHint.hint(tool: .text, selection: [arrow], isTyping: true)?.lead == "Typing")
}

@Test func cropModeHasNoHintSinceTheCropBarNamesItsKeys() {
    #expect(CanvasHint.hint(tool: .crop, selection: [arrow], isTyping: false) == nil)
    #expect(CanvasHint.hint(tool: .crop, selection: [], isTyping: false) == nil)
}

@Test func withNothingSelectedTheHintSaysWhatTheToolDoes() {
    #expect(CanvasHint.hint(tool: .arrow, selection: [], isTyping: false) == CanvasHint("Drag to draw an arrow", [CanvasHint.Part(.shift, "snap 45°")]))
    #expect(CanvasHint.hint(tool: .select, selection: [], isTyping: false)?.parts.isEmpty == true)
    for tool in EditorTool.allCases where tool != .crop {
        #expect(CanvasHint.hint(tool: tool, selection: [], isTyping: false)?.lead.isEmpty == false)
    }
}

@Test func voiceOverReadsTheKeysByName() throws {
    let hint = try #require(CanvasHint.hint(tool: .arrow, selection: [arrow], isTyping: false))
    #expect(hint.spoken == "Arrow selected. Delete: delete. Shift: snap 45°")
    #expect(CanvasHint.hint(tool: .select, selection: [mark(.line(from: .zero, to: CGPoint(x: 4, y: 4)), locked: true)], isTyping: false)?.spoken == "Line locked. unlock it in Layers")
}

@Test func theZoomShowsAsAWholePercentage() {
    #expect(ZoomControl.percent(0.864) == 86)
    #expect(ZoomControl.percent(1) == 100)
    #expect(ZoomControl.percent(0.125) == 13)
}

@Test func plusAndMinusStopAtTheEndsOfTheSteps() {
    #expect(ZoomControl.canZoomIn(1))
    #expect(!ZoomControl.canZoomIn(8))
    #expect(ZoomControl.canZoomOut(1))
    #expect(!ZoomControl.canZoomOut(0.1))
    // A fit smaller than the smallest step has nowhere further out to go.
    #expect(!ZoomControl.canZoomOut(0.05))
}

@Test func hintShowsOnlyWhileFreshAndNotDragging() {
    #expect(CanvasHint.isShown(isFresh: true, isDragging: false, voiceOver: false))
    #expect(!CanvasHint.isShown(isFresh: false, isDragging: false, voiceOver: false))
    #expect(!CanvasHint.isShown(isFresh: true, isDragging: true, voiceOver: false))
}

@Test func hintStaysForVoiceOver() {
    #expect(CanvasHint.isShown(isFresh: false, isDragging: true, voiceOver: true))
}
