import CoreGraphics
import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

// Golden tests for #648: every fixture draws the same pixels through `CGCanvas` as through the renderer as it was before
// it had a canvas, `LegacyAnnotationRenderer`. They go with it once #648 has landed.

private let red = RGBA.presets[0], blue = RGBA.presets[4], yellow = RGBA.presets[2]

/// A different colour in every pixel of a small tile, in `space`, so any change to a filter or blend changes the bytes.
private func pattern(width: Int, height: Int, space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for x in 0..<width {
        for y in 0..<height {
            ctx.setFillColor(CGColor(colorSpace: space, components: [CGFloat(x % 17) / 16, CGFloat(y % 13) / 12, CGFloat((x * y) % 7) / 6, 1])!)
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    return ctx.makeImage()!
}

/// A blue disc on clear, for an outline to follow.
private func disc(side: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(blue.cgColor)
    ctx.fillEllipse(in: CGRect(x: side / 8, y: side / 8, width: side * 3 / 4, height: side * 3 / 4))
    return ctx.makeImage()!
}

private func mark(_ kind: Annotation.Kind, color: RGBA = red, fill: RGBA? = nil, width: CGFloat = 4, _ change: (inout Annotation) -> Void = { _ in }) -> Annotation {
    var annotation = Annotation(kind: kind, color: color, fill: fill, lineWidth: width)
    change(&annotation)
    return annotation
}

private func placed(_ image: CGImage, at rect: CGRect, _ change: (inout Annotation) -> Void = { _ in }) -> Annotation {
    mark(.image(AnnotationImage(image), rect: rect), change)
}

private let scribble = [CGPoint(x: 20, y: 150), CGPoint(x: 45, y: 120), CGPoint(x: 70, y: 160), CGPoint(x: 95, y: 115), CGPoint(x: 130, y: 150)]

/// One document per area of the renderer, between them every kind of annotation and every style it can have.
private func fixtures() -> [(name: String, doc: EditorDocument)] {
    let base = pattern(width: 240, height: 180)
    let shadow = ShadowPreset.float.shadow(scale: 1)
    var fixtures: [(String, EditorDocument)] = []

    let shapes = BoxShape.allCases.enumerated().flatMap { index, shape in
        let x = CGFloat(index) * 45 + 5
        return [
            mark(.shape(shape, rect: CGRect(x: x, y: 10, width: 40, height: 30))),
            mark(.shape(shape, rect: CGRect(x: x, y: 50, width: 40, height: 30)), fill: yellow) { $0.cornerRadius = 8 },
        ]
    }
    fixtures.append(("marks", EditorDocument(base: base, annotations: shapes + [
        mark(.arrow(from: CGPoint(x: 10, y: 100), to: CGPoint(x: 120, y: 110))),
        mark(.arrow(from: CGPoint(x: 10, y: 130), to: CGPoint(x: 120, y: 170))) { $0.bend = CGVector(dx: 10, dy: -20) },
        mark(.line(from: CGPoint(x: 130, y: 100), to: CGPoint(x: 230, y: 110)), width: 6),
        mark(.line(from: CGPoint(x: 130, y: 130), to: CGPoint(x: 230, y: 170))) { $0.bend = CGVector(dx: -15, dy: 10) },
        mark(.counter(3, center: CGPoint(x: 200, y: 60))),
        mark(.freehand(scribble), color: blue),
        mark(.freehand([CGPoint(x: 220, y: 20)]), width: 10),
        mark(.marker(scribble.map { CGPoint(x: $0.x + 80, y: $0.y - 30) }), color: yellow),
        mark(.highlight(CGRect(x: 60, y: 60, width: 100, height: 20))),
    ])))

    fixtures.append(("text", EditorDocument(base: base, annotations: [
        mark(.text("Left\nand two lines", origin: CGPoint(x: 10, y: 10), fontSize: 18)),
        mark(.text("Centred\nlines", origin: CGPoint(x: 140, y: 10), fontSize: 16)) { $0.alignment = .center },
        mark(.text("Right", origin: CGPoint(x: 140, y: 70), fontSize: 20)) { $0.alignment = .right },
        mark(.text("Outlined", origin: CGPoint(x: 10, y: 70), fontSize: 24)) { $0.style = ObjectStyle(border: Border(kind: .outline, lineWidth: 3, color: blue)) },
        mark(.text("Shadow", origin: CGPoint(x: 10, y: 110), fontSize: 24)) { $0.style = ObjectStyle(shadow: shadow) },
        mark(.counter(12, center: CGPoint(x: 200, y: 140))),
        mark(.note("A note on top", rect: CGRect(x: 100, y: 110, width: 80, height: 50)), color: yellow),
    ])))

    fixtures.append(("styled marks", EditorDocument(base: base, annotations: [
        mark(.arrow(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 200, y: 60))) { $0.style = ObjectStyle(shadow: shadow) },
        mark(.shape(.star, rect: CGRect(x: 30, y: 80, width: 70, height: 70)), fill: yellow) { $0.style = ObjectStyle(shadow: ShadowPreset.glow.shadow(scale: 1)) },
        mark(.freehand(scribble.map { CGPoint(x: $0.x + 90, y: $0.y) }), color: blue) { $0.style = ObjectStyle(shadow: ShadowPreset.contact.shadow(scale: 1)) },
    ])))

    let marks = [
        mark(.shape(.rectangle, rect: CGRect(x: 30, y: 30, width: 80, height: 60)), fill: yellow),
        mark(.arrow(from: CGPoint(x: 100, y: 20), to: CGPoint(x: 200, y: 140))),
    ]
    fixtures.append(("redactions", EditorDocument(base: base, annotations: marks + [
        mark(.pixelate(CGRect(x: 20, y: 20, width: 100, height: 60))),
        mark(.blur(CGRect(x: 120, y: 60, width: 100, height: 80), amount: 0.012)),
        mark(.pixelate(CGRect(x: 10, y: 120, width: 60, height: 50), amount: 0.004)),
    ])))

    fixtures.append(("spotlights", EditorDocument(base: base, annotations: marks + [
        mark(.spotlight(CGRect(x: 20, y: 20, width: 80, height: 60), style: SpotlightStyle())),
        mark(.spotlight(CGRect(x: 130, y: 30, width: 70, height: 70), style: SpotlightStyle(shape: .ellipse))),
    ])))
    fixtures.append(("blurred spotlight", EditorDocument(base: base, annotations: marks + [
        mark(.spotlight(CGRect(x: 40, y: 40, width: 90, height: 70), style: SpotlightStyle(shape: .diamond, effect: .blur, strength: 0.7))),
    ])))
    fixtures.append(("soft spotlights", EditorDocument(base: base, annotations: marks + [
        mark(.spotlight(CGRect(x: 20, y: 30, width: 90, height: 70), style: SpotlightStyle(softEdge: 0.5))),
        mark(.spotlight(CGRect(x: 120, y: 60, width: 80, height: 80), style: SpotlightStyle(shape: .ellipse, effect: .blur, softEdge: 1))),
        mark(.spotlight(CGRect(x: 180, y: 10, width: 50, height: 40), style: SpotlightStyle())) { $0.cornerRadius = 10 },
    ])))

    let photo = pattern(width: 60, height: 45), cutout = disc(side: 50)
    fixtures.append(("placed images", EditorDocument(base: base, annotations: [
        placed(photo, at: CGRect(x: 10, y: 10, width: 60, height: 45)),
        placed(photo, at: CGRect(x: 90.4, y: 10.6, width: 90, height: 67)) { $0.cornerRadius = 12 },
        placed(photo, at: CGRect(x: 10, y: 70, width: 60, height: 45)) { $0.style = ObjectStyle(border: Border(kind: .hairline)) },
        placed(photo, at: CGRect(x: 90, y: 90, width: 60, height: 45)) {
            $0.cornerRadius = 8
            $0.style = ObjectStyle(shadow: shadow, border: Border(kind: .solid, lineWidth: 4, color: yellow))
        },
        placed(cutout, at: CGRect(x: 170, y: 90, width: 50, height: 50)) { $0.style = ObjectStyle(border: Border(kind: .outline, lineWidth: 4, color: red)) },
        placed(cutout, at: CGRect(x: 170, y: 20, width: 50, height: 50)) { $0.style = ObjectStyle(shadow: ShadowPreset.glow.shadow(scale: 1)) },
        placed(photo, at: CGRect(x: 10, y: 130, width: 60, height: 45)) {
            $0.imageCrop = ImageCrop(left: 0.1, top: 0.2, right: 0.15, bottom: 0)
            $0.style = ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 1), border: Border(kind: .hairline))
        },
    ])))

    var styled = EditorDocument(base: base, annotations: marks, canvasRect: CGRect(x: -30, y: -20, width: 300, height: 220), background: RGBA(0.9, 0.95, 1))
    styled.captureCornerRadius = 14
    styled.captureStyle = ObjectStyle(shadow: shadow, border: Border(kind: .solid, lineWidth: 3, color: blue))
    fixtures.append(("styled capture", styled))

    var cropped = EditorDocument(base: base, annotations: marks + [mark(.blur(CGRect(x: 60, y: 40, width: 80, height: 60)))], background: RGBA(1, 1, 1))
    cropped.crop(to: CGRect(x: 20, y: 15, width: 180, height: 140))
    fixtures.append(("frame crop", cropped))

    fixtures.append(("hidden", EditorDocument(base: base, annotations: [
        marks[0],
        mark(.blur(CGRect(x: 40, y: 40, width: 100, height: 60))) { $0.isHidden = true },
        mark(.spotlight(CGRect(x: 40, y: 40, width: 60, height: 60), style: SpotlightStyle())) { $0.isHidden = true },
    ])))

    let p3 = pattern(width: 200, height: 150, space: CGColorSpace(name: CGColorSpace.displayP3)!)
    fixtures.append(("Display P3", EditorDocument(base: p3, annotations: marks + [
        mark(.highlight(CGRect(x: 10, y: 100, width: 80, height: 20))),
        mark(.blur(CGRect(x: 100, y: 80, width: 80, height: 60))),
        mark(.spotlight(CGRect(x: 120, y: 10, width: 60, height: 50), style: SpotlightStyle(softEdge: 0.4))),
        placed(photo, at: CGRect(x: 20, y: 20, width: 60, height: 45)) { $0.style = ObjectStyle(shadow: shadow, border: Border(kind: .hairline)) },
    ])))
    return fixtures
}

