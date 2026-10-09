import AVFoundation
import CoreImage
import ImageIO
import Testing
@testable import ShotCore

struct Color {
    var r: UInt8, g: UInt8, b: UInt8
    static let red = Color(r: 255, g: 0, b: 0)
    /// Mid-tone, since a primary at the edge of the gamut shifts the most through a video encode and decode.
    static let green = Color(r: 60, g: 200, b: 90)
    static let blue = Color(r: 0, g: 0, b: 255)
    static let black = Color(r: 0, g: 0, b: 0)

    func isNear(_ other: Color, tolerance: Int = 60) -> Bool {
        abs(Int(r) - Int(other.r)) <= tolerance && abs(Int(g) - Int(other.g)) <= tolerance && abs(Int(b) - Int(other.b)) <= tolerance
    }
}

/// A video of one flat colour, optionally with a corner marked in a second colour so orientation shows.
func writeSolidVideo(to url: URL, color: Color, corner: Color? = nil, size: CGSize, seconds: Double, rotated: Bool = false) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)])
    if rotated {
        input.transform = CGAffineTransform(rotationAngle: .pi / 2)
    }
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    // Every frame is the same, so it's filled once: per pixel per frame is slow in a debug build.
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &buffer)
    let pixels = try #require(buffer)
    CVPixelBufferLockBaseAddress(pixels, [])
    let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(pixels)
    for y in 0..<Int(size.height) {
        for x in 0..<Int(size.width) {
            let marked = corner != nil && x < Int(size.width) / 4 && y < Int(size.height) / 4
            let c = marked ? corner! : color
            let p = base + y * stride + x * 4
            p[0] = c.b; p[1] = c.g; p[2] = c.r; p[3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(pixels, [])
    for frame in 0..<Int(seconds * 30) {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(2))
        }
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
    }
    input.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
}

/// The colour at (`x`, `y`), as fractions of the frame from the top left, of the frame shown at `seconds`.
func pixel(in url: URL, at seconds: Double, x: Double, y: Double) async throws -> Color {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Draw so the wanted pixel falls on the one pixel of the context.
    let width = Double(image.width), height = Double(image.height)
    context.draw(image, in: CGRect(x: -x * width, y: -(1 - y) * height, width: width, height: height))
    return Color(r: bytes[0], g: bytes[1], b: bytes[2])
}

private let canvas = CGSize(width: 640, height: 360)

private func temp(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
}

