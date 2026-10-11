import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let red = RGBA.presets[0]

@Test func everyKindMapsToItsSidecarType() throws {
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
    let mapped = SidecarAnnotation.mapping(annotations, canvas: CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(mapped.map(\.type) == kinds.map(\.1))
    #expect(mapped.map(\.id) == annotations.map(\.id.uuidString))
}

@Test func redactionsGiveOnlyWhereTheyAre() {
    let blur = SidecarAnnotation.mapping([Annotation(kind: .blur(CGRect(x: 40, y: 40, width: 300, height: 30)), color: red, lineWidth: 4)], canvas: CGRect(x: 0, y: 0, width: 400, height: 400))[0]
    #expect(blur == SidecarAnnotation(id: blur.id, type: "blur", rect: [40, 40, 300, 30], note: "redacted, content hidden"))
}

@Test func marksSayWhatTheySayAndTheirColour() {
    let mapped = SidecarAnnotation.mapping([
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
    let padded = SidecarAnnotation.mapping([arrow, box], canvas: CGRect(x: -20, y: -10, width: 200, height: 200))
    #expect(padded[0].from == [20, 10])
    #expect(padded[0].to == [120, 60])
    #expect(padded[1].rect == [30, 30, 30, 40])
    let cropped = SidecarAnnotation.mapping([box], canvas: CGRect(x: 10, y: 10, width: 50, height: 50), scale: 0.5)
    #expect(cropped[0].rect == [0, 5, 15, 20])
}

@Test func hiddenAnnotationsAreLeftOut() {
    var hidden = Annotation(kind: .counter(1, center: .zero), color: red, lineWidth: 4)
    hidden.isHidden = true
    let shown = Annotation(kind: .counter(2, center: .zero), color: red, lineWidth: 4)
    #expect(SidecarAnnotation.mapping([hidden, shown], canvas: CGRect(x: 0, y: 0, width: 10, height: 10)).map(\.number) == [2])
}

@Test func everyPresetIsNamedAfterItself() {
    #expect(RGBA.presets.map(\.nearestPresetName) == RGBA.presetNames.map { $0.lowercased() })
}
