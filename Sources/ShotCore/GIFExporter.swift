import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Which source frames a GIF uses and how big they are.
public struct GIFFramePlan: Equatable, Sendable {
    public let size: CGSize
    public let frameCount: Int
    /// How long each frame stays on screen.
    public let frameDelay: Double
    /// True when the range plays for longer than `GIFExporter.maxDuration` and only the start is kept.
    public let truncated: Bool
    private let start: Double
    private let step: Double

    /// Scales down to `maxWidth` but never up; `speed` 2 plays the range in half the time.
    public init(sourceSize: CGSize, range: TrimRange, fps: Double, maxWidth: CGFloat?, speed: Double = 1) {
        let sourceWidth = abs(sourceSize.width), sourceHeight = abs(sourceSize.height)
        let width = min(maxWidth ?? sourceWidth, sourceWidth)
        size = CGSize(width: width, height: sourceWidth == 0 ? 0 : (sourceHeight * width / sourceWidth).rounded())
        let length = range.length / speed
        frameCount = max(1, Int((min(length, GIFExporter.maxDuration) * fps).rounded(.down)))
        frameDelay = 1 / fps
        truncated = length > GIFExporter.maxDuration
        start = range.start
        step = speed / fps
    }

    public func sourceTime(ofFrame index: Int) -> Double {
        start + Double(index) * step
    }

    /// Up to `count` frames from the middle of equal slots, for estimating the file size.
    public func sampleFrames(_ count: Int) -> [Int] {
        let count = max(1, min(count, frameCount))
        return (0..<count).map { Int((Double($0) + 0.5) * Double(frameCount) / Double(count)) }
    }
}

public enum GIFExporter {
    /// Frames are held one at a time, but longer input needs a streaming exporter to stay responsive.
    public static let maxDuration: Double = 60
    /// Places in the range sampled to estimate a GIF's size.
    public static let estimateSamples = 6

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

    /// Writes `range` (the whole video when nil) as a looping GIF at `fps`, scaled down to `maxWidth`.
    @discardableResult
    public static func export(
        videoURL: URL,
        to outputURL: URL,
        range: TrimRange? = nil,
        fps: Double = 12,
        maxWidth: CGFloat? = 720,
        speed: Double = 1,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> Result {
        let (generator, plan) = try await prepare(videoURL: videoURL, range: range, fps: fps, maxWidth: maxWidth, speed: speed)
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.gif.identifier as CFString, plan.frameCount, nil) else {
            throw ExportError.cannotCreateDestination
        }
        try await write(plan, from: generator, to: destination, progress: progress)
        return Result(frameCount: plan.frameCount, truncated: plan.truncated)
    }

    /// Roughly how many bytes `export` writes with the same arguments.
    /// ImageIO stores only what changed since the previous frame, so this encodes a few pairs of
    /// neighbouring frames spread over the range: one frame alone costs a whole frame, and the pair
    /// costs that plus a typical change.
    public static func estimatedSize(of videoURL: URL, range: TrimRange? = nil, fps: Double, maxWidth: CGFloat?, speed: Double = 1) async throws -> Int {
        let (generator, plan) = try await prepare(videoURL: videoURL, range: range, fps: fps, maxWidth: maxWidth, speed: speed)
        let anchors = plan.sampleFrames(estimateSamples).map { max(0, min($0, plan.frameCount - 2)) }
        var whole = 0, change = 0
        for anchor in anchors {
            try Task.checkCancellation()
            var images: [CGImage] = []
            for index in anchor..<min(anchor + 2, plan.frameCount) {
                images.append(try await generator.image(at: CMTime(seconds: plan.sourceTime(ofFrame: index), preferredTimescale: 600)).image)
            }
            let single = try encodedSize(images.prefix(1), delay: plan.frameDelay)
            whole += single
            change += images.count > 1 ? try encodedSize(images, delay: plan.frameDelay) - single : 0
        }
        return extrapolate(wholeFrameBytes: whole / anchors.count, changeBytes: change / anchors.count, totalFrames: plan.frameCount)
    }

    static func extrapolate(wholeFrameBytes: Int, changeBytes: Int, totalFrames: Int) -> Int {
        wholeFrameBytes + changeBytes * max(0, totalFrames - 1)
    }

    private static func encodedSize(_ images: some Collection<CGImage>, delay: Double) throws -> Int {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString, images.count, nil) else {
            throw ExportError.cannotCreateDestination
        }
        CGImageDestinationSetProperties(destination, fileProperties)
        for image in images {
            CGImageDestinationAddImage(destination, image, frameProperties(delay: delay))
        }
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.finalizeFailed
        }
        return data.length
    }

    private static var fileProperties: CFDictionary { [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary }

    private static func frameProperties(delay: Double) -> CFDictionary {
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
    }

    private static func prepare(videoURL: URL, range: TrimRange?, fps: Double, maxWidth: CGFloat?, speed: Double) async throws -> (AVAssetImageGenerator, GIFFramePlan) {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let plan = GIFFramePlan(sourceSize: naturalSize.applying(transform), range: range ?? TrimRange(duration: duration), fps: fps, maxWidth: maxWidth, speed: speed)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = plan.size
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return (generator, plan)
    }

    private static func write(_ plan: GIFFramePlan, from generator: AVAssetImageGenerator, to destination: CGImageDestination, progress: @Sendable (Double) -> Void) async throws {
        CGImageDestinationSetProperties(destination, fileProperties)
        let frameProperties = frameProperties(delay: plan.frameDelay)

        for index in 0..<plan.frameCount {
            try Task.checkCancellation()
            let time = CMTime(seconds: plan.sourceTime(ofFrame: index), preferredTimescale: 600)
            let (image, _) = try await generator.image(at: time)
            CGImageDestinationAddImage(destination, image, frameProperties)
            progress(Double(index + 1) / Double(plan.frameCount))
        }
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.finalizeFailed
        }
    }
}