/// The pixels and the layout of `image`, which two images match in only if they're the same bitmap.
private func bitmap(_ image: CGImage?) -> (size: [Int], space: String?, bytes: Data)? {
    guard let image, let data = image.dataProvider?.data as Data? else {
        return nil
    }
    return ([image.width, image.height, image.bitsPerPixel, image.bytesPerRow], image.colorSpace?.name as String?, data)
}

private func expectSame(_ legacy: CGImage?, _ canvas: CGImage?, _ comment: Comment) throws {
    let old = try #require(bitmap(legacy), comment), new = try #require(bitmap(canvas), comment)
    #expect(old.size == new.size, comment)
    #expect(old.space == new.space, comment)
    #expect(old.bytes == new.bytes, comment)
}

/// Starts both renderers with nothing cached, so neither reuses what an earlier fixture made.
private func forgetCaches() {
    LegacyAnnotationRenderer.cache.removeAll()
    AnnotationRenderer.releaseCaches()
}

@Test func everyFixtureFlattensToTheSamePixelsOnACanvas() throws {
    for (name, doc) in fixtures() {
        forgetCaches()
        let legacy = LegacyAnnotationRenderer.flatten(doc), canvas = AnnotationRenderer.flatten(doc)
        try expectSame(legacy, canvas, "\(name)")
        // Again, from what the first renders cached.
        try expectSame(LegacyAnnotationRenderer.flatten(doc), AnnotationRenderer.flatten(doc), "\(name), cached")
        try expectSame(legacy, AnnotationRenderer.flatten(doc), "\(name), cached against fresh")
    }
}

