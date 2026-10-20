import Foundation
import Testing
@testable import ShotCoreLinux

// The documents in Tests/Fixtures/canvas/goldens.json drawn through AnnotationRenderer on CairoCanvas, compared with the
// PNGs ShotCoreAppleTests' CanvasGoldenTests drew through CGCanvas. Cairo and CoreGraphics antialias edges a little
// differently, and a shadow's blur is three box blurs rather than CoreGraphics' own, so a pixel may differ by a little,
// and a few edge pixels by more; `limits` says how much for each. Set SHOT_CAIRO_GOLDENS to a folder to write what
// Cairo drew there, to look at.

private let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/canvas")

private struct Golden: Codable {
    var name: String
    var annotations: [Annotation]
    var canvasRect: CGRect?
    var background: RGBA?
}

/// How far a channel may differ before its pixel counts as different, of 255.
private let tolerance = 16

/// A golden, the share of its pixels that may differ by more than `tolerance`, which antialiased edges account for, and
/// how far any channel may differ.
private let limits: [(name: String, share: Double, worst: Int)] = [
    ("lines", 0.005, 24),
    ("shapes", 0.005, 24),
    // The blurred edges of shadows, where three box blurs part from CoreGraphics' blur.
    ("shadows", 0.005, 32),
    // Pictures enlarged five times and more, which CoreGraphics resamples a little more sharply than Cairo's bilinear filter
    // where two colours meet.
    ("images", 0.03, 40),
    ("spotlights", 0.005, 24),
    ("padding", 0.005, 24),
]

private func goldens() throws -> [Golden] {
    let decoder = JSONDecoder()
    decoder.userInfo[.pngCodec] = PNGJPEGCodec()
    return try decoder.decode([Golden].self, from: Data(contentsOf: folder.appendingPathComponent("goldens.json")))
}

@Test(arguments: limits)
func cairoDrawsTheGoldenAsCoreGraphicsDrewIt(name: String, share maxShare: Double, worst maxWorst: Int) throws {
    let codec = PNGJPEGCodec()
    let golden = try #require(try goldens().first { $0.name == name })
    let base = try #require(codec.image(at: folder.appendingPathComponent("base.png")))
    let doc = EditorDocument(base: base, annotations: golden.annotations, canvasRect: golden.canvasRect, background: golden.background)
    let drawn = try #require(AnnotationRenderer.flatten(doc, canvasType: CairoCanvas.self)).bitmap
    if let out = ProcessInfo.processInfo.environment["SHOT_CAIRO_GOLDENS"] {
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        try codec.encode(drawn, as: .png, quality: 1, metadata: ImageMetadata())?.write(to: URL(fileURLWithPath: out).appendingPathComponent("\(name).png"))
    }
    let mac = try #require(codec.decode(fileAt: folder.appendingPathComponent("\(name).png")))
    try #require(mac.width == drawn.width && mac.height == drawn.height)
    var differing = 0, worst = 0
    for y in 0..<mac.height {
        for x in 0..<mac.width {
            let a = mac[x, y], b = drawn[x, y]
            let most = max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b)), abs(Int(a.a) - Int(b.a)))
            worst = max(worst, most)
            if most > tolerance {
                differing += 1
            }
        }
    }
    let share = Double(differing) / Double(mac.width * mac.height)
    print("\(name): \(differing) pixels (\(String(format: "%.2f", share * 100))%) differ by more than \(tolerance), the most by \(worst)")
    #expect(share <= maxShare, "\(name): \(differing) pixels differ by more than \(tolerance)")
    #expect(worst <= maxWorst, "\(name): a pixel differs by \(worst)")
}
