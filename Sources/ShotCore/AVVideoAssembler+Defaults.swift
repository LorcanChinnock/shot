import AVFoundation
import Foundation

// ShotCore's calls that cut and join video take a `VideoAssembler`. On a Mac it's always AVFoundation, so these give the
// app, ShotCLI and the tests each call as it was, without one, and with the file type as an `AVFileType`.

extension VideoTrimmer {
    @discardableResult
    public static func trim(_ input: URL, range: TrimRange, cuts: CutList = CutList(), speed: Double = 1, muted: Bool = false, to output: URL, as fileType: AVFileType? = nil) async throws -> Bool {
        try await trim(input, range: range, cuts: cuts, speed: speed, muted: muted, to: output, as: fileType?.rawValue, assembler: AVVideoAssembler())
    }
}

extension VideoConcatenator {
    public static func concatenate(_ segments: [URL], audio: [SegmentAudio] = [], to output: URL, muting muted: CutList = CutList()) async throws {
        try await concatenate(segments, audio: audio, to: output, muting: muted, assembler: AVVideoAssembler())
    }
}
