import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let blue = RGBA(0, 0.48, 1)
private let across = [CGPoint(x: 40, y: 50), CGPoint(x: 100, y: 52), CGPoint(x: 160, y: 50)]

private func marker(_ points: [CGPoint], lineWidth: CGFloat = 4) -> Annotation {
    Annotation(kind: .marker(points), color: blue, lineWidth: lineWidth)
}

private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [CGFloat] {
    let data = try #require(image.dataProvider?.data as Data?)
    let offset = y * image.bytesPerRow + x * 4
    return data[offset..<offset + 4].map { CGFloat($0) / 255 }
}

@Test func theHighlighterIsKeyedMAndTakesAColourAndWidth() {
    #expect(EditorTool.highlight.key == "m")
    #expect(EditorTool.highlight.isStyled)
    #expect(marker(across).isStyled)
}

@Test func theHighlighterKeepsItsOwnColour() {
    let style = EditorStyle()
    #expect(style.highlightColor == RGBA.presets[2])
    #expect(style.highlightColor != style.color)
}

@Test func theMiddleWidthIsAboutALineOfTextTall() {
    #expect(marker(across, lineWidth: EditorStyle.widths[1]).markerWidth == 18)
}

@Test func aMarkerMultipliesIntoTheImageWithFlatEnds() throws {
    let doc = EditorDocument(base: solidImage(width: 200, height: 100), annotations: [marker([CGPoint(x: 40, y: 50), CGPoint(x: 160, y: 50)])])
    let image = try #require(AnnotationRenderer.flatten(doc))
    // Blue multiplied into red leaves a darker red with no blue; painted over it would show blue.
    let inked = try pixel(image, 100, 50 + 7)
    #expect(inked[0] < 0.6 && inked[1] < 0.05 && inked[2] < 0.05, "multiplied, got \(inked)")
    #expect(try pixel(image, 100, 50 + 12) == [1, 0, 0, 1], "past the marker's width")
    #expect(try pixel(image, 35, 50) == [1, 0, 0, 1], "past its flat end")
}

@Test func aMarkerIsHitAnywhereOnItsInk() {
    let m = marker(across)
    #expect(m.hitTest(CGPoint(x: 100, y: 52 + 8), tolerance: 0))
    #expect(!m.hitTest(CGPoint(x: 100, y: 52 + 14), tolerance: 0))
    #expect(m.paintedBounds.contains(CGRect(x: 40, y: 50 - 9, width: 120, height: 18)))
}

@Test func aMarkerMovesResizesAndReveals() {
    var m = marker(across)
    m.offset(by: CGVector(dx: 10, dy: 5))
    #expect(m.kind == .marker(across.map { CGPoint(x: $0.x + 10, y: $0.y + 5) }))
    var wide = marker(across)
    wide.resize(.right, to: CGPoint(x: 280, y: 51))
    #expect(wide.kind == .marker([CGPoint(x: 40, y: 50), CGPoint(x: 160, y: 52), CGPoint(x: 280, y: 50)]))
    guard case let .marker(half) = marker(across).revealed(0.5).kind else {
        Issue.record("not a marker")
        return
    }
    #expect(half.first == across.first && (half.last?.x ?? 0) < 105)
}

@Test func anOldHighlightBoxStillOpens() throws {
    // How earlier versions saved a highlight in a video project.
    let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":{"highlight":{"_0":[[20,20],[100,40]]}},"color":{"r":1,"g":0.23,"b":0.19,"a":1},"lineWidth":4}"#
    let old = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
    #expect(old.kind == .highlight(CGRect(x: 20, y: 20, width: 100, height: 40)))
}
