import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let blue = RGBA(0, 0, 1)

private func arrow() -> Annotation {
    Annotation(kind: .arrow(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 190, y: 30)), color: blue, lineWidth: 6)
}

private func palette(tool: EditorTool?, selection: Annotation? = nil, style: EditorStyle = EditorStyle(), scale: CGFloat = 2) -> AnnotationPalette {
    AnnotationPalette(
        style: style, editingText: nil, editingTextIsNew: false, selection: selection, tool: tool, scale: scale, imageLength: 200,
        sharedSpotlight: nil
    )
}

@Test func onlyArrowsLinesAndShapesTakeAGlow() {
    #expect(arrow().takesGlow)
    #expect(Annotation(kind: .line(from: .zero, to: CGPoint(x: 5, y: 5)), color: blue, lineWidth: 2).takesGlow)
    #expect(Annotation(kind: .shape(.rectangle, rect: CGRect(x: 0, y: 0, width: 10, height: 10)), color: blue, lineWidth: 2).takesGlow)
    #expect(!Annotation(kind: .freehand([.zero, CGPoint(x: 4, y: 4)]), color: blue, lineWidth: 2).takesGlow)
    #expect(EditorTool.allCases.filter(\.takesGlow) == [.arrow, .line, .shape])
}

@Test func aGlowIsTheStylePanelsGlowShadow() {
    var mark = arrow()
    #expect(!mark.glows)
    mark.setGlow(true, scale: 2)
    #expect(mark.glows)
    #expect(mark.style.shadow == ShadowPreset.glow.shadow(scale: 2))
    mark.setGlow(false, scale: 2)
    #expect(mark.style.shadow == nil)
}

@Test func puttingTheGlowOutKeepsAnotherShadow() {
    var mark = arrow()
    mark.style.shadow = ShadowPreset.soft.shadow(scale: 1)
    #expect(!mark.glows)
    mark.setGlow(false, scale: 1)
    #expect(mark.style.shadow == ShadowPreset.soft.shadow(scale: 1))
}

@Test func aGlowSurvivesSavingAndOldMarksOpenWithout() throws {
    var mark = arrow()
    mark.setGlow(true, scale: 1)
    let decoded = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(mark))
    #expect(decoded.glows)
    #expect(decoded.style.shadow == mark.style.shadow)

    // A mark saved before it had a style, with no objectStyle key at all.
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(arrow())) as? [String: Any])
    json.removeValue(forKey: "objectStyle")
    let old = try JSONDecoder().decode(Annotation.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(!old.glows)
}

@Test func theStyleBarShowsGlowForArrowsLinesAndShapesOnly() {
    #expect(palette(tool: .arrow).glow == false)
    #expect(palette(tool: .arrow).controlRows[0] == [.width, .lineDash, .glow])
    #expect(palette(tool: .shape).controlRows[0] == [.width, .glow])
    #expect(palette(tool: .pen).glow == nil)
    #expect(!palette(tool: .pen).controlRows.joined().contains(.glow))
    #expect(palette(tool: .text).glow == nil)
}

@Test func switchingGlowOnLightsTheMarkJustDrawnAndTheNextOne() {
    var bar = palette(tool: .arrow, selection: arrow())
    bar.setGlow(true)
    #expect(bar.selection?.glows == true)
    #expect(bar.selection?.style.shadow == ShadowPreset.glow.shadow(scale: 2))
    #expect(bar.style.glow)
    #expect(bar.glow == true)
}

@Test func theSelectToolGlowsOnlyTheSelection() {
    var bar = palette(tool: .select, selection: arrow())
    bar.setGlow(true)
    #expect(bar.selection?.glows == true)
    #expect(!bar.style.glow)
}

@Test func resetStylePutsTheGlowOut() {
    var mark = arrow()
    mark.setGlow(true, scale: 2)
    var bar = palette(tool: .arrow, selection: mark, style: EditorStyle(glow: true))
    #expect(bar.canReset)
    bar.reset()
    #expect(bar.selection?.glows == false)
    #expect(!bar.style.glow)
}

@Test func pickingAGlowingLayerTurnsGlowOnForTheNextMark() {
    var mark = arrow()
    mark.setGlow(true, scale: 2)
    var bar = palette(tool: .arrow, selection: mark)
    bar.takeStyleOfSelection()
    #expect(bar.style.glow)
}

@Test func aDraftArrowGlowsAndAPenStrokeDoesNot() throws {
    let glow = ShadowPreset.glow.shadow(scale: 1)
    let style = AnnotationDraft.Style(
        color: blue, fill: nil, noteColor: blue, lineWidth: 4, shape: .rectangle, redaction: .blur, redactionAmount: Redaction.defaultAmount,
        spotlight: SpotlightStyle(), alignment: .left, noteAlignment: .center, verticalAlignment: .middle, glow: glow
    )
    let drawn = try #require(AnnotationDraft.annotation(
        tool: .arrow, from: .zero, to: CGPoint(x: 50, y: 0), previous: nil, constrain: false, fromCenter: false, minDistance: 1, style: style
    ))
    #expect(drawn.style.shadow == glow)
    let stroke = try #require(AnnotationDraft.annotation(
        tool: .pen, from: .zero, to: CGPoint(x: 50, y: 0), previous: nil, constrain: false, fromCenter: false, minDistance: 1, style: style
    ))
    #expect(stroke.style.shadow == nil)
}

/// The blue level 6 px below a 6 px blue arrow drawn over a red image, from 0 to 255.
private func blueBelowTheStroke(of mark: Annotation) throws -> UInt8 {
    let doc = EditorDocument(base: solidImage(width: 200, height: 60), annotations: [mark])
    let image = try #require(AnnotationRenderer.flatten(doc))
    return try pixelBytes(image, 100, 39)[2]
}

@Test func aGlowingMarkPaintsItsColourOutsideTheStroke() throws {
    var glowing = arrow()
    glowing.setGlow(true, scale: 1)
    #expect(try blueBelowTheStroke(of: arrow()) == 0)
    #expect(try blueBelowTheStroke(of: glowing) > 10)
}