/// The editor draws the document zoomed, which scales the shadows and the resolution they're cached at.
@Test func everyFixtureRendersToTheSamePixelsZoomed() throws {
    for (name, doc) in fixtures() {
        for zoom in [0.5, 1.5] as [CGFloat] {
            forgetCaches()
            func zoomed(_ render: (CGContext) -> Void) -> CGImage? {
                let size = doc.exportSize
                guard let ctx = CGContext(
                    data: nil, width: Int(size.width * zoom), height: Int(size.height * zoom), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    return nil
                }
                ctx.scaleBy(x: zoom, y: zoom)
                render(ctx)
                return ctx.makeImage()
            }
            let legacy = zoomed { LegacyAnnotationRenderer.render(doc, into: $0) }
            let canvas = zoomed { AnnotationRenderer.render(doc, into: $0) }
            try expectSame(legacy, canvas, "\(name) at \(zoom)×")
        }
    }
}

/// Each annotation alone in a top-left-origin context, as the editor draws one being dragged and a video frame draws its overlay.
@Test func everyAnnotationDrawsTheSamePixelsAloneOnACanvas() throws {
    for (name, doc) in fixtures() {
        forgetCaches()
        for (index, annotation) in doc.annotations.enumerated() {
            func alone(_ draw: (CGContext) -> Void) -> CGImage? {
                let size = doc.exportSize
                guard let ctx = CGContext(
                    data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    return nil
                }
                ctx.translateBy(x: 0, y: size.height)
                ctx.scaleBy(x: 1, y: -1)
                draw(ctx)
                return ctx.makeImage()
            }
            let below = doc.annotations[..<index]
            let legacy = alone { LegacyAnnotationRenderer.draw(annotation, base: doc.base, over: below, background: doc.background, in: $0) }
            let canvas = alone { AnnotationRenderer.draw(annotation, base: doc.base, over: below, background: doc.background, in: $0) }
            try expectSame(legacy, canvas, "\(name), annotation \(index)")
        }
    }
}
