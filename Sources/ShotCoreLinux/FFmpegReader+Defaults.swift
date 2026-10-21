import Foundation

// ShotCore's calls that read, cut and join video take a `VideoReader` or `VideoAssembler`. On Linux they're ffmpeg's, so
// these give ShotCLI and the tests each call without one, as ShotCoreApple's do on a Mac.

extension MediaProbe {
    /// What ffprobe finds in `url`: how long it plays, the size of its picture as it plays, and whether it has sound.
    public static func probe(_ url: URL) async throws -> ImportedMedia {
        try await probe(url, reader: FFmpegReader())
    }
}

extension KeyFrameExtractor {
    public static func frames(of url: URL, at times: [Double], maxWidth: Int) async throws -> [Frame] {
        try await frames(of: url, at: times, maxWidth: maxWidth, reader: FFmpegReader())
    }
}

extension Waveform {
    public static func load(_ url: URL) async throws -> Waveform? {
        try await load(url, reader: FFmpegReader())
    }
}

extension VideoTrimmer {
    public static func estimatedSize(of input: URL, range: TrimRange, cuts: CutList = CutList(), speed: Double = 1, muted: Bool = false) async throws -> Int {
        try await estimatedSize(of: input, range: range, cuts: cuts, speed: speed, muted: muted, reader: FFmpegReader())
    }

    @discardableResult
    public static func trim(_ input: URL, range: TrimRange, cuts: CutList = CutList(), speed: Double = 1, muted: Bool = false, to output: URL, as fileType: String? = nil) async throws -> Bool {
        try await trim(input, range: range, cuts: cuts, speed: speed, muted: muted, to: output, as: fileType, assembler: FFmpegAssembler())
    }
}

extension VideoConcatenator {
    public static func concatenate(_ segments: [URL], audio: [SegmentAudio] = [], to output: URL, muting muted: CutList = CutList()) async throws {
        try await concatenate(segments, audio: audio, to: output, muting: muted, assembler: FFmpegAssembler())
    }
}
