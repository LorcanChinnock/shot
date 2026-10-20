import CoreGraphics
import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

// The goldens ShotCoreLinuxTests' CairoGoldenTests draws through CairoCanvas and compares: documents of every kind of
// annotation over `base.png`, drawn through CGCanvas into `<name>.png`. They're all in Tests/Fixtures/canvas, the documents in `goldens.json`.
//
// Run with SHOT_WRITE_GOLDENS=1 to write them again after a rendering change, and check the new PNGs by eye. Otherwise
// this checks they're still what CGCanvas draws.

private let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/canvas")

/// A document to draw over the base, as `goldens.json` keeps it.
private struct Golden: Codable {
    var name: String
    var annotations: [Annotation]
    var canvasRect: CGRect?
    var background: RGBA?
}

/// 160 × 120: a gradient, opaque, with a darker band across the middle, so images and spotlights have something to show.
private func base() throws -> Bitmap {
    var pixels = Data()
    for y in 0..<120 {
        for x in 0..<160 {
            let band = (50..<70).contains(y) ? 0.5 : 1
            pixels += [Double(x) / 159 * band, Double(y) / 119 * band, 0.6 * band].map { UInt8(($0 * 255).rounded()) } + [255]
        }
    }
    return try #require(Bitmap(width: 160, height: 120, pixels: pixels))
}

/// A 12 × 8 picture to place: four coloured quarters, the bottom right half clear.
private func picture() throws -> CGImage {
    var pixels = Data()
    for y in 0..<8 {
        for x in 0..<12 {
            switch (x < 6, y < 4) {
            case (true, true): pixels += [230, 40, 40, 255]
            case (false, true): pixels += [40, 200, 60, 255]
            case (true, false): pixels += [40, 60, 220, 255]
            case (false, false): pixels += [64, 64, 64, 128]
            }
        }
    }
    return try #require(Bitmap(width: 12, height: 8, pixels: pixels)?.cgImage)
}

