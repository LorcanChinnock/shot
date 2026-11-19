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

@Test func onlyTheMarksSharingTheMarkStyleTakeAGlow() {
    #expect(arrow().takesGlow)
    #expect(Annotation(kind: .line(from: .zero, to: CGPoint(x: 5, y: 5)), color: blue, lineWidth: 2).takesGlow)
    #expect(Annotation(kind: .shape(.rectangle, rect: CGRect(x: 0, y: 0, width: 10, height: 10)), color: blue, lineWidth: 2).takesGlow)
    #expect(Annotation(kind: .freehand([.zero, CGPoint(x: 4, y: 4)]), color: blue, lineWidth: 2).takesGlow)
    #expect(!Annotation(kind: .highlight(CGRect(x: 0, y: 0, width: 10, height: 10)), color: blue, lineWidth: 2).takesGlow)
    // Every tool whose marks start with the shared mark style can turn its glow off.
    #expect(EditorTool.allCases.filter(\.takesGlow) == [.arrow, .line, .shape, .pen, .counter])
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

@Test func theStyleBarShowsGlowForMarksOnly() {
    #expect(palette(tool: .arrow).glow == false)
    #expect(palette(tool: .arrow).controlRows[0] == [.width, .lineDash, .glow])
    #expect(palette(tool: .shape).controlRows[0] == [.width, .glow])
    #expect(palette(tool: .pen).controlRows[0] == [.width, .penLine, .glow])
    #expect(palette(tool: .highlight).glow == nil)
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

@Test func aDraftArrowAndPenStrokeGlowAndAHighlightDoesNot() throws {
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
    #expect(stroke.style.shadow == glow)
    let highlight = try #require(AnnotationDraft.annotation(
        tool: .highlight, from: .zero, to: CGPoint(x: 50, y: 20), previous: nil, constrain: false, fromCenter: false, minDistance: 1, style: style
    ))
    #expect(highlight.style.shadow == nil)
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

@Test func theSwitchAndTheStylePanelShareOneGlow() {
    // The Style panel's Glow, given to a mark, is what the switch shows for the next one.
    var style = EditorStyle(objectStyles: [.mark: ObjectStyle(shadow: ShadowPreset.glow.shadow(scale: 1))])
    #expect(style.glow)
    #expect(palette(tool: .arrow, style: style).glow == true)
    // Turning the switch off takes the glow out of the style new marks start with, so the next arrow doesn't glow.
    style.glow = false
    #expect(style.objectStyles[.mark] == nil)
    #expect(style.editorObjectStyle(for: .mark, scale: 1).shadow == nil)
    // Turning it on gives new marks the Glow shadow, in points.
    style.glow = true
    #expect(style.objectStyles[.mark]?.shadow == ShadowPreset.glow.shadow(scale: 1))
}

@Test func turningTheGlowOffKeepsAMarksBorder() {
    let border = ObjectStyle(shadow: ShadowPreset.glow.shadow(scale: 1), border: Border(kind: .outline, lineWidth: 2, color: RGBA(0, 0, 0)))
    var style = EditorStyle(objectStyles: [.mark: border])
    style.glow = false
    #expect(style.objectStyles[.mark]?.shadow == nil)
    #expect(style.objectStyles[.mark]?.border == border.border)
}
