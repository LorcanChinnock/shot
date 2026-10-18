import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

// Golden tests for #651: every fixture draws the same pixels through `CoreImageEffects` as through the renderer's Core
// Image filters as they were before, `LegacyImageEffects`. They go with it once #651 has landed.

private let red = RGBA.presets[0], blue = RGBA.presets[4], yellow = RGBA.presets[2]

/// A different colour in every pixel of a small tile, in `space`, so any change to a filter changes the bytes.
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

/// One document per effect the renderer runs, each at several sizes and against the image's edges.
private func fixtures() -> [(name: String, doc: EditorDocument)] {
    let base = pattern(width: 240, height: 180)
    let marks = [
        mark(.shape(.rectangle, rect: CGRect(x: 30, y: 30, width: 80, height: 60)), fill: yellow),
        mark(.arrow(from: CGPoint(x: 100, y: 20), to: CGPoint(x: 200, y: 140))),
    ]
    var fixtures: [(String, EditorDocument)] = []

    fixtures.append(("pixelate", EditorDocument(base: base, annotations: marks + [
        mark(.pixelate(CGRect(x: 20, y: 20, width: 100, height: 60))),
        mark(.pixelate(CGRect(x: 10, y: 120, width: 60, height: 50), amount: 0.004)),
        mark(.pixelate(CGRect(x: 130.5, y: 100.25, width: 70.5, height: 41), amount: 0.05)),
        mark(.pixelate(CGRect(x: -20, y: 150, width: 80, height: 60))),
        mark(.pixelate(CGRect(x: 200, y: -10, width: 60, height: 50), amount: 0.02)),
    ])))

    fixtures.append(("blur", EditorDocument(base: base, annotations: marks + [
        mark(.blur(CGRect(x: 120, y: 60, width: 100, height: 80), amount: 0.012)),
        mark(.blur(CGRect(x: 10, y: 10, width: 70, height: 50))),
        mark(.blur(CGRect(x: 20.5, y: 100.75, width: 60.5, height: 45), amount: 0.004)),
        mark(.blur(CGRect(x: 190, y: -15, width: 70, height: 60), amount: 0.05)),
        mark(.blur(CGRect(x: -10, y: 150, width: 60, height: 50))),
    ])))

    fixtures.append(("blurred spotlights", EditorDocument(base: base, annotations: marks + [
        mark(.spotlight(CGRect(x: 40, y: 40, width: 90, height: 70), style: SpotlightStyle(shape: .diamond, effect: .blur, strength: 0.7))),
        mark(.spotlight(CGRect(x: 160, y: 20, width: 60, height: 60), style: SpotlightStyle(shape: .ellipse, effect: .blur, strength: 0.2))),
    ])))

    fixtures.append(("soft spotlights", EditorDocument(base: base, annotations: marks + [
        mark(.spotlight(CGRect(x: 20, y: 30, width: 90, height: 70), style: SpotlightStyle(softEdge: 0.5))),
        mark(.spotlight(CGRect(x: 120, y: 60, width: 80, height: 80), style: SpotlightStyle(shape: .ellipse, effect: .blur, softEdge: 1))),
        mark(.spotlight(CGRect(x: 180, y: 10, width: 50, height: 40), style: SpotlightStyle(softEdge: 0.1))) { $0.cornerRadius = 10 },
    ])))

    let cutout = disc(side: 50)
    fixtures.append(("outlines", EditorDocument(base: base, annotations: [
        mark(.image(AnnotationImage(cutout), rect: CGRect(x: 20, y: 20, width: 50, height: 50))) {
            $0.style = ObjectStyle(border: Border(kind: .outline, lineWidth: 4, color: red))
        },
        mark(.image(AnnotationImage(cutout), rect: CGRect(x: 100.5, y: 30.25, width: 75, height: 75))) {
            $0.style = ObjectStyle(border: Border(kind: .outline, lineWidth: 2.5, color: yellow))
        },
        mark(.image(AnnotationImage(cutout), rect: CGRect(x: 20, y: 110, width: 60, height: 60))) {
            $0.style = ObjectStyle(shadow: ShadowPreset.glow.shadow(scale: 1), border: Border(kind: .outline, lineWidth: 8, color: blue))
        },
    ])))

    var cropped = EditorDocument(base: base, annotations: marks + [mark(.blur(CGRect(x: 60, y: 40, width: 80, height: 60))), mark(.pixelate(CGRect(x: 150, y: 100, width: 60, height: 50)))], background: RGBA(1, 1, 1))
    cropped.crop(to: CGRect(x: 20, y: 15, width: 180, height: 140))
    fixtures.append(("frame crop", cropped))

    let p3 = pattern(width: 200, height: 150, space: CGColorSpace(name: CGColorSpace.displayP3)!)
    fixtures.append(("Display P3", EditorDocument(base: p3, annotations: marks + [
        mark(.blur(CGRect(x: 100, y: 80, width: 80, height: 60))),
        mark(.pixelate(CGRect(x: 10, y: 90, width: 70, height: 50))),
        mark(.spotlight(CGRect(x: 120, y: 10, width: 60, height: 50), style: SpotlightStyle(effect: .blur, softEdge: 0.4))),
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

private func expectSame(_ legacy: CGImage?, _ new: CGImage?, _ comment: Comment) throws {
    let old = try #require(bitmap(legacy), comment), new = try #require(bitmap(new), comment)
    #expect(old.size == new.size, comment)
    #expect(old.space == new.space, comment)
    #expect(old.bytes == new.bytes, comment)
}

/// Both paths share the renderer's cache, which doesn't know which effects made what it holds, so each render starts empty.
private func fresh<T>(_ render: () -> T) -> T {
    AnnotationRenderer.releaseCaches()
    return render()
}

@Test func everyFixtureFlattensToTheSamePixelsThroughTheEffects() throws {
    for (name, doc) in fixtures() {
        let legacy = fresh { AnnotationRenderer.flatten(doc, canvasType: LegacyEffectsCanvas.self) }
        let new = fresh { AnnotationRenderer.flatten(doc) }
        try expectSame(legacy, new, "\(name)")
    }
}

/// The editor draws the document zoomed, which changes the resolution the soft spotlights are blurred at.
@Test func everyFixtureRendersToTheSamePixelsZoomedThroughTheEffects() throws {
    for (name, doc) in fixtures() {
        for zoom in [0.5, 1.5] as [CGFloat] {
            func zoomed(_ canvas: (CGContext) -> any Canvas) -> CGImage? {
                let size = doc.exportSize
                guard let ctx = CGContext(
                    data: nil, width: Int(size.width * zoom), height: Int(size.height * zoom), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    return nil
                }
                ctx.scaleBy(x: zoom, y: zoom)
                fresh { AnnotationRenderer.render(doc, into: canvas(ctx)) }
                return ctx.makeImage()
            }
            let legacy = zoomed { LegacyEffectsCanvas(CGCanvas($0)) }
            let new = zoomed { CGCanvas($0) }
            try expectSame(legacy, new, "\(name) at \(zoom)×")
        }
    }
}

/// Each annotation alone in a top-left-origin context, as the editor draws one being dragged.
@Test func everyAnnotationDrawsTheSamePixelsAloneThroughTheEffects() throws {
    for (name, doc) in fixtures() {
        for (index, annotation) in doc.annotations.enumerated() {
            func alone(_ canvas: (CGContext) -> any Canvas) -> CGImage? {
                let size = doc.exportSize
                guard let ctx = CGContext(
                    data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    return nil
                }
                ctx.translateBy(x: 0, y: size.height)
                ctx.scaleBy(x: 1, y: -1)
                fresh { AnnotationRenderer.draw(annotation, base: doc.base, over: doc.annotations[..<index], background: doc.background, in: canvas(ctx)) }
                return ctx.makeImage()
            }
            let legacy = alone { LegacyEffectsCanvas(CGCanvas($0)) }
            let new = alone { CGCanvas($0) }
            try expectSame(legacy, new, "\(name), annotation \(index)")
        }
    }
}

/// A video frame draws a blur or pixelate over the picture under it, through the same effects.
@Test func aVideoFrameRedactsToTheSamePixelsThroughTheEffects() throws {
    let canvas = CGRect(x: 0, y: 0, width: 240, height: 180)
    let frame = CIImage(cgImage: pattern(width: 240, height: 180))
    let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    let annotations = [
        mark(.blur(CGRect(x: 120, y: 60, width: 100, height: 80))),
        mark(.pixelate(CGRect(x: 20, y: 20, width: 100, height: 60))),
    ]
    func drawn(_ canvasType: any Canvas.Type) -> CGImage? {
        let image = fresh { AnnotationFrame.apply(annotations, to: frame, canvas: canvas, context: context, canvasType: canvasType) }
        return context.createCGImage(image, from: canvas, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
    try expectSame(drawn(LegacyEffectsCanvas.self), drawn(CGCanvas.self), "video frame")
}
