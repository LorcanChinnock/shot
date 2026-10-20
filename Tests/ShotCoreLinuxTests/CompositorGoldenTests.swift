import Foundation
import Testing
@testable import ShotCoreLinux

// The projects in Tests/Fixtures/compositor/goldens.json drawn through PortableCompositor on CairoCanvas, compared with
// the frames ShotCoreAppleTests' CompositorGoldenTests drew through ProjectCompositor, the Mac's Core Image compositor,
// from the same source frames. Cairo antialiases a turned picture's edges where Core Image resamples them, and a
// shadow's blur is three box blurs rather than a gaussian, so a pixel may differ by a little, and a few edge pixels by
// more; `limits` says how much for each. Set SHOT_CAIRO_GOLDENS to a folder to write what Cairo drew there, to look at.

private let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/compositor")

private struct Golden: Codable {
    var name: String
    var project: Project
    var time: Double
}

/// How far a channel may differ before its pixel counts as different, of 255.
private let tolerance = 16

/// A golden, the share of its pixels that may differ by more than `tolerance`, and how far any channel may differ.
private let limits: [(name: String, share: Double, worst: Int)] = [
    ("styled", 0.005, 32),
    // A turned clip's edges, as on the Mac, where PortableCompositor on CGCanvas differs from Core Image by as much.
    ("hairlineGlow", 0.005, 80),
    ("keyframed", 0.005, 80),
    ("faded", 0.005, 32),
    ("annotations", 0.005, 32),
]

private func golden(_ name: String) throws -> Golden {
    let decoder = JSONDecoder()
    decoder.userInfo[.pngCodec] = PNGJPEGCodec()
    let goldens = try decoder.decode([Golden].self, from: Data(contentsOf: folder.appendingPathComponent("goldens.json")))
    return try #require(goldens.first { $0.name == name })
}

@Test(arguments: limits)
func cairoComposesTheGoldenFrameAsCoreImageDid(name: String, share maxShare: Double, worst maxWorst: Int) throws {
    let drawn = try draw(try golden(name))
    if let out = ProcessInfo.processInfo.environment["SHOT_CAIRO_GOLDENS"] {
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        try PNGJPEGCodec().encode(drawn, as: .png, quality: 1, metadata: ImageMetadata())?.write(to: URL(fileURLWithPath: out).appendingPathComponent("compositor-\(name).png"))
    }
    let (share, worst) = try compare(drawn, with: name)
    #expect(share <= maxShare, "\(name): \(String(format: "%.2f", share * 100))% differ by more than \(tolerance)")
    #expect(worst <= maxWorst, "\(name): a channel differs by \(worst)")
}

// The limits catch a compositor that leaves out the clip's style or the annotations: each golden drawn without them fails
// one of them by a clear margin. A hairline and a glow cover few pixels, but change them by far more than the limit.
@Test(arguments: limits.map(\.name))
func aFrameDrawnWithoutItsStylesOrAnnotationsWouldFailItsGolden(name: String) throws {
    var plain = try golden(name)
    for track in plain.project.tracks.indices {
        plain.project.tracks[track].annotations = []
        for clip in plain.project.tracks[track].clips.indices {
            plain.project.tracks[track].clips[clip].style = ObjectStyle()
            plain.project.tracks[track].clips[clip].cornerRadius = 0
        }
    }
    let limit = try #require(limits.first { $0.name == name })
    let (share, worst) = try compare(try draw(plain, pictures: name), with: name)
    #expect(share > limit.share * 2 || worst > limit.worst + 32)
}

@Test func theCompositorDrawsOnlyTheCanvasBackgroundWhereNoClipHasAFrame() throws {
    let golden = try golden("styled")
    let compositor = PortableCompositor(project: golden.project, canvasType: CairoCanvas.self)
    let frame = try #require(compositor.frame(at: golden.time, pictures: [:])).bitmap
    let corners: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)] = [frame[0, 0], frame[frame.width - 1, frame.height - 1], frame[frame.width / 2, frame.height / 2]]
    #expect(corners.allSatisfy { $0 == (0, 0, 0, 255) })
}

@Test func theCompositorSaysWhichSourceFrameEachClipShows() throws {
    let golden = try golden("keyframed")
    let shown = PortableCompositor(project: golden.project, canvasType: CairoCanvas.self).pictures(at: 1.25)
    let names: [String] = shown.map(\.clip.source.lastPathComponent)
    #expect(names == ["base.mp4", "clip.mp4"])
    let times: [Double] = shown.map(\.sourceTime)
    #expect(times == [1.25, 1.25])
}

/// `golden` drawn through CairoCanvas from the source frames saved for the golden named `pictures`, or its own.
private func draw(_ golden: Golden, pictures: String? = nil) throws -> Bitmap {
    let codec = PNGJPEGCodec()
    let compositor = PortableCompositor(project: golden.project, canvasType: CairoCanvas.self)
    var frames: [UUID: PlatformImage] = [:]
    for (index, shown) in compositor.pictures(at: golden.time).enumerated() {
        frames[shown.clip.id] = try #require(codec.image(at: folder.appendingPathComponent("\(pictures ?? golden.name)-\(index).png")))
    }
    return try #require(compositor.frame(at: golden.time, pictures: frames)).bitmap
}

/// The share of `drawn`'s pixels that differ from the frame `name` the Mac drew by more than `tolerance`, and the most
/// any channel differs by.
private func compare(_ drawn: Bitmap, with name: String) throws -> (share: Double, worst: Int) {
    let mac = try #require(PNGJPEGCodec().decode(fileAt: folder.appendingPathComponent("\(name).png")))
    try #require(mac.width == drawn.width && mac.height == drawn.height)
    var differing = 0, worst = 0
    for y in 0..<drawn.height {
        for x in 0..<drawn.width {
            let a = drawn[x, y], b = mac[x, y]
            let most: Int = [abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b)), abs(Int(a.a) - Int(b.a))].max() ?? 0
            worst = max(worst, most)
            if most > tolerance {
                differing += 1
            }
        }
    }
    let share = Double(differing) / Double(drawn.width * drawn.height)
    print("\(name): \(differing) pixels (\(String(format: "%.2f", share * 100))%) differ by more than \(tolerance), the most by \(worst)")
    return (share, worst)
}
