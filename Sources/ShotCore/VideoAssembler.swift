import Foundation

/// Cuts and joins video files without drawing them: trims, retimes and concatenates, mixing audio tracks where it has to,
/// and copies the video samples as they are when it can. `VideoTrimmer` and `VideoConcatenator` check what they're asked
/// and call it for the work. `AVVideoAssembler` is the one there is; ShotCore code takes one as `assembler`.
public protocol VideoAssembler: Sendable {
    /// Writes the `kept` sections of `input`, of which there's at least one, end to end to `output`, replacing it, as
    /// `fileType`, a uniform type identifier such as `public.mpeg-4`, or else the input's own type. `speed` 2 plays it in
    /// half the time with every frame kept; `muted` leaves the audio out. Returns false when it had to re-encode the video.
    /// Throws `VideoTrimmer.TrimError` when it can't write that type or the export fails.
    func trim(_ input: URL, kept: [TrimRange], speed: Double, muted: Bool, to output: URL, as fileType: String?) async throws -> Bool
    /// Joins `segments`, of which there's at least one, end to end at `output`, which doesn't exist, as MP4 without
    /// re-encoding the video, leaving the segments in place. `muted` holds stretches of the joined recording, in seconds,
    /// that become silent. With `audio`, one per segment, the segments' own audio is replaced by a mix of those files,
    /// and only the microphone is muted.
    func concatenate(_ segments: [URL], audio: [VideoConcatenator.SegmentAudio], to output: URL, muting muted: CutList) async throws
}
