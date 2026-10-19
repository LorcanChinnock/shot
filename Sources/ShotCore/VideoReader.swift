import Foundation

/// One frame `VideoReader.readFrames` was asked for.
public struct VideoFrame {
    /// The time asked for, as given.
    public let requestedTime: Double
    /// When the frame decoded is shown, in seconds from the start, and its picture; the error when it didn't decode.
    public let decoded: Result<(time: Double, image: PlatformImage), any Error>

    public init(requestedTime: Double, decoded: Result<(time: Double, image: PlatformImage), any Error>) {
        self.requestedTime = requestedTime
        self.decoded = decoded
    }
}

/// Something that plays, read a frame at a time: a file, or a project as it's drawn.
public protocol VideoFrames: Sendable {
    /// How long it plays, in seconds.
    var duration: Double { get }
    /// The size of its picture as it plays; `nil` when it has no video.
    var size: CGSize? { get }
    /// Decodes the frames at `times` as `VideoReader.readFrames` does, handing each to `body` in the order of `times`.
    func readFrames(at times: [Double], maxSize: CGSize, tolerance: Double?, _ body: (VideoFrame) throws -> Void) async throws
}

/// Reads video and audio files, and projects as they're drawn: what they hold, their frames and their sound. It reports
/// facts and leaves the decisions to its callers, such as `MediaProbe`, `KeyFrameExtractor`, `Waveform`, `VideoTrimmer`'s
/// estimate and `GIFExporter`. ShotCoreApple's `AVVideoReader` is the Mac's; ShotCore code takes one as `reader`.
public protocol VideoReader: Sendable {
    /// How long `url` plays, the size of its first video track's picture as it plays (`nil` without one), and whether it
    /// has sound, as the file says, unchecked. Throws when the file can't be read.
    func info(of url: URL) async throws -> ImportedMedia
    /// The average bit rates of `url`'s video tracks and of its audio tracks, each summed, in bits a second.
    func bitRates(of url: URL) async throws -> (video: Double, audio: Double)
    /// When the sync frame at or before each of `times` is shown in `url`'s first video track, or the time itself where
    /// the file can't say; `nil` when it has no video or can't find sync frames at all.
    func syncTimes(atOrBefore times: [Double], in url: URL) async throws -> [Double]?
    /// Decodes the frames of `url` at `times`, upright, at most `maxSize` (0 leaves that side free) and never enlarged,
    /// and hands each to `body` in the order of `times`. A frame may come from up to `tolerance` seconds either side of its
    /// time; `nil` lets the reader pick whatever's quickest.
    func readFrames(of url: URL, at times: [Double], maxSize: CGSize, tolerance: Double?, _ body: (VideoFrame) throws -> Void) async throws
    /// `project` as it's drawn, at its output size with its annotations on `canvasType` canvases. Throws
    /// `CompositionBuilder.BuildError` when a clip can't be read.
    func frames(of project: Project, canvasType: any Canvas.Type) async throws -> any VideoFrames
    /// Decodes `url`'s first audio track as mono 32-bit float samples at `sampleRate`, handing them to `body` in order, a
    /// chunk at a time. Reading may block the calling thread until each chunk is decoded.
    func readMonoSamples(of url: URL, sampleRate: Double, _ body: ([Float]) throws -> Void) async throws
}
