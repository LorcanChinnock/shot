import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum GIFExporter {
    /// Frames are held one at a time, but longer input needs a streaming exporter to stay responsive.
    public static let maxDuration: Double = 60

    public struct Result: Sendable {
        public let frameCount: Int
        public let truncated: Bool
    }

    public enum ExportError: LocalizedError {
        case noVideoTrack
        case cannotCreateDestination
        case finalizeFailed

        public var errorDescription: String? {
            switch self {
            case .noVideoTrack: "The recording has no video track"
            case .cannotCreateDestination: "Could not create the GIF file"
            case .finalizeFailed: "Could not finish writing the GIF"
            }
        }
    }

    public static func export(
        videoURL: URL,
        to outputURL: URL,
        fps: Double = 12,
        maxWidth: CGFloat = 720,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> Result {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let size = naturalSize.applying(transform)
        let sourceWidth = abs(size.width), sourceHeight = abs(size.height)
        let width = min(maxWidth, sourceWidth)
        let height = (sourceHeight * width / sourceWidth).rounded()

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width, height: height)
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let usedDuration = min(duration, maxDuration)
        let count = max(1, Int((usedDuration * fps).rounded(.down)))
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw ExportError.cannotCreateDestination
        }
        let fileProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        CGImageDestinationSetProperties(destination, fileProperties)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary

        for index in 0..<count {
            try Task.checkCancellation()
            let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
            let (image, _) = try await generator.image(at: time)
            CGImageDestinationAddImage(destination, image, frameProperties)
            progress(Double(index + 1) / Double(count))
        }
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.finalizeFailed
        }
        return Result(frameCount: count, truncated: duration > maxDuration)
    }
}
