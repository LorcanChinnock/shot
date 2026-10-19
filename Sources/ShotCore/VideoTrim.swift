import Foundation

public enum VideoTrimmer {
    public enum TrimError: LocalizedError {
        case unsupportedFileType
        case exportFailed
        case nothingLeft

        public var errorDescription: String? {
            switch self {
            case .unsupportedFileType: shotLocalized("Can't write this kind of video")
            case .exportFailed: shotLocalized("Couldn't export the trimmed video")
            case .nothingLeft: shotLocalized("The cuts leave nothing to export")
            }
        }
    }

    /// Writes `range` of `input`, less `cuts`, to `output`, replacing `output`, through `assembler`, in `fileType`, a
    /// uniform type identifier, or else the input's own. `speed` 2 plays it in half the time with every frame kept;
    /// `muted` leaves the audio out. Copies the video samples as they are when it can; returns false when it had to
    /// re-encode.
    @discardableResult
    public static func trim(_ input: URL, range: TrimRange, cuts: CutList = CutList(), speed: Double = 1, muted: Bool = false, to output: URL, as fileType: String? = nil, assembler: any VideoAssembler) async throws -> Bool {
        let kept = cuts.kept(in: range)
        guard !kept.isEmpty else {
            throw TrimError.nothingLeft
        }
        return try await assembler.trim(input, kept: kept, speed: speed, muted: muted, to: output, as: fileType)
    }

    /// Roughly how many bytes `trim` writes with the same arguments, from the tracks' average bit rates as `reader` reads them.
    public static func estimatedSize(of input: URL, range: TrimRange, cuts: CutList = CutList(), speed: Double = 1, muted: Bool = false, reader: any VideoReader) async throws -> Int {
        let rates = try await reader.bitRates(of: input)
        let kept = cuts.kept(in: range)
        let videoLength = try await reader.syncTimes(atOrBefore: kept.map(\.start), in: input).map { copiedLength(of: kept, syncTimes: $0) }
        return estimatedBytes(videoBitRate: rates.video, audioBitRate: rates.audio, videoLength: videoLength, length: cuts.keptLength(in: range), speed: speed, muted: muted)
    }

    /// Every video frame is kept at any speed, so the video's size depends only on the source length it
    /// copies, `videoLength` (`length` when nil); the audio plays for `length / speed`.
    static func estimatedBytes(videoBitRate: Double, audioBitRate: Double, videoLength: Double? = nil, length: Double, speed: Double, muted: Bool) -> Int {
        let audio = muted ? 0 : audioBitRate * length / speed
        return Int(((videoBitRate * (videoLength ?? length) + audio) / 8).rounded())
    }

    /// Seconds of video a passthrough copy of `kept` writes. Frames depend on the sync frame before
    /// them, so each section reaches back to its entry in `syncTimes`.
    static func copiedLength(of kept: [TrimRange], syncTimes: [Double]) -> Double {
        zip(kept, syncTimes).reduce(0) { $0 + $1.0.end - min($1.1, $1.0.start) }
    }
}
