import Foundation
import Testing
@testable import ShotCoreLinux

/// Times what Linux does in plain Swift where a Mac has Core Image, against budgets in `docs/performance.md`. Unlike the
/// Mac's PerfTests, it runs with the other Linux tests on every pull request, so it keeps the fastest of only a few runs.
@Suite(.serialized) struct PerfTests {
    @Test func blurringA2560By1600CaptureStaysInBudget() throws {
        let capture = BitmapImage(try gradient(width: 2560, height: 1600))
        let effects = PortableEffects()
        var fastest = Duration.seconds(Int64.max)
        for _ in 0..<3 {
            fastest = min(fastest, try ContinuousClock().measure {
                _ = try #require(effects.blurred(capture, radius: 20))
            })
        }
        let budget = Duration.milliseconds(2500)
        print("Blur 2560×1600: \(fastest), budget \(budget)")
        #expect(fastest <= budget, "Blur took \(fastest), over its \(budget) budget")
    }

    @Test func composingA1920By1080FrameStaysInBudget() throws {
        let size = CGSize(width: 1920, height: 1080), inset = CGSize(width: 1280, height: 720)
        let base = Project(source: URL(fileURLWithPath: "/base.mp4"), duration: 2, canvasSize: size, hasAudio: false)
        var (project, id) = try #require(base.importing(ImportedMedia(source: URL(fileURLWithPath: "/clip.mp4"), duration: 2, size: inset, hasAudio: false), at: 0))
        project = try #require(project.setting(transform: ClipTransform(offset: CGSize(width: 120, height: -60), scale: 0.6, rotation: 0.1), of: id))
        project = try #require(project.setting(cornerRadius: 48, of: id))
        project = try #require(project.setting(style: ObjectStyle(shadow: ShadowPreset.float.shadow(scale: 2), border: Border(kind: .solid, lineWidth: 8)), of: id))
        var box = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 1200, y: 120, width: 500, height: 260)), color: RGBA(1, 1, 1), fill: RGBA(1, 1, 1), lineWidth: 6)
        box.style = ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 2))
        for annotation in [
            Annotation(kind: .arrow(from: CGPoint(x: 200, y: 900), to: CGPoint(x: 900, y: 600)), color: RGBA(0.9, 0.1, 0.1), lineWidth: 16),
            box,
            Annotation(kind: .highlight(CGRect(x: 200, y: 400, width: 700, height: 90)), color: RGBA(1, 0.92, 0.2), lineWidth: 1),
        ] {
            project = project.adding(annotation: annotation, at: 0, duration: 2).project
        }
        let compositor = PortableCompositor(project: project, canvasType: CairoCanvas.self)
        let shown = compositor.pictures(at: 1)
        let pictures = try Dictionary(uniqueKeysWithValues: shown.map { shown in
            (shown.clip.id, BitmapImage(try gradient(width: Int(shown.clip.size.width), height: Int(shown.clip.size.height))))
        })
        var fastest = Duration.seconds(Int64.max)
        for _ in 0..<3 {
            fastest = min(fastest, try ContinuousClock().measure {
                _ = try #require(compositor.frame(at: 1, pictures: pictures))
            })
        }
        let budget = Duration.milliseconds(650)
        print("Compose 1920×1080: \(fastest), budget \(budget)")
        #expect(fastest <= budget, "Composing a frame took \(fastest), over its \(budget) budget")
    }

    @Test(.enabled(if: hasFFmpeg, "ffmpeg isn't installed")) func writing10SecondsOf1080pStaysInBudget() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mp4")
        _ = try await Subprocess.output(try FFmpegTools.find().ffmpeg, [
            "-v", "error", "-nostdin", "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=30:duration=10", "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", source.path,
        ])
        var project = Project(source: source, duration: 10, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: false)
        let arrow = Annotation(kind: .arrow(from: CGPoint(x: 200, y: 900), to: CGPoint(x: 900, y: 600)), color: RGBA(0.9, 0.1, 0.1), lineWidth: 16)
        project = project.adding(annotation: arrow, at: 2, duration: 4).project
        let output = folder.appendingPathComponent("out.mp4")
        let took = try await ContinuousClock().measure {
            try await FFmpegWriter().write(project, to: output, as: "public.mpeg-4", canvasType: CairoCanvas.self) { _ in .h264 }
        }
        let budget = Duration.seconds(80)
        print("Write 10 s of 1920×1080 at 30 fps: \(took), budget \(budget)")
        #expect(took <= budget, "Writing took \(took), over its \(budget) budget")
    }
}

/// Opaque, with detail in every channel.
private func gradient(width: Int, height: Int) throws -> Bitmap {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            (pixels[i], pixels[i + 1], pixels[i + 2]) = (UInt8(x * 255 / width), UInt8(y * 255 / height), UInt8((x + y) % 256))
        }
    }
    return try #require(Bitmap(width: width, height: height, pixels: Data(pixels)))
}
