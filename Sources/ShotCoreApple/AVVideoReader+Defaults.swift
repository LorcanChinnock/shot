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