private func goldens() throws -> [Golden] {
    let red = RGBA(0.9, 0.1, 0.1), blue = RGBA(0.1, 0.3, 0.9), green = RGBA(0.1, 0.7, 0.2), white = RGBA(1, 1, 1)
    func annotation(_ kind: Annotation.Kind, _ color: RGBA, width: CGFloat = 3, fill: RGBA? = nil, id: Int) -> Annotation {
        Annotation(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!, kind: kind, color: color, fill: fill, lineWidth: width)
    }
    var curvedArrow = annotation(.arrow(from: CGPoint(x: 20, y: 60), to: CGPoint(x: 140, y: 60)), blue, id: 2)
    curvedArrow.bend = CGVector(dx: 0, dy: -25)
    var curvedLine = annotation(.line(from: CGPoint(x: 20, y: 110), to: CGPoint(x: 140, y: 110)), red, width: 2, id: 4)
    curvedLine.bend = CGVector(dx: 0, dy: 12)
    let lines = [
        annotation(.arrow(from: CGPoint(x: 15, y: 15), to: CGPoint(x: 145, y: 35)), red, width: 4, id: 1),
        curvedArrow,
        annotation(.line(from: CGPoint(x: 20, y: 80), to: CGPoint(x: 140, y: 95)), green, width: 2, id: 3),
        curvedLine,
        annotation(.freehand([CGPoint(x: 30, y: 40), CGPoint(x: 50, y: 30), CGPoint(x: 70, y: 48), CGPoint(x: 90, y: 32), CGPoint(x: 110, y: 46)]), white, id: 5),
        annotation(.marker([CGPoint(x: 20, y: 70), CGPoint(x: 80, y: 75), CGPoint(x: 140, y: 68)]), RGBA(1, 0.85, 0), id: 6),
    ]

    var rounded = annotation(.shape(.rectangle, rect: CGRect(x: 62, y: 10, width: 40, height: 30)), blue, fill: RGBA(1, 1, 1, 0.6), id: 12)
    rounded.cornerRadius = 8
    let shapes = [
        annotation(.shape(.rectangle, rect: CGRect(x: 10, y: 10, width: 40, height: 30)), red, id: 11),
        rounded,
        annotation(.shape(.ellipse, rect: CGRect(x: 112, y: 8, width: 40, height: 34)), green, width: 4, fill: RGBA(0.1, 0.7, 0.2, 0.4), id: 13),
        annotation(.shape(.triangle, rect: CGRect(x: 10, y: 74, width: 40, height: 36)), white, width: 2, id: 14),
        annotation(.shape(.diamond, rect: CGRect(x: 62, y: 74, width: 40, height: 36)), red, width: 3, fill: blue, id: 15),
        annotation(.shape(.star, rect: CGRect(x: 112, y: 72, width: 40, height: 40)), RGBA(1, 0.85, 0), width: 2, id: 16),
        annotation(.highlight(CGRect(x: 20, y: 48, width: 120, height: 14)), RGBA(1, 0.92, 0.2), id: 17),
    ]

    func shadowed(_ annotation: Annotation, elevation: CGFloat, opacity: CGFloat = 0.4) -> Annotation {
        var annotation = annotation
        annotation.style = ObjectStyle(shadow: Shadow(elevation: elevation, opacity: opacity))
        return annotation
    }
    let shadows = [
        shadowed(annotation(.shape(.rectangle, rect: CGRect(x: 14, y: 14, width: 50, height: 36)), white, fill: white, id: 21), elevation: 8),
        shadowed(annotation(.shape(.ellipse, rect: CGRect(x: 90, y: 12, width: 50, height: 40)), red, width: 4, id: 22), elevation: 2, opacity: 0.6),
        shadowed(annotation(.arrow(from: CGPoint(x: 20, y: 95), to: CGPoint(x: 140, y: 80)), blue, width: 5, id: 23), elevation: 16),
    ]

    let placed = AnnotationImage(try picture(), id: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!)
    func image(_ rect: CGRect, radius: CGFloat?, style: ObjectStyle, id: Int) -> Annotation {
        var image = annotation(.image(placed, rect: rect), RGBA(0, 0, 0), width: 0, id: id)
        image.cornerRadius = radius
        image.style = style
        return image
    }
    let images = [
        image(CGRect(x: 12, y: 12, width: 60, height: 40), radius: 6, style: ObjectStyle(shadow: Shadow(elevation: 8, opacity: 0.5), border: Border(kind: .solid, lineWidth: 4, color: white)), id: 31),
        image(CGRect(x: 92, y: 14, width: 48, height: 32), radius: nil, style: ObjectStyle(border: .hairline), id: 32),
        image(CGRect(x: 30, y: 70, width: 100, height: 40), radius: 12, style: ObjectStyle(), id: 33),
    ]

    var ellipseSpot = annotation(.spotlight(CGRect(x: 96, y: 60, width: 50, height: 40), style: SpotlightStyle(shape: .ellipse, strength: 0.7)), RGBA(0, 0, 0), id: 42)
    ellipseSpot.cornerRadius = nil
    var roundedSpot = annotation(.spotlight(CGRect(x: 14, y: 14, width: 60, height: 40), style: SpotlightStyle(strength: 0.7)), RGBA(0, 0, 0), id: 41)
    roundedSpot.cornerRadius = 10
    let spotlights = [roundedSpot, ellipseSpot]

    let padded = [
        annotation(.arrow(from: CGPoint(x: 80, y: 60), to: CGPoint(x: 190, y: 20)), red, width: 4, id: 51),
        shadowed(annotation(.shape(.rectangle, rect: CGRect(x: -20, y: 90, width: 50, height: 40)), blue, width: 3, fill: white, id: 52), elevation: 4),
    ]

    func text(_ string: String, at origin: CGPoint, size: CGFloat, _ color: RGBA, align: TextAlign = .left, outline: RGBA? = nil, id: Int) -> Annotation {
        var text = annotation(.text(string, origin: origin, fontSize: size), color, id: id)
        text.alignment = align
        if let outline {
            text.style = ObjectStyle(border: Border(kind: .outline, lineWidth: 3, color: outline))
        }
        return text
    }
    let texts = [
        text("Shot", at: CGPoint(x: 10, y: 8), size: 24, red, id: 61),
        text("Left\nand more", at: CGPoint(x: 10, y: 44), size: 14, white, id: 62),
        text("Right\naligned", at: CGPoint(x: 90, y: 44), size: 14, blue, align: .right, id: 63),
        text("centred", at: CGPoint(x: 40, y: 88), size: 18, RGBA(1, 0.85, 0), align: .center, id: 64),
    ]
    let outlined = [
        text("Look", at: CGPoint(x: 12, y: 10), size: 32, white, outline: RGBA(0, 0, 0), id: 71),
        text("here!", at: CGPoint(x: 40, y: 64), size: 28, RGBA(1, 0.85, 0), outline: red, id: 72),
    ]

    var middleNote = annotation(.note("Middle", rect: CGRect(x: 100, y: 8, width: 52, height: 48)), green, width: 1, id: 82)
    middleNote.verticalAlignment = .middle
    middleNote.alignment = .center
    let notes = [
        annotation(.note("A note that wraps", rect: CGRect(x: 8, y: 8, width: 80, height: 0)), RGBA(1, 0.85, 0), width: 1, id: 81),
        middleNote,
        annotation(.note("Supercalifragilistic", rect: CGRect(x: 60, y: 66, width: 64, height: 0)), blue, width: 1, id: 83),
    ]

    let counters = [
        annotation(.counter(1, center: CGPoint(x: 22, y: 24)), red, width: 1, id: 91),
        annotation(.counter(2, center: CGPoint(x: 62, y: 30)), blue, width: 2, id: 92),
        annotation(.counter(10, center: CGPoint(x: 120, y: 36)), green, width: 4, id: 93),
        annotation(.counter(42, center: CGPoint(x: 50, y: 88)), RGBA(0.3, 0.3, 0.3), width: 3, id: 94),
    ]

    // Sharp-edged shapes under each redaction, so it has detail to hide.
    let detail = [
        annotation(.shape(.rectangle, rect: CGRect(x: 14, y: 14, width: 56, height: 36)), white, width: 2, fill: red, id: 101),
        annotation(.line(from: CGPoint(x: 10, y: 70), to: CGPoint(x: 150, y: 100)), blue, width: 5, id: 102),
        annotation(.shape(.ellipse, rect: CGRect(x: 92, y: 12, width: 50, height: 40)), RGBA(0, 0, 0), width: 3, fill: white, id: 103),
        annotation(.arrow(from: CGPoint(x: 20, y: 110), to: CGPoint(x: 140, y: 64)), green, width: 4, id: 104),
    ]
    let pixelated = detail + [
        annotation(.pixelate(CGRect(x: 8, y: 8, width: 70, height: 50)), red, id: 111),
        annotation(.pixelate(CGRect(x: 86, y: 6, width: 66, height: 104), amount: 0.06), red, id: 112),
    ]
    let blurred = detail + [
        annotation(.blur(CGRect(x: 8, y: 8, width: 70, height: 50)), red, id: 121),
        annotation(.blur(CGRect(x: 86, y: 6, width: 66, height: 104), amount: 0.08), red, id: 122),
    ]
    var softSpot = annotation(.spotlight(CGRect(x: 18, y: 16, width: 64, height: 44), style: SpotlightStyle(effect: .blur, strength: 0.6, softEdge: 0.5)), RGBA(0, 0, 0), id: 131)
    softSpot.cornerRadius = 8
    var softEllipse = annotation(.spotlight(CGRect(x: 96, y: 62, width: 48, height: 40), style: SpotlightStyle(shape: .ellipse, effect: .blur, strength: 0.6, softEdge: 1)), RGBA(0, 0, 0), id: 132)
    softEllipse.cornerRadius = nil
    let blurredSpotlights = detail + [softSpot, softEllipse]
    let outlinedImages = [
        image(CGRect(x: 12, y: 12, width: 60, height: 40), radius: nil, style: ObjectStyle(border: Border(kind: .outline, lineWidth: 4, color: white)), id: 141),
        image(CGRect(x: 92, y: 20, width: 36, height: 24), radius: nil, style: ObjectStyle(border: Border(kind: .outline, lineWidth: 6, color: red)), id: 142),
        image(CGRect(x: 30, y: 70, width: 100, height: 40), radius: nil, style: ObjectStyle(border: Border(kind: .outline, lineWidth: 2, color: RGBA(0, 0, 0))), id: 143),
    ]

    return [
        Golden(name: "lines", annotations: lines),
        Golden(name: "shapes", annotations: shapes),
        Golden(name: "shadows", annotations: shadows, canvasRect: CGRect(x: 0, y: 0, width: 160, height: 120), background: white),
        Golden(name: "images", annotations: images),
        Golden(name: "spotlights", annotations: spotlights),
        Golden(name: "padding", annotations: padded, canvasRect: CGRect(x: -30, y: -10, width: 230, height: 150), background: RGBA(0.95, 0.95, 0.9)),
        Golden(name: "text", annotations: texts),
        Golden(name: "outlinedText", annotations: outlined),
        Golden(name: "notes", annotations: notes, canvasRect: CGRect(x: 0, y: 0, width: 160, height: 120), background: white),
        Golden(name: "counters", annotations: counters),
        Golden(name: "pixelate", annotations: pixelated),
        Golden(name: "blur", annotations: blurred),
        Golden(name: "blurredSpotlights", annotations: blurredSpotlights),
        Golden(name: "outlinedImages", annotations: outlinedImages),
    ]
}

