import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

// Projects drawn through ProjectCompositor, the Mac's Core Image compositor, and through PortableCompositor on CGCanvas,
// which must look the same. ShotCoreLinuxTests' CompositorGoldenTests draws them through PortableCompositor on
// CairoCanvas and compares with what ProjectCompositor drew here. They're all in Tests/Fixtures/compositor: the projects
// and times in `goldens.json`, each frame ProjectCompositor drew in `<name>.png`, and the source frames each clip showed
// then in `<name>-<n>.png`, numbered bottom to top as `PortableCompositor.pictures(at:)` gives them.
//
// Frames are compared as they come, with no colour conversion, as the compositors pass them through.
//
// Run with SHOT_WRITE_GOLDENS=1 to write them again after a rendering change, and check the new PNGs by eye.

private let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/compositor")
private let canvas = CGSize(width: 640, height: 360)

/// A project and the time to draw it at, as `goldens.json` keeps it, its clips' sources named by file alone.
private struct Golden: Codable {
    var name: String
    var project: Project
    var time: Double
}

/// The base recording, flat blue-grey with its top-left corner yellow, and a 4:3 clip, flat green with its top-left
/// corner red, so a turn or flip shows.
private struct Sources {
    let base: URL
    let clip: URL

    static func write(in folder: URL) async throws -> Sources {
        let sources = Sources(base: folder.appendingPathComponent("base.mp4"), clip: folder.appendingPathComponent("clip.mp4"))
        try await writeSolidVideo(to: sources.base, color: Color(r: 70, g: 100, b: 140), corner: Color(r: 220, g: 200, b: 60), size: canvas, seconds: 2)
        try await writeSolidVideo(to: sources.clip, color: .green, corner: .red, size: CGSize(width: 400, height: 300), seconds: 2)
        return sources
    }
}

/// How far a channel may differ before its pixel counts as different, of 255.
private let tolerance = 16

/// Each golden, the share of its pixels PortableCompositor on CGCanvas may draw differently from ProjectCompositor by
/// more than `tolerance`, which antialiased edges account for, and how far any channel may differ.
private let limits: [(name: String, share: Double, worst: Int)] = [
    ("styled", 0.005, 32),
    // A turned clip's edges, which Core Image resamples bilinearly where CoreGraphics draws them antialiased.
    ("hairlineGlow", 0.005, 80),
    ("keyframed", 0.005, 80),
    ("faded", 0.005, 32),
    ("annotations", 0.005, 32),
]

