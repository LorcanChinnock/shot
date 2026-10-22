import AVFoundation
import Foundation

/// One frame `AVVideoReader.readFrames` was asked for.
public struct VideoFrame {
    /// The time asked for, as given.
    public let requestedTime: Double
    /// When the frame decoded is shown, in seconds from the start, and its picture; the error when it didn't decode.
    public let decoded: Result<(time: Double, image: CGImage), any Error>

    public init(requestedTime: Double, decoded: Result<(time: Double, image: CGImage), any Error>) {
        self.requestedTime = requestedTime
        self.decoded = decoded
    }
}

/// Something that plays, read a frame at a time: a file, or a project as its compositor draws it.
public struct VideoFrames {
    let asset: AVAsset
    let videoComposition: AVVideoComposition?
    /// How long it plays, in seconds.
    public let duration: Double
    /// The size of its picture as it plays; `nil` when it has no video.
    public let size: CGSize?

    /// The file at `url`.
    public init(url: URL) async throws {
        let media = try await AVVideoReader.info(of: url)
        asset = AVURLAsset(url: url)
        videoComposition = nil
        duration = media.duration
        size = media.size
    }

    /// A project's composition, drawn by its compositor.
    public init(_ composition: ProjectComposition) async throws {
        asset = composition.asset
        videoComposition = composition.videoComposition
        duration = try await composition.asset.load(.duration).seconds
        size = try await composition.asset.loadTracks(withMediaType: .video).isEmpty ? nil : composition.videoComposition.renderSize
    }

    /// Decodes the frames at `times` as `AVVideoReader.readFrames` does, handing each to `body` in the order of `times`.
    func readFrames(at times: [Double], maxSize: CGSize, tolerance: Double?, _ body: (VideoFrame) throws -> Void) async throws {
        try await AVVideoReader.readFrames(of: asset, drawnBy: videoComposition, at: times, maxSize: maxSize, tolerance: tolerance, body)
    }
}
