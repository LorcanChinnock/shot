import Foundation
import Testing
@testable import ShotCoreLinux

// The documents in Tests/Fixtures/canvas/goldens.json drawn through AnnotationRenderer on CairoCanvas, compared with the
// PNGs ShotCoreAppleTests' CanvasGoldenTests drew through CGCanvas. Cairo and CoreGraphics antialias edges a little
// differently, and a shadow's blur is three box blurs rather than CoreGraphics' own, so a pixel may differ by a little,
// and a few edge pixels by more; `limits` says how much for each. Text is in another font on Linux, so its goldens are
// compared over blocks of pixels, each averaged. Set SHOT_CAIRO_GOLDENS to a folder to write what Cairo drew there, to
// look at.

private let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/canvas")

private struct Golden: Codable {
    var name: String
    var annotations: [Annotation]
    var canvasRect: CGRect?
    var background: RGBA?
}

/// How far a channel may differ before its pixel counts as different, of 255.
private let tolerance = 16

/// A golden, the size of the blocks compared, the share of them that may differ by more than `tolerance`, which
/// antialiased edges account for, and how far any channel may differ.
private let limits: [(name: String, block: Int, share: Double, worst: Int)] = [
    ("lines", 1, 0.005, 24),
    ("shapes", 1, 0.005, 24),
    // The blurred edges of shadows, where three box blurs part from CoreGraphics' blur.
    ("shadows", 1, 0.005, 32),
    // Pictures enlarged five times and more, which CoreGraphics resamples a little more sharply than Cairo's bilinear filter
    // where two colours meet.
    ("images", 1, 0.03, 40),
    ("spotlights", 1, 0.005, 24),
    ("padding", 1, 0.005, 24),
    // Text, in DejaVu Sans on Linux where the Mac draws San Francisco, whose letters are narrower, so a note wraps
    // differently. Over 20-pixel blocks, the text differs in up to an eighth of them, where drawing none differs in a
    // third to two thirds. PangoShaperTests checks where text is drawn, exactly.
    ("text", 20, 0.1, 40),
    ("outlinedText", 20, 0.2, 100),
    ("notes", 20, 0.15, 100),
    ("counters", 20, 0.05, 32),
    // Image effects, which match Core Image's within a few levels.
    ("pixelate", 1, 0.005, 16),
    ("blur", 1, 0.005, 16),
    ("blurredSpotlights", 1, 0.005, 24),
    // As "images", whose pictures these are.
    ("outlinedImages", 1, 0.04, 40),
]

private func goldens() throws -> [Golden] {
    let decoder = JSONDecoder()
    decoder.userInfo[.pngCodec] = PNGJPEGCodec()
    return try decoder.decode([Golden].self, from: Data(contentsOf: folder.appendingPathComponent("goldens.json")))
}

@Test(arguments: limits)
func cairoDrawsTheGoldenAsCoreGraphicsDrewIt(name: String, block: Int, share maxShare: Double, worst maxWorst: Int) throws {
    let drawn = try draw(name)
    if let out = ProcessInfo.processInfo.environment["SHOT_CAIRO_GOLDENS"] {
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        try PNGJPEGCodec().encode(drawn, as: .png, quality: 1, metadata: ImageMetadata())?.write(to: URL(fileURLWithPath: out).appendingPathComponent("\(name).png"))
    }
    let (share, worst) = try compare(drawn, with: name, block: block)
    #expect(share <= maxShare, "\(name): \(String(format: "%.2f", share * 100))% differ by more than \(tolerance)")
    #expect(worst <= maxWorst, "\(name): a channel differs by \(worst)")
}

// The effect goldens' limits catch an effect that draws nothing: the golden drawn without its effects fails them.
@Test(arguments: ["pixelate", "blur", "blurredSpotlights", "outlinedImages"])
func anEffectThatDrewNothingWouldFailItsGolden(name: String) throws {
    let limit = try #require(limits.first { $0.name == name })
    let (share, worst) = try compare(try draw(name, withoutEffects: true), with: name, block: limit.block)
    #expect(share > limit.share * 2 && worst > limit.worst)
}

/// The golden `name` drawn through CairoCanvas, without its redactions, spotlights and outlines if `withoutEffects`.
private func draw(_ name: String, withoutEffects: Bool = false) throws -> Bitmap {
    let codec = PNGJPEGCodec()
    let golden = try #require(try goldens().first { $0.name == name })
    let base = try #require(codec.image(at: folder.appendingPathComponent("base.png")))
    var annotations = golden.annotations
    if withoutEffects {
        annotations = annotations.compactMap { annotation in
            switch annotation.kind {
            case .pixelate, .blur, .spotlight:
                return nil
            default:
                var plain = annotation
                plain.style = ObjectStyle()
                return plain
            }
        }
    }
    let doc = EditorDocument(base: base, annotations: annotations, canvasRect: golden.canvasRect, background: golden.background)
    return try #require(AnnotationRenderer.flatten(doc, canvasType: CairoCanvas.self)).bitmap
}

/// The share of `block`-pixel blocks of `drawn` that differ from the golden `name` the Mac drew by more than
/// `tolerance`, and the most any channel differs by.
private func compare(_ drawn: Bitmap, with name: String, block: Int) throws -> (share: Double, worst: Int) {
    let mac = try #require(PNGJPEGCodec().decode(fileAt: folder.appendingPathComponent("\(name).png")))
    try #require(mac.width == drawn.width && mac.height == drawn.height)
    let a = blocks(of: mac, size: block), b = blocks(of: drawn, size: block)
    var differing = 0, worst = 0
    for (x, y) in zip(a, b) {
        let most = zip(x, y).map { abs($0 - $1) }.max() ?? 0
        worst = max(worst, most)
        if most > tolerance {
            differing += 1
        }
    }
    let share = Double(differing) / Double(a.count)
    let unit = block == 1 ? "pixels" : "\(block)-pixel blocks"
    print("\(name): \(differing) \(unit) (\(String(format: "%.2f", share * 100))%) differ by more than \(tolerance), the most by \(worst)")
    return (share, worst)
}

/// Each `size` × `size` block's channels averaged, left to right and top to bottom; a block at the edge is smaller.
private func blocks(of bitmap: Bitmap, size: Int) -> [[Int]] {
    stride(from: 0, to: bitmap.height, by: size).flatMap { top in
        stride(from: 0, to: bitmap.width, by: size).map { left in
            var sums = [0, 0, 0, 0], count = 0
            for y in top..<min(top + size, bitmap.height) {
                for x in left..<min(left + size, bitmap.width) {
                    let p = bitmap[x, y]
                    sums[0] += Int(p.r)
                    sums[1] += Int(p.g)
                    sums[2] += Int(p.b)
                    sums[3] += Int(p.a)
                    count += 1
                }
            }
            return sums.map { ($0 + count / 2) / count }
        }
    }
}
