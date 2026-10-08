import CoreImage
import Darwin
import Foundation
import Testing
@testable import ShotCore

extension Tag {
    @Tag static var perf: Self
}

/// Times the pure paths that have budgets in `docs/performance.md`. `make test` skips this suite and `make perf` runs it alone,
/// one test at a time, so other tests don't skew the timings. Budgets are 2× the baseline measured on the reference Mac,
/// which leaves room for a noisy CI runner but still fails on a regression that does the work again on every call.
@Suite(.serialized, .tags(.perf)) struct PerfTests {
    @Test func flatteningAndEncodingA5KCaptureStaysInBudget() throws {
        let doc = EditorDocument(base: try gradient(width: 5120, height: 2880), annotations: twentyAnnotations(in: CGSize(width: 5120, height: 2880), special: true))
        let time = try median {
            let image = try #require(AnnotationRenderer.flatten(doc))
            _ = try #require(ImageCodec.data(from: image, scale: 2))
        }
        try check(time, budget: .milliseconds(Budget.flattenAndEncode), "Flatten + encode")
    }

    @Test func drawingAnnotationsOverAVideoFrameStaysInBudget() throws {
        let canvas = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let items = twentyAnnotations(in: canvas.size, special: false).map { AnnotationFrame.Item(annotation: $0) }
        let frame = CIImage(color: .gray).cropped(to: canvas)
        let context = CIContext()
        // One cache for the whole run, as the compositor keeps one for an export or a preview.
        let cache = OverlayCache()
        let frames = 30
        let time = try median {
            for _ in 0..<frames {
                _ = AnnotationFrame.apply(items, to: frame, canvas: canvas, context: context, cache: cache)
            }
        }
        try check(time / frames, budget: .microseconds(Budget.overlayFrame), "Overlay per frame")
    }

    @Test func exportingA20SecondGIFKeepsMemoryFlat() async throws {
        let video = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-perf.mp4")
        let gif = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-perf.gif")
        defer { [video, gif].forEach { try? FileManager.default.removeItem(at: $0) } }
        try await writeSolidVideo(to: video, color: .green, corner: .red, size: CGSize(width: 1920, height: 1080), seconds: 20)
        let sampler = FootprintSampler()
        sampler.start()
        try await GIFExporter.export(videoURL: video, to: gif)
        let growth = sampler.stop()
        let budget = Budget.gifExportMegabytes << 20
        print("GIF export peak memory growth: \(growth >> 20) MB, budget \(Budget.gifExportMegabytes) MB")
        #expect(growth <= budget, "GIF export grew memory by \(growth >> 20) MB, over its \(Budget.gifExportMegabytes) MB budget")
    }

    @Test func groupingTheGalleryStaysInBudget() throws {
        let now = Date()
        let items = (0..<1500).map { index in
            GalleryItem(url: URL(fileURLWithPath: "/shots/Shot \(index).png"), kind: index % 5 == 0 ? .video : .image, date: now.addingTimeInterval(Double(-index) * 3 * 3600), bytes: 1000 + index)
        }
        let time = try median {
            let visible = Gallery.visible(items, filter: .all, sort: .newest, query: "")
            #expect(!Gallery.sections(visible, sort: .newest, now: now).isEmpty)
        }
        try check(time, budget: .milliseconds(Budget.galleryGrouping), "Gallery grouping")
    }
}

/// Twice the baselines in `docs/performance.md`; change both together.
private enum Budget {
    static let flattenAndEncode = 544
    static let overlayFrame = 22
    /// The baseline is under 1 MB, so this is a floor above allocator noise rather than 2×. Holding every frame, as #230
    /// did, costs about 280 MB here.
    static let gifExportMegabytes = 32
    static let galleryGrouping = 3
}

/// The median time of five runs of `body`, after one untimed run that warms caches.
private func median(_ body: () throws -> Void) throws -> Duration {
    try body()
    let clock = ContinuousClock()
    let times = try (0..<5).map { _ in try clock.measure(body) }
    return times.sorted()[2]
}

private func check(_ time: Duration, budget: Duration, _ name: String) throws {
    print("\(name): \(time.formatted(.units(allowed: [.milliseconds, .microseconds], fractionalPart: .show(length: 2)))), budget \(budget)")
    #expect(time <= budget, "\(name) took \(time), over its \(budget) budget")
}

/// A smooth gradient, so PNG encoding does real work rather than compressing a flat colour to nothing.
private func gradient(width: Int, height: Int) throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let colors = [CGColor(srgbRed: 0.1, green: 0.3, blue: 0.8, alpha: 1), CGColor(srgbRed: 0.9, green: 0.6, blue: 0.2, alpha: 1)] as CFArray
    let gradient = try #require(CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: nil))
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
    return try #require(context.makeImage())
}

/// Twenty annotations of mixed kinds spread over `size`. With `special`, two are a blur and a spotlight, which read the
/// picture under them.
private func twentyAnnotations(in size: CGSize, special: Bool) -> [Annotation] {
    let cell = CGSize(width: size.width / 5, height: size.height / 4)
    return (0..<20).map { index in
        let origin = CGPoint(x: CGFloat(index % 5) * cell.width, y: CGFloat(index / 5) * cell.height)
        let box = CGRect(origin: origin, size: cell).insetBy(dx: cell.width * 0.15, dy: cell.height * 0.15)
        let color = RGBA.presets[index % RGBA.presets.count]
        if special, index == 7 {
            return Annotation(kind: .blur(box), color: color, lineWidth: 4)
        }
        if special, index == 12 {
            return Annotation(kind: .spotlight(box, style: SpotlightStyle()), color: color, lineWidth: 4)
        }
        switch index % 4 {
        case 0: return Annotation(kind: .arrow(from: CGPoint(x: box.minX, y: box.maxY), to: CGPoint(x: box.maxX, y: box.minY)), color: color, lineWidth: 6)
        case 1: return Annotation(kind: .shape(.rectangle, rect: box), color: color, lineWidth: 6)
        case 2: return Annotation(kind: .shape(.ellipse, rect: box), color: color, fill: color, lineWidth: 6)
        default: return Annotation(kind: .text("Annotation \(index)", origin: box.origin, fontSize: cell.height * 0.15), color: color, lineWidth: 4)
        }
    }
}

/// Samples this process's memory footprint every few milliseconds on its own thread, keeping the largest growth.
private final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var baseline = 0
    private var peak = 0
    private var thread: Thread?

    func start() {
        baseline = footprint()
        peak = baseline
        running = true
        let thread = Thread { [self] in
            while lock.withLock({ running }) {
                let now = footprint()
                lock.withLock { peak = max(peak, now) }
                usleep(5000)
            }
        }
        self.thread = thread
        thread.start()
    }

    /// Stops sampling and returns the largest growth over the footprint at `start`, in bytes.
    func stop() -> Int {
        lock.withLock { running = false }
        let now = footprint()
        return lock.withLock { max(peak, now) - baseline }
    }

    private func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        precondition(result == KERN_SUCCESS, "task_info failed: \(result)")
        return Int(info.phys_footprint)
    }
}