/// The goldens with text in them.
private let textGoldens: Set = ["text", "outlinedText", "notes", "counters"]

/// `golden` drawn over `base` through CGCanvas.
private func render(_ golden: Golden, base: CGImage) throws -> Bitmap {
    let doc = EditorDocument(base: base, annotations: golden.annotations, canvasRect: golden.canvasRect, background: golden.background)
    return try #require(AnnotationRenderer.flatten(doc).flatMap { Bitmap($0) })
}

@Test func theCanvasGoldensAreWhatCGCanvasDraws() throws {
    let codec = ImageIOCodec()
    let write = ProcessInfo.processInfo.environment["SHOT_WRITE_GOLDENS"] == "1"
    let goldens = try goldens()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.userInfo[.pngCodec] = codec
    let json = try encoder.encode(goldens)
    if write {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #require(codec.encode(try base(), as: .png, quality: 1, metadata: ImageMetadata())).write(to: folder.appendingPathComponent("base.png"))
        try json.write(to: folder.appendingPathComponent("goldens.json"))
    }
    #expect(try Data(contentsOf: folder.appendingPathComponent("goldens.json")) == json, "goldens.json is stale: run with SHOT_WRITE_GOLDENS=1")
    let base = try #require(codec.image(at: folder.appendingPathComponent("base.png")))
    for golden in goldens {
        let drawn = try render(golden, base: base)
        let url = folder.appendingPathComponent("\(golden.name).png")
        if write {
            try #require(codec.encode(drawn, as: .png, quality: 1, metadata: ImageMetadata())).write(to: url)
        }
        // A PNG keeps straight alpha, so premultiplied pixels read back within 1 where they're nearly clear.
        let saved = try #require(codec.decode(fileAt: url))
        #expect(saved.width == drawn.width && saved.height == drawn.height, "\(golden.name)")
        let changed = ImageDiff.changes([UInt8](saved.pixels), [UInt8](drawn.pixels), width: drawn.width, height: drawn.height, bytesPerRow: drawn.bytesPerRow, threshold: 1.0 / 255)
        // Core Text antialiases the system font a little differently from one macOS release to the next: CI's macOS 26
        // changes up to 1.4% of a text golden's pixels drawn on macOS 27.
        let allowed = textGoldens.contains(golden.name) ? changed.count * 3 / 100 : 0
        #expect(changed.filter { $0 == 1 }.count <= allowed, "\(golden.name).png is stale: run with SHOT_WRITE_GOLDENS=1")
    }
}
