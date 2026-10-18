import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let red = RGBA(1, 0, 0)
private let blue = RGBA(0, 0, 1)
private let arrow = Annotation(kind: .arrow(from: .zero, to: CGPoint(x: 100, y: 0)), color: red, lineWidth: 8)
private let box = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 0, y: 0, width: 50, height: 50)), color: red, lineWidth: 4)
private let note = Annotation(kind: .note("Hi", rect: CGRect(x: 0, y: 0, width: 80, height: 40)), color: RGBA.presets[2], lineWidth: 4)

private func palette(tool: EditorTool? = .arrow, selection: Annotation? = nil, editing: Annotation? = nil, isNew: Bool = false, scale: CGFloat = 2) -> AnnotationPalette {
    AnnotationPalette(style: EditorStyle(tool: tool ?? .arrow), editingText: editing, editingTextIsNew: isNew, selection: selection, tool: tool, scale: scale, imageLength: 1000, sharedSpotlight: nil)
}

@Test func eachToolAndSelectionUsesItsColourSlot() {
    #expect(palette(tool: .note).customSlot(forFill: false) == .note)
    #expect(palette(tool: .highlight).customSlot(forFill: false) == .highlight)
    #expect(palette(tool: .pen).customSlot(forFill: false) == .stroke)
    #expect(palette(tool: nil).customSlot(forFill: false) == .stroke)
    #expect(palette(tool: .highlight, selection: arrow).customSlot(forFill: false) == .stroke)
    #expect(palette(tool: .arrow, editing: note).customSlot(forFill: false) == .note)
    #expect(palette(tool: .shape).customSlot(forFill: true) == .fill)

    var picked = palette(tool: .note)
    picked.pickCustom(blue, forFill: false)
    #expect(picked.style.customColors == [.note: blue])
    #expect(picked.style.noteColor == blue)
    #expect(picked.lastCustom(forFill: false) == blue)
    #expect(picked.lastCustom(forFill: true) == nil)
}

@Test func theToolbarStylesTheNextAnnotationUnlessOnePickedWithSelectIsSelected() {
    // Nothing selected: only the next annotation changes.
    var idle = palette(tool: .arrow)
    idle.setColor(blue)
    #expect(idle.style.color == blue)
    #expect(idle.selection == nil)

    // The annotation just drawn is still selected: it and the next one change.
    var drawn = palette(tool: .arrow, selection: arrow)
    drawn.setColor(blue)
    #expect(drawn.selection?.color == blue)
    #expect(drawn.style.color == blue)

    // One picked with the select tool restyles alone.
    var picked = palette(tool: .select, selection: arrow)
    picked.setColor(blue)
    picked.setLineWidthIndex(0)
    #expect(picked.selection?.color == blue)
    #expect(picked.selection?.lineWidth == 4)
    #expect(picked.style == EditorStyle(tool: .select))

    // Notes and the highlighter keep their own colour.
    var highlighter = palette(tool: .highlight)
    highlighter.setColor(blue)
    #expect(highlighter.style.highlightColor == blue)
    #expect(highlighter.style.color == EditorStyle().color)
}

@Test func textBeingTypedTakesTheStyleAndANewOneAlsoSetsTheNext() {
    var existing = palette(tool: .select, selection: arrow, editing: note)
    existing.setColor(blue)
    existing.setAlignment(.right)
    #expect(existing.editingText?.color == blue)
    #expect(existing.editingText?.alignment == .right)
    #expect(existing.selection == arrow)
    #expect(existing.style == EditorStyle(tool: .select))

    var new = palette(tool: .note, editing: note, isNew: true)
    new.setColor(blue)
    new.setAlignment(.right)
    new.setLineWidthIndex(2)
    #expect(new.style.noteColor == blue)
    #expect(new.style.color == EditorStyle().color)
    #expect(new.style.alignment == .right)
    #expect(new.style.widthIndex == 2)
}

@Test func eachOptionRowShowsForItsToolOrSelection() {
    #expect(palette(tool: .shape).shape == .rectangle)
    #expect(palette(tool: .arrow).shape == nil)
    #expect(palette(tool: .arrow, selection: box).shape == .rectangle)
    #expect(palette(tool: .shape, selection: arrow).shape == nil)
    #expect(palette(tool: .shape).showsFill)
    #expect(!palette(tool: .shape, selection: arrow).showsFill)
    #expect(palette(tool: .redact).redaction == .blur)
    #expect(palette(tool: .shape).redaction == nil)
    #expect(palette(tool: .spotlight).spotlight == SpotlightStyle())
    #expect(palette(tool: .arrow).spotlight == nil)
    #expect(palette(tool: .note).alignment == .left)
    #expect(palette(tool: .arrow).alignment == nil)
    #expect(palette(tool: .arrow, selection: note).alignment == .left)
    #expect(palette(tool: .text).sizesText)
    #expect(!palette(tool: .arrow).sizesText)
    #expect(palette(tool: .spotlight, editing: note).showsStyle)
    #expect(!palette(tool: .spotlight).showsStyle)
    #expect(!palette(tool: nil).showsStyle)
}

@Test func theWidthShownIsTheNearestToTheSelections() {
    // Widths are 2, 4 and 8 points, at 2 pixels per point.
    #expect(palette(selection: arrow).lineWidthIndex == 1)
    var odd = arrow
    odd.lineWidth = 13
    #expect(palette(selection: odd).lineWidthIndex == 2)
    odd.lineWidth = 1
    #expect(palette(selection: odd).lineWidthIndex == 0)
    #expect(palette().lineWidthIndex == EditorStyle().widthIndex)
}

@Test func theNextSpotlightTakesTheSharedLook() {
    var shared = palette(tool: .spotlight)
    shared.style.spotlight = SpotlightStyle(shape: .ellipse, effect: .darken, strength: 0.3, softEdge: 0.5)
    shared.sharedSpotlight = SpotlightStyle(shape: .rectangle, effect: .blur, strength: 0.7)
    #expect(shared.nextSpotlightStyle == SpotlightStyle(shape: .ellipse, effect: .blur, strength: 0.7, softEdge: 0.5))
}
