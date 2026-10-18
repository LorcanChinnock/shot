import AVFoundation
import CoreImage
import Testing
@testable import ShotCore

// Temporary experiment for #414: does a plain player also miss the frame a paused seek lands on after a scrub?
// Prints one EXPERIMENT line per attempt and never fails. Not for merging.
@Suite(.serialized) struct ScrubExperiment {
    @Test(arguments: 0..<20) func plainPlayer(attempt: Int) async throws {
        try await run(compositor: false, attempt: attempt)
    }

    @Test(arguments: 0..<20) func shotCompositor(attempt: Int) async throws {
        try await run(compositor: true, attempt: attempt)
    }

    private func run(compositor useCompositor: Bool, attempt: Int) async throws {
        let size = CGSize(width: 640, height: 360)
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-base.mp4")
        defer { try? FileManager.default.removeItem(at: base) }
        try await writeSolidVideo(to: base, color: .green, size: size, seconds: 4)
        let item: AVPlayerItem
        if useCompositor {
            let stroke = (0...20).map { CGPoint(x: 40 + CGFloat($0) * 28, y: 180 + 40 * sin(CGFloat($0) / 3)) }
            let marker = Annotation(kind: .marker(stroke), color: RGBA(1, 1, 0), lineWidth: 24)
            let project = Project(source: base, duration: 4, canvasSize: size, hasAudio: false).adding(annotation: marker, at: 0, duration: 4).project
            let built = try await CompositionBuilder.build(project)
            item = await AVPlayerItem(asset: built.asset)
            await MainActor.run { item.videoComposition = built.videoComposition }
        } else {
            item = await AVPlayerItem(asset: AVURLAsset(url: base))
        }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        item.add(output)
        let player = await AVPlayer(playerItem: item)
        await player.play()
        let shot = await MainActor.run { item.customVideoCompositor as? ProjectCompositor }
        shot?.requests.start()
        for step in 0..<30 {
            await player.seek(to: CMTime(seconds: Double(step % 15) * 0.25, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { _ in })
            try await Task.sleep(for: .milliseconds(16))
        }
        await player.pause()
        let target = CMTime(seconds: 2, preferredTimescale: 600)
        let sought = await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        var shown = CMTime.invalid
        var seen: [Double] = []
        let start = ContinuousClock.now
        var arrivedAfter: Duration?
        while arrivedAfter == nil, ContinuousClock.now - start < .seconds(12) {
            if output.copyPixelBuffer(forItemTime: target, itemTimeForDisplay: &shown) != nil {
                seen.append(shown.seconds)
                if shown == target {
                    arrivedAfter = ContinuousClock.now - start
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let variant = useCompositor ? "compositor" : "plain"
        let result = arrivedAfter.map { "arrived after \($0)" } ?? "never arrived"
        let tail = shot.map { " events after the last cancel: \(String(describing: $0.requests.events.split(separator: .cancelAll).last.map(Array.init) ?? []))" } ?? ""
        print("EXPERIMENT variant=\(variant) attempt=\(attempt) sought=\(sought) \(result) seen=\(seen.count) item=\(item.currentTime().seconds)\(tail)")
    }
}