private func goldens(_ sources: Sources) throws -> [Golden] {
    let base = Project(source: sources.base, duration: 2, canvasSize: canvas, hasAudio: false)
    let media = ImportedMedia(source: sources.clip, duration: 2, size: CGSize(width: 400, height: 300), hasAudio: false)
    func imported(_ transform: ClipTransform, radius: CGFloat, style: ObjectStyle) throws -> (Project, UUID) {
        let (project, id) = try #require(base.importing(media, at: 0))
        var styled = try #require(project.setting(transform: transform, of: id))
        styled = try #require(styled.setting(cornerRadius: radius, of: id))
        return (try #require(styled.setting(style: style, of: id)), id)
    }
    /// `project` with `id` keyed from `from` at the start to `to` at 2 s.
    func keyed(_ project: Project, _ id: UUID, _ properties: [AnimatedProperty], to change: (inout PropertyValues) -> Void) throws -> Project {
        var project = project
        for property in properties {
            project = try #require(project.togglingKeyframe(property, ofClip: id, at: 0))
        }
        var values = try #require(project.values(ofClip: id, at: 2))
        change(&values)
        return try #require(project.setting(values: values, ofClip: id, at: 2))
    }

    let white = RGBA(1, 1, 1), red = RGBA(0.9, 0.1, 0.1)
    let (styled, _) = try imported(
        ClipTransform(offset: CGSize(width: 40, height: -20), scale: 0.6), radius: 40,
        style: ObjectStyle(shadow: ShadowPreset.float.shadow(scale: 1), border: Border(kind: .solid, lineWidth: 6, color: white))
    )
    let (hairlineGlow, _) = try imported(
        ClipTransform(offset: CGSize(width: -30, height: 10), scale: 0.5, rotation: 0.2), radius: 24,
        style: ObjectStyle(shadow: ShadowPreset.glow.shadow(scale: 1), border: .hairline)
    )
    var (keyframed, moving) = try imported(
        ClipTransform(offset: CGSize(width: -150, height: -60), scale: 0.4), radius: 20, style: ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 1))
    )
    keyframed = try keyed(keyframed, moving, [.position, .scale, .rotation]) { values in
        values.position = CGSize(width: 100, height: 50)
        values.scale = 0.9
        values.rotation = 0.5
    }
    var (faded, fading) = try imported(
        ClipTransform(scale: 0.7), radius: 0, style: ObjectStyle(shadow: ShadowPreset.contact.shadow(scale: 1), border: Border(kind: .solid, lineWidth: 4, color: red))
    )
    faded = try #require(faded.setting(crop: ImageCrop(left: 0.1, top: 0.2, right: 0.15, bottom: 0), of: fading))
    faded = try keyed(faded, fading, [.opacity]) { $0.opacity = 0 }
    faded = faded.setting(frameCrop: CGRect(x: 40, y: 20, width: 560, height: 320))

    func annotation(_ kind: Annotation.Kind, _ color: RGBA, fill: RGBA? = nil, width: CGFloat = 4) -> Annotation {
        Annotation(kind: kind, color: color, fill: fill, lineWidth: width)
    }
    var box = annotation(.shape(.rectangle, rect: CGRect(x: 380, y: 60, width: 180, height: 90)), white, fill: white)
    box.style = ObjectStyle(shadow: ShadowPreset.float.shadow(scale: 1))
    var annotated = base
    for drawn in [
        annotation(.arrow(from: CGPoint(x: 60, y: 300), to: CGPoint(x: 300, y: 200)), red, width: 8),
        box,
        annotation(.highlight(CGRect(x: 60, y: 120, width: 260, height: 40)), RGBA(1, 0.92, 0.2)),
        annotation(.blur(CGRect(x: 100, y: 40, width: 120, height: 80)), red),
    ] {
        annotated = annotated.adding(annotation: drawn, at: 0, duration: 2).project
    }
    // A bar turned and faded halfway by 1 s, and a highlight faded halfway, which only fades.
    var turning: UUID
    (annotated, turning) = annotated.adding(annotation: annotation(.shape(.rectangle, rect: CGRect(x: 380, y: 220, width: 200, height: 50)), red, fill: red), at: 0, duration: 2)
    annotated = try keyed(annotated, turning, [.rotation, .opacity]) { values in
        values.rotation = 1
        values.opacity = 0
    }
    var fadingHighlight: UUID
    (annotated, fadingHighlight) = annotated.adding(annotation: annotation(.highlight(CGRect(x: 200, y: 300, width: 300, height: 30)), RGBA(0.3, 0.9, 1)), at: 0, duration: 2)
    annotated = try keyed(annotated, fadingHighlight, [.opacity]) { $0.opacity = 0 }

    return [
        Golden(name: "styled", project: styled, time: 1),
        Golden(name: "hairlineGlow", project: hairlineGlow, time: 1),
        Golden(name: "keyframed", project: keyframed, time: 1),
        Golden(name: "faded", project: faded, time: 1),
        Golden(name: "annotations", project: annotated, time: 1),
    ]
}

/// `image`'s pixels as they're stored, read in its own colour space so nothing is converted.
private func stored(_ image: CGImage) throws -> Bitmap {
    let width = image.width, height = image.height
    var pixels = Data(count: width * height * 4)
    let space = try #require(image.colorSpace)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    try #require(drawn)
    return try #require(Bitmap(width: width, height: height, pixels: pixels))
}

