import AVFoundation
import Foundation

// ShotCore's calls that read video take a `VideoReader`. On a Mac it's always AVFoundation, so these give the app,
// ShotCLI and the tests each call as it was, without one. ImageIOCodec+Defaults.swift and CGCanvas+Defaults.swift pass
// it to the calls that also code images or draw.

extension MediaProbe {
    /// What AVFoundation finds in `url`: how long it plays, the size of its picture as it plays, and whether it has sound.
    public static func probe(_ url: URL) async throws -> ImportedMedia {
        try await probe(url, reader: AVVideoReader())
    }
}

extension KeyFrameExtractor {
    public static func changeTimes(in url: URL, duration: Double, count: Int) async throws -> [Double] {
        try await changeTimes(in: url, duration: duration, count: count, reader: AVVideoReader())
    }

    public static func frames(of url: URL, at times: [Double], maxWidth: Int) async throws -> [Frame] {
        try await frames(of: url, at: times, maxWidth: maxWidth, reader: AVVideoReader())
    }
}

extension Waveform {
    public static func load(_ url: URL) async throws -> Waveform? {
        try await load(url, reader: AVVideoReader())
    }
}

extension VideoTrimmer {
    public static func estimatedSize(of input: URL, range: TrimRange, cuts: CutList = CutList(), speed: Double = 1, muted: Bool = false) async throws -> Int {
        try await estimatedSize(of: input, range: range, cuts: cuts, speed: speed, muted: muted, reader: AVVideoReader())
    }
}

extension GIFExporter {
    @discardableResult
    public static func export(
        videoURL: URL,
        to outputURL: URL,
        range: TrimRange? = nil,
        cuts: CutList = CutList(),
        fps: Double = 12,
        maxWidth: CGFloat? = 720,
        speed: Double = 1,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> Result {
        try await export(videoURL: videoURL, to: outputURL, range: range, cuts: cuts, fps: fps, maxWidth: maxWidth, speed: speed, reader: AVVideoReader(), progress: progress)
    }

    /// Writes the whole of `composition` as a looping GIF, as `export(videoURL:…)` does for a file.
    @discardableResult
    public static func export(
        composition: ProjectComposition,
        to outputURL: URL,
        fps: Double = 12,
        maxWidth: CGFloat? = 720,
        speed: Double = 1,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> Result {
        try await export(CompositionFrames(composition), to: outputURL, fps: fps, maxWidth: maxWidth, speed: speed, progress: progress)
    }

    public static func estimatedSize(of videoURL: URL, range: TrimRange? = nil, cuts: CutList = CutList(), fps: Double, maxWidth: CGFloat?, speed: Double = 1) async throws -> Int {
        try await estimatedSize(of: videoURL, range: range, cuts: cuts, fps: fps, maxWidth: maxWidth, speed: speed, reader: AVVideoReader())
    }

    public static func estimatedSize(of composition: ProjectComposition, fps: Double, maxWidth: CGFloat?, speed: Double = 1) async throws -> Int {
        try await estimatedSize(of: CompositionFrames(composition), fps: fps, maxWidth: maxWidth, speed: speed)
    }
}