extension MediaTests {
    @Test func anOverlayDrawsOverTheRecordingOnlyWhileItIsThere() async throws {
        let base = temp("base.mp4"), top = temp("top.mp4"), output = temp("out.mp4")
        defer { [base, top, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: base, color: .red, size: canvas, seconds: 4)
        try await writeSolidVideo(to: top, color: .green, size: canvas, seconds: 1)

        var project = Project(source: base, duration: 4, canvasSize: canvas, hasAudio: false)
        let (imported, id) = try #require(project.importing(ImportedMedia(source: top, duration: 1, size: canvas, hasAudio: false), at: 2))
        project = try #require(imported.setting(transform: ClipTransform(scale: 0.5), of: id))
        try await ProjectExporter.export(project, to: output)

        let track = try #require(try await AVURLAsset(url: output).loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == canvas)
        #expect(abs(try await AVURLAsset(url: output).load(.duration).seconds - 4) < 0.2)
        #expect(try await pixel(in: output, at: 1, x: 0.5, y: 0.5).isNear(.red), "before the overlay")
        #expect(try await pixel(in: output, at: 2.5, x: 0.5, y: 0.5).isNear(.green), "the overlay's middle")
        #expect(try await pixel(in: output, at: 2.5, x: 0.05, y: 0.05).isNear(.red), "outside the half-size overlay")
        #expect(try await pixel(in: output, at: 3.5, x: 0.5, y: 0.5).isNear(.red), "after the overlay")
    }

    @Test func anImportPastTheEndExtendsTheVideoOverBlack() async throws {
        let base = temp("base.mp4"), top = temp("top.mp4"), output = temp("out.mp4")
        defer { [base, top, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: base, color: .red, size: canvas, seconds: 2)
        try await writeSolidVideo(to: top, color: .blue, size: canvas, seconds: 1)
        let project = try #require(Project(source: base, duration: 2, canvasSize: canvas, hasAudio: false)
            .importing(ImportedMedia(source: top, duration: 1, size: canvas, hasAudio: false), at: 3)).project
        try await ProjectExporter.export(project, to: output)

        #expect(abs(try await AVURLAsset(url: output).load(.duration).seconds - 4) < 0.2)
        #expect(try await pixel(in: output, at: 1, x: 0.5, y: 0.5).isNear(.red))
        #expect(try await pixel(in: output, at: 2.5, x: 0.5, y: 0.5).isNear(.black), "the gap shows the background")
        #expect(try await pixel(in: output, at: 3.5, x: 0.5, y: 0.5).isNear(.blue))
    }

    @Test func aLaterTrackIsOnTopAndOpacityShowsWhatIsUnderIt() async throws {
        let base = temp("base.mp4"), top = temp("top.mp4"), output = temp("out.mp4")
        defer { [base, top, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: base, color: .red, size: canvas, seconds: 2)
        try await writeSolidVideo(to: top, color: .blue, size: canvas, seconds: 2)
        let (imported, id) = try #require(Project(source: base, duration: 2, canvasSize: canvas, hasAudio: false)
            .importing(ImportedMedia(source: top, duration: 2, size: canvas, hasAudio: false), at: 0))
        let project = try #require(imported.setting(transform: ClipTransform(opacity: 0.5), of: id))
        try await ProjectExporter.export(project, to: output)
        let mixed = try await pixel(in: output, at: 1, x: 0.5, y: 0.5)
        #expect(mixed.r > 80 && mixed.r < 180 && mixed.b > 80 && mixed.b < 180, "half red, half blue, got \(mixed)")
    }

    @Test func aRotatedFileIsDrawnUpright() async throws {
        let base = temp("base.mp4"), top = temp("top.mp4"), output = temp("out.mp4")
        defer { [base, top, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: base, color: .black, size: canvas, seconds: 2)
        // 320 × 180 stored and rotated a quarter turn clockwise: it plays as 180 × 320, its stored top-left
        // marker (green) ending up at the top right.
        try await writeSolidVideo(to: top, color: .red, corner: .green, size: CGSize(width: 320, height: 180), seconds: 2, rotated: true)
        let media = ImportedMedia(source: top, duration: 2, size: CGSize(width: 180, height: 320), hasAudio: false)
        let project = try #require(Project(source: base, duration: 2, canvasSize: canvas, hasAudio: false).importing(media, at: 0)).project
        try await ProjectExporter.export(project, to: output)
        // Fitted by height the picture is 202.5 × 360, centred: spans x from 0.34 to 0.66 of the canvas.
        #expect(try await pixel(in: output, at: 1, x: 0.5, y: 0.5).isNear(.red))
        #expect(try await pixel(in: output, at: 1, x: 0.64, y: 0.05).isNear(.green), "marker at the top right")
        #expect(try await pixel(in: output, at: 1, x: 0.36, y: 0.05).isNear(.red), "not the top left")
        #expect(try await pixel(in: output, at: 1, x: 0.1, y: 0.5).isNear(.black), "pillarbox")
    }

    @Test func soundIsMixedAtItsVolumeAndExtendsTheTimeline() async throws {
        let base = temp("base.mp4"), output = temp("out.mp4")
        defer { [base, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeScreenRecording(to: base, seconds: 2, audio: true)
        let music = temp("tone.mp4")
        defer { try? FileManager.default.removeItem(at: music) }
        try await writeScreenRecording(to: music, seconds: 3, audio: true)
        var project = Project(source: base, duration: 2, canvasSize: CGSize(width: 640, height: 400), hasAudio: true)
        let (imported, id) = try #require(project.importing(ImportedMedia(source: music, duration: 3, size: nil, hasAudio: true), at: 1))
        project = try #require(imported.setting(volume: 0.5, of: id))
        try await ProjectExporter.export(project, to: output)
        let exported = AVURLAsset(url: output)
        #expect(abs(try await exported.load(.duration).seconds - 4) < 0.3)
        #expect(try await !exported.loadTracks(withMediaType: .audio).isEmpty)
    }

    @Test func aCompositionExportsAsAGIFAtTheCanvasSizeAndEstimatesItsSize() async throws {
        let base = temp("base.mp4"), top = temp("top.mp4"), output = temp("out.gif")
        defer { [base, top, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: base, color: .red, size: canvas, seconds: 1)
        try await writeSolidVideo(to: top, color: .green, size: canvas, seconds: 1)
        let project = try #require(Project(source: base, duration: 1, canvasSize: canvas, hasAudio: false)
            .importing(ImportedMedia(source: top, duration: 1, size: canvas, hasAudio: false), at: 1)).project
        let built = try await CompositionBuilder.build(project)
        let result = try await GIFExporter.export(composition: built, to: output, fps: 10, maxWidth: 320)
        #expect(result.frameCount == 20)
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 20)
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)), last = try #require(CGImageSourceCreateImageAtIndex(source, 19, nil))
        #expect(first.width == 320 && first.height == 180)
        let (a, b) = (try average(first), try average(last))
        // Video and GIF palettes both shift flat colours a little.
        #expect(a.isNear(.red, tolerance: 90) && b.isNear(.green, tolerance: 90), "first \(a) last \(b)")
        let estimate = try await GIFExporter.estimatedSize(of: built, fps: 10, maxWidth: 320)
        #expect(estimate > 0)
    }

    private func average(_ image: CGImage) throws -> Color {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Color(r: bytes[0], g: bytes[1], b: bytes[2])
    }

    @Test func aCompositedClipKeepsItsColours() async throws {
        let base = temp("base.mp4"), output = temp("out.mp4")
        defer { [base, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        for color in [Color(r: 200, g: 80, b: 40), Color(r: 40, g: 160, b: 220), Color(r: 128, g: 128, b: 128)] {
            try await writeSolidVideo(to: base, color: color, size: canvas, seconds: 1)
            // A hair off full size so it takes the composite path.
            let plain = Project(source: base, duration: 1, canvasSize: canvas, hasAudio: false)
            let project = try #require(plain.setting(transform: ClipTransform(scale: 1.001), of: plain.main.clips[0].id))
            try await ProjectExporter.export(project, to: output)
            let before = try await pixel(in: base, at: 0.5, x: 0.5, y: 0.5)
            let after = try await pixel(in: output, at: 0.5, x: 0.5, y: 0.5)
            #expect(before.isNear(after, tolerance: 20), "source \(before) became \(after)")
            try? FileManager.default.removeItem(at: base)
        }
    }

    @Test func anAnnotationShowsOnlyWhileItsClipDoes() async throws {
        let base = temp("base.mp4"), output = temp("out.mp4")
        defer { [base, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: base, color: Color(r: 128, g: 128, b: 128), size: canvas, seconds: 3)
        let box = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 160, y: 90, width: 320, height: 180)), color: RGBA(0, 0, 0), fill: RGBA(1, 0, 0), lineWidth: 2)
        let project = Project(source: base, duration: 3, canvasSize: canvas, hasAudio: false).adding(annotation: box, at: 1, duration: 1).project
        try await ProjectExporter.export(project, to: output)
        #expect(try await pixel(in: output, at: 0.5, x: 0.5, y: 0.5).isNear(Color(r: 128, g: 128, b: 128)), "before")
        #expect(try await pixel(in: output, at: 1.5, x: 0.5, y: 0.5).isNear(.red), "during")
        #expect(try await pixel(in: output, at: 1.5, x: 0.05, y: 0.05).isNear(Color(r: 128, g: 128, b: 128)), "outside the box")
        #expect(try await pixel(in: output, at: 2.5, x: 0.5, y: 0.5).isNear(Color(r: 128, g: 128, b: 128)), "after")
    }

    @Test func aHighlightBlendsWithTheVideoUnderIt() async throws {
        let base = temp("base.mp4"), output = temp("out.mp4")
        defer { [base, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: base, color: .blue, size: canvas, seconds: 2)
        let marker = Annotation(kind: .highlight(CGRect(x: 160, y: 90, width: 320, height: 180)), color: RGBA(1, 1, 0), lineWidth: 2)
        let project = Project(source: base, duration: 2, canvasSize: canvas, hasAudio: false).adding(annotation: marker, at: 0, duration: 2).project
        try await ProjectExporter.export(project, to: output)
        // Yellow multiplied over blue leaves almost none of either.
        let inside = try await pixel(in: output, at: 1, x: 0.5, y: 0.5)
        #expect(inside.r < 80 && inside.g < 80 && inside.b < 140, "multiplied, got \(inside)")
        #expect(try await pixel(in: output, at: 1, x: 0.05, y: 0.05).isNear(.blue))
    }

    @Test func aSpotlightDimsOnlyThePicturesUnderIt() async throws {
        let base = temp("base.mp4"), top = temp("top.mp4"), over = temp("over.mp4"), under = temp("under.mp4")
        defer { [base, top, over, under].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: base, color: .red, size: canvas, seconds: 2)
        try await writeSolidVideo(to: top, color: .green, size: canvas, seconds: 2)
        let spotlight = Annotation(kind: .spotlight(CGRect(x: 0, y: 0, width: 64, height: 36), style: SpotlightStyle()), color: RGBA(0, 0, 0), lineWidth: 2)
        let annotated = Project(source: base, duration: 2, canvasSize: canvas, hasAudio: false).adding(annotation: spotlight, at: 0, duration: 2).project
        let (imported, id) = try #require(annotated.importing(ImportedMedia(source: top, duration: 2, size: canvas, hasAudio: false), at: 0))
        let project = try #require(imported.setting(transform: ClipTransform(scale: 0.5), of: id))
        try await ProjectExporter.export(project, to: over)
        #expect(try await pixel(in: over, at: 1, x: 0.5, y: 0.5).isNear(.green), "the picture is over the spotlight")
        let dimmedRed = try await pixel(in: over, at: 1, x: 0.9, y: 0.9)
        #expect(dimmedRed.r < 200 && !dimmedRed.isNear(.red, tolerance: 30), "the recording under it is dimmed, got \(dimmedRed)")

        try await ProjectExporter.export(try #require(project.moving(clip: id, .toBack)), to: under)
        let dimmedGreen = try await pixel(in: under, at: 1, x: 0.5, y: 0.5)
        #expect(!dimmedGreen.isNear(.green, tolerance: 30), "under the spotlight it's dimmed too, got \(dimmedGreen)")
    }

    @Test func liveAnnotationsReplaceTheProjectsWhileTheyAreSet() async throws {
        let base = temp("base.mp4")
        defer { try? FileManager.default.removeItem(at: base) }
        try await writeSolidVideo(to: base, color: Color(r: 128, g: 128, b: 128), size: canvas, seconds: 2)
        let box = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 160, y: 90, width: 320, height: 180)), color: RGBA(0, 0, 0), fill: RGBA(1, 0, 0), lineWidth: 2)
        let (project, id) = Project(source: base, duration: 2, canvasSize: canvas, hasAudio: false).adding(annotation: box, at: 0, duration: 2)
        let built = try await CompositionBuilder.build(project)
        let generator = AVAssetImageGenerator(asset: built.asset)
        generator.videoComposition = built.videoComposition
        func center(at seconds: Double) async throws -> Color {
            let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
            var bytes = [UInt8](repeating: 0, count: 4)
            let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: -Double(image.width) / 2, y: -Double(image.height) / 2, width: Double(image.width), height: Double(image.height)))
            return Color(r: bytes[0], g: bytes[1], b: bytes[2])
        }
        #expect(try await center(at: 0.2).isNear(.red))
        // Hiding it, and drawing a green one in its place for the same time.
        var green = try #require(project.annotationClip(id))
        green.annotation.fill = RGBA(60.0 / 255, 200.0 / 255, 90.0 / 255)
        // Frames near one already drawn may be reused, so each check looks at a time of its own.
        built.live.set(hidden: [id], drawn: [green])
        let seen = try await center(at: 0.8)
        #expect(seen.isNear(.green, tolerance: 90), "got \(seen)")
        built.live.set(hidden: [id], drawn: [])
        #expect(try await center(at: 1.4).isNear(Color(r: 128, g: 128, b: 128)))
        built.live.clear()
        #expect(try await center(at: 1.95).isNear(.red))
    }

    @Test func keyframedOpacityFadesAnOverlayInOverTime() async throws {
        let base = temp("base.mp4"), top = temp("top.mp4"), output = temp("out.mp4")
        defer { [base, top, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: base, color: .red, size: canvas, seconds: 3)
        try await writeSolidVideo(to: top, color: .blue, size: canvas, seconds: 3)
        let (imported, id) = try #require(Project(source: base, duration: 3, canvasSize: canvas, hasAudio: false)
            .importing(ImportedMedia(source: top, duration: 3, size: canvas, hasAudio: false), at: 0))
        // Fade in over the first half second, then fully there.
        let faded = try #require(imported.applying(.fadeIn, toClip: id))
        try await ProjectExporter.export(faded, to: output)
        let start = try await pixel(in: output, at: 0.02, x: 0.5, y: 0.5)
        #expect(start.isNear(.red, tolerance: 70), "starts as the recording, got \(start)")
        let after = try await pixel(in: output, at: 1.5, x: 0.5, y: 0.5)
        #expect(after.isNear(.blue), "then the overlay, got \(after)")
        let middle = try await pixel(in: output, at: 0.25, x: 0.5, y: 0.5)
        #expect(middle.r > 40 && middle.b > 40, "in between it's both, got \(middle)")
    }

    @Test func aKeyframedAnnotationMovesAcrossTheFrame() async throws {
        let base = temp("base.mp4"), output = temp("out.mp4")
        defer { [base, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: base, color: Color(r: 128, g: 128, b: 128), size: canvas, seconds: 3)
        let box = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 20, y: 140, width: 80, height: 80)), color: RGBA(0, 0, 0), fill: RGBA(1, 0, 0), lineWidth: 2)
        var (project, id) = Project(source: base, duration: 3, canvasSize: canvas, hasAudio: false).adding(annotation: box, at: 0, duration: 3)
        // From where it was drawn to 400 points to the right, over the whole clip, with no easing.
        project = try #require(project.togglingKeyframe(.position, ofClip: id, at: 0))
        var values = try #require(project.values(ofClip: id, at: 3))
        values.position = CGSize(width: 400, height: 0)
        project = try #require(project.setting(values: values, ofClip: id, at: 3))
        try await ProjectExporter.export(project, to: output)
        let gray = Color(r: 128, g: 128, b: 128)
        #expect(try await pixel(in: output, at: 0.1, x: 60 / 640, y: 0.5).isNear(.red), "starts at the left")
        #expect(try await pixel(in: output, at: 0.1, x: 460 / 640, y: 0.5).isNear(gray))
        #expect(try await pixel(in: output, at: 2.9, x: 460 / 640, y: 0.5).isNear(.red), "ends at the right")
        #expect(try await pixel(in: output, at: 2.9, x: 60 / 640, y: 0.5).isNear(gray))
    }

    @Test func aRotatedAnnotationTurnsAboutItsCentre() async throws {
        let base = temp("base.mp4"), output = temp("out.mp4")
        defer { [base, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: base, color: Color(r: 128, g: 128, b: 128), size: canvas, seconds: 2)
        // A wide bar across the middle, turned a quarter, becomes a tall one.
        let bar = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 220, y: 160, width: 200, height: 40)), color: RGBA(0, 0, 0), fill: RGBA(1, 0, 0), lineWidth: 1)
        var (project, id) = Project(source: base, duration: 2, canvasSize: canvas, hasAudio: false).adding(annotation: bar, at: 0, duration: 2)
        var values = try #require(project.values(ofClip: id, at: 1))
        values.rotation = .pi / 2
        project = try #require(project.setting(values: values, ofClip: id, at: 1))
        try await ProjectExporter.export(project, to: output)
        let gray = Color(r: 128, g: 128, b: 128)
        #expect(try await pixel(in: output, at: 1, x: 0.5, y: 0.5 - 80 / 360).isNear(.red), "above the centre, where the tall bar reaches")
        #expect(try await pixel(in: output, at: 1, x: 0.5 + 80 / 640, y: 0.5).isNear(gray), "no longer to the side")
    }

    @Test func aStyledClipExportsWithRoundedCornersAndAShadowBelowIt() async throws {
        let base = temp("base.mp4"), top = temp("top.mp4"), output = temp("out.mp4")
        defer { [base, top, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: base, color: Color(r: 128, g: 128, b: 128), size: canvas, seconds: 1)
        try await writeSolidVideo(to: top, color: .green, size: canvas, seconds: 1)
        let (imported, id) = try #require(Project(source: base, duration: 1, canvasSize: canvas, hasAudio: false)
            .importing(ImportedMedia(source: top, duration: 1, size: canvas, hasAudio: false), at: 0))
        // At half scale the clip sits from 160 to 480 across and 90 to 270 down, its radius and shadow halved with it.
        var project = try #require(imported.setting(transform: ClipTransform(scale: 0.5), of: id))
        project = try #require(project.setting(cornerRadius: 80, of: id))
        project = try #require(project.setting(style: ObjectStyle(shadow: ShadowPreset.float.shadow(scale: 1)), of: id))
        try await ProjectExporter.export(project, to: output)
        #expect(try await pixel(in: output, at: 0.5, x: 0.5, y: 0.5).isNear(.green))
        // The encode shifts the grey a little, so the shadow is measured against grey well clear of it.
        let clear = try await pixel(in: output, at: 0.5, x: 0.05, y: 0.5)
        #expect(try await pixel(in: output, at: 0.5, x: 162 / 640, y: 92 / 360).isNear(clear, tolerance: 20), "the rounded corner shows what's under it")
        let above = try await pixel(in: output, at: 0.5, x: 0.5, y: 78 / 360), below = try await pixel(in: output, at: 0.5, x: 0.5, y: 282 / 360)
        #expect(above.isNear(clear, tolerance: 4), "nothing above, got \(above) by \(clear)")
        #expect(Int(below.r) < Int(clear.r) - 8, "a shadow below, got \(below) by \(clear)")
    }

    @Test func aStyledAnnotationCastsItsShadowInTheVideo() async throws {
        let base = temp("base.mp4"), output = temp("out.mp4")
        defer { [base, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: base, color: Color(r: 128, g: 128, b: 128), size: canvas, seconds: 1)
        var box = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 220, y: 130, width: 200, height: 100)), color: RGBA(1, 1, 1), fill: RGBA(1, 1, 1), lineWidth: 2)
        box.style = ObjectStyle(shadow: ShadowPreset.float.shadow(scale: 1))
        let project = Project(source: base, duration: 1, canvasSize: canvas, hasAudio: false).adding(annotation: box, at: 0, duration: 1).project
        try await ProjectExporter.export(project, to: output)
        let above = try await pixel(in: output, at: 0.5, x: 0.5, y: 118 / 360), below = try await pixel(in: output, at: 0.5, x: 0.5, y: 242 / 360)
        #expect(Int(below.r) < Int(above.r) - 8, "darker below than above, got \(below) and \(above)")
    }

    @Test func volumeKeyframesBecomeRampsInTheAudioMix() async throws {
        let base = temp("base.mp4")
        defer { try? FileManager.default.removeItem(at: base) }
        try await writeScreenRecording(to: base, seconds: 2, audio: true)
        var project = Project(source: base, duration: 2, canvasSize: CGSize(width: 640, height: 400), hasAudio: true)
        let sound = project.tracks[1].clips[0].id
        project = try #require(project.togglingKeyframe(.volume, ofClip: sound, at: 0))
        var values = try #require(project.values(ofClip: sound, at: 2))
        values.volume = 0
        project = try #require(project.setting(values: values, ofClip: sound, at: 2))
        let mix = try #require(try await CompositionBuilder.build(project).audioMix)
        let parameters = try #require(mix.inputParameters.first)
        var from: Float = 0, to: Float = 0
        var range = CMTimeRange.zero
        #expect(parameters.getVolumeRamp(for: CMTime(seconds: 1, preferredTimescale: 600), startVolume: &from, endVolume: &to, timeRange: &range))
        #expect(from < 1 && from > 0.3 && to < from, "halfway down, got \(from) to \(to)")
        #expect(range.duration.seconds <= 0.11)
    }
}