/// The frame at `time` of `asset`, played through `composition` when it's given.
private func decodedFrame(of asset: AVAsset, composition: AVVideoComposition? = nil, at time: Double) async throws -> Bitmap {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.videoComposition = composition
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return try stored(try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image)
}

/// What ProjectCompositor draws of `golden`, and the source frames its clips show then, bottom to top.
private func drawn(_ golden: Golden) async throws -> (frame: Bitmap, pictures: [Bitmap]) {
    let built = try await CompositionBuilder.build(golden.project)
    let frame = try await decodedFrame(of: built.asset, composition: built.videoComposition, at: golden.time)
    var pictures: [Bitmap] = []
    for (clip, time) in PortableCompositor(project: golden.project, canvasType: CGCanvas.self).pictures(at: golden.time) {
        pictures.append(try await decodedFrame(of: AVURLAsset(url: clip.source), at: time))
    }
    return (frame, pictures)
}

/// The share of `drawn`'s pixels that differ from `expected` by more than `tolerance`, and the most any channel differs by.
private func difference(_ drawn: Bitmap, from expected: Bitmap) -> (share: Double, worst: Int) {
    var differing = 0, worst = 0
    for y in 0..<drawn.height {
        for x in 0..<drawn.width {
            let a = drawn[x, y], b = expected[x, y]
            let most = [abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b)), abs(Int(a.a) - Int(b.a))].max() ?? 0
            worst = max(worst, most)
            if most > tolerance {
                differing += 1
            }
        }
    }
    return (Double(differing) / Double(drawn.width * drawn.height), worst)
}

extension CompositingMediaTests {
    @Test func thePortableCompositorDrawsEachFrameAsTheCoreImageOneDoes() async throws {
        let temporary = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let codec = ImageIOCodec()
        let write = ProcessInfo.processInfo.environment["SHOT_WRITE_GOLDENS"] == "1"
        let goldens = try goldens(try await Sources.write(in: temporary))
        var kept: [Golden] = []
        for golden in goldens {
            let (expected, pictures) = try await drawn(golden)
            let compositor = PortableCompositor(project: golden.project, canvasType: CGCanvas.self)
            let shown = compositor.pictures(at: golden.time)
            try #require(shown.count == pictures.count)
            let frames = try Dictionary(uniqueKeysWithValues: zip(shown, pictures).map { (shown, picture) in (shown.clip.id, try #require(picture.cgImage)) })
            let portable = try #require(compositor.frame(at: golden.time, pictures: frames).flatMap { Bitmap($0) })
            try #require(portable.width == expected.width && portable.height == expected.height, "\(golden.name)")
            let (share, worst) = difference(portable, from: expected)
            let limit = try #require(limits.first { $0.name == golden.name })
            print("\(golden.name): \(String(format: "%.2f", share * 100))% differ by more than \(tolerance), the most by \(worst)")
            #expect(share <= limit.share, "\(golden.name): \(String(format: "%.2f", share * 100))% differ by more than \(tolerance)")
            #expect(worst <= limit.worst, "\(golden.name): a channel differs by \(worst)")

            guard write else {
                continue
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try #require(codec.encode(expected, as: .png, quality: 1, metadata: ImageMetadata())).write(to: folder.appendingPathComponent("\(golden.name).png"))
            for (index, picture) in pictures.enumerated() {
                try #require(codec.encode(picture, as: .png, quality: 1, metadata: ImageMetadata())).write(to: folder.appendingPathComponent("\(golden.name)-\(index).png"))
            }
            var saved = golden
            for track in saved.project.tracks.indices {
                for clip in saved.project.tracks[track].clips.indices {
                    saved.project.tracks[track].clips[clip].source = URL(fileURLWithPath: "/" + saved.project.tracks[track].clips[clip].source.lastPathComponent)
                }
            }
            kept.append(saved)
        }
        if write {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.userInfo[.pngCodec] = codec
            try encoder.encode(kept).write(to: folder.appendingPathComponent("goldens.json"))
        }
    }
}
