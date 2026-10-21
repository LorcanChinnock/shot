import Foundation

/// A kind of video file, by its uniform type identifier, as `AVFileType` names one.
public struct VideoFileType: RawRepresentable, Hashable, Sendable {
    public static let mp4 = VideoFileType(rawValue: "public.mpeg-4")
    public static let mov = VideoFileType(rawValue: "com.apple.quicktime-movie")

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// How a written video's pictures are compressed.
public enum VideoCodec: Sendable {
    case h264
    case hevc
}

/// Draws a project and encodes it to a file: its pictures composited frame by frame with its annotations, and its audio
/// tracks mixed. `ProjectExporter` picks the codec and calls it for the work. `AVVideoWriter` is the one there is;
/// ShotCore code takes one as `writer`.
public protocol VideoWriter: Sendable {
    /// Writes `project` to `output`, replacing it, as `fileType`, a uniform type identifier such as `public.mpeg-4`, drawn
    /// at its output size with its annotations on `canvasType` canvases. `codec` picks the encoding from the frame rate
    /// it's drawn at, its fastest picture's. Throws `ProjectExporter.ExportError` when it can't write that type or the
    /// export fails, and `CompositionBuilder.BuildError` when a clip can't be read.
    func write(_ project: Project, to output: URL, as fileType: String, canvasType: any Canvas.Type, codec: (_ frameRate: Int) -> VideoCodec) async throws
}
