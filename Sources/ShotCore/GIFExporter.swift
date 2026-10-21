import Foundation

/// Which source frames a GIF uses and how big they are.
public struct GIFFramePlan: Equatable, Sendable {
    public let size: CGSize
    public let frameCount: Int
    /// How long each frame stays on screen.
    public let frameDelay: Double
    /// True when the range plays for longer than `GIFExporter.maxDuration` and only the start is kept.
    public let truncated: Bool
    private let range: TrimRange
    private let cuts: CutList
    private let step: Double

    /// Scales down to `maxWidth` but never up; `speed` 2 plays the range, less `cuts`, in half the time.
    public init(sourceSize: CGSize, range: TrimRange, cuts: CutList = CutList(), fps: Double, maxWidth: CGFloat?, speed: Double = 1) {
        let sourceWidth = abs(sourceSize.width), sourceHeight = abs(sourceSize.height)
        let width = min(maxWidth ?? sourceWidth, sourceWidth)
        size = CGSize(width: width, height: sourceWidth == 0 ? 0 : (sourceHeight * width / sourceWidth).rounded())
        let length = cuts.keptLength(in: range) / speed
        frameCount = max(1, Int((min(length, GIFExporter.maxDuration) * fps).rounded(.down)))
        frameDelay = 1 / fps
        truncated = length > GIFExporter.maxDuration
        self.range = range
        self.cuts = cuts
        step = speed / fps
    }

    /// A GIF stores delays in whole hundredths of a second, so 1/15 s can't be written as it is. Frames alternate between
    /// the two nearest values so the GIF still plays for the right length overall.
    public func delay(ofFrame index: Int) -> Double {
        let end = (Double(index + 1) * 100 * frameDelay).rounded()
        let start = (Double(index) * 100 * frameDelay).rounded()
        return (end - start) / 100
    }

    public func sourceTime(ofFrame index: Int) -> Double {
        cuts.sourceTime(at: Double(index) * step, in: range)
    }

    /// Up to `count` frames from the middle of equal slots, for estimating the file size.
    public func sampleFrames(_ count: Int) -> [Int] {
        let count = max(1, min(count, frameCount))
        return (0..<count).map { Int((Double($0) + 0.5) * Double(frameCount) / Double(count)) }
    }
}

public enum GIFExporter {
    /// Only the first this many seconds of longer input are kept.
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
            case .noVideoTrack: String(localized: "The recording has no video track")
            case .cannotCreateDestination: String(localized: "Couldn't create the GIF file")
            case .finalizeFailed: String(localized: "Couldn't finish writing the GIF")
            }
        }
    }

    /// Writes `range` (the whole video when nil), less `cuts`, of the video at `videoURL` as a looping GIF
    /// at `fps`, scaled down to `maxWidth`, drawing each frame on a `canvasType` canvas.
    @discardableResult
    public static func export(
        videoURL: URL,
        to outputURL: URL,
        range: TrimRange? = nil,
        cuts: CutList = CutList(),
        fps: Double = 12,
        maxWidth: CGFloat? = 720,
        speed: Double = 1,
        canvasType: any Canvas.Type,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> Result {
        try await export(
            VideoFrames(url: videoURL), to: outputURL, range: range, cuts: cuts, fps: fps, maxWidth: maxWidth, speed: speed, canvasType: canvasType,
            progress: progress
        )
    }

    /// Writes `range` (all of it when nil), less `cuts`, of `frames`, a file or a drawn project, as `export(videoURL:…)` does.
    @discardableResult
    public static func export(
        _ frames: VideoFrames,
        to outputURL: URL,
        range: TrimRange? = nil,
        cuts: CutList = CutList(),
        fps: Double = 12,
        maxWidth: CGFloat? = 720,
        speed: Double = 1,
        canvasType: any Canvas.Type,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> Result {
        let plan = try plan(of: frames, range: range, cuts: cuts, fps: fps, maxWidth: maxWidth, speed: speed)
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil), let file = try? FileHandle(forWritingTo: outputURL) else {
            throw ExportError.cannotCreateDestination
        }
        var finished = false
        // A cancelled or failed export leaves no half-written GIF behind.
        defer {
            try? file.close()
            if !finished {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }
        let writer = GIFStreamWriter(canvasType: canvasType) { try file.write(contentsOf: $0) }
        let times = (0..<plan.frameCount).map(plan.sourceTime(ofFrame:))
        var index = 0
        try await frames.readFrames(at: times, maxSize: plan.size, tolerance: tolerance(fps)) { frame in
            try Task.checkCancellation()
            try writer.add(frame.decoded.get().image, delay: plan.delay(ofFrame: index))
            index += 1
            progress(Double(index) / Double(plan.frameCount))
        }
        try writer.finish()
        finished = true
        return Result(frameCount: plan.frameCount, truncated: plan.truncated)
    }

    /// Roughly how many bytes `export` writes with the same arguments.
    /// Each frame stores only what changed since the previous one, so this encodes a few pairs of
    /// neighbouring frames spread over the range: one frame alone costs a whole frame, and the pair
    /// costs that plus a typical change.
    public static func estimatedSize(
        of videoURL: URL, range: TrimRange? = nil, cuts: CutList = CutList(), fps: Double, maxWidth: CGFloat?, speed: Double = 1, canvasType: any Canvas.Type
    ) async throws -> Int {
        try await estimatedSize(of: VideoFrames(url: videoURL), range: range, cuts: cuts, fps: fps, maxWidth: maxWidth, speed: speed, canvasType: canvasType)
    }

    public static func estimatedSize(
        of frames: VideoFrames, range: TrimRange? = nil, cuts: CutList = CutList(), fps: Double, maxWidth: CGFloat?, speed: Double = 1, canvasType: any Canvas.Type
    ) async throws -> Int {
        let plan = try plan(of: frames, range: range, cuts: cuts, fps: fps, maxWidth: maxWidth, speed: speed)
        let anchors = plan.sampleFrames(estimateSamples).map { max(0, min($0, plan.frameCount - 2)) }
        var whole = 0, change = 0
        for anchor in anchors {
            try Task.checkCancellation()
            let writer = GIFStreamWriter(canvasType: canvasType) { _ in }
            let indices = Array(anchor..<min(anchor + 2, plan.frameCount))
            var single = 0, read = 0
            try await frames.readFrames(at: indices.map(plan.sourceTime(ofFrame:)), maxSize: plan.size, tolerance: tolerance(fps)) { frame in
                try writer.add(frame.decoded.get().image, delay: plan.delay(ofFrame: indices[read]))
                if read == 0 { single = writer.bytesWritten }
                read += 1
            }
            whole += single
            change += writer.bytesWritten - single
        }
        return extrapolate(wholeFrameBytes: whole / anchors.count, changeBytes: change / anchors.count, totalFrames: plan.frameCount)
    }

    static func extrapolate(wholeFrameBytes: Int, changeBytes: Int, totalFrames: Int) -> Int {
        wholeFrameBytes + changeBytes * max(0, totalFrames - 1)
    }

    private static func plan(of frames: VideoFrames, range: TrimRange?, cuts: CutList, fps: Double, maxWidth: CGFloat?, speed: Double) throws -> GIFFramePlan {
        guard let size = frames.size else {
            throw ExportError.noVideoTrack
        }
        return GIFFramePlan(sourceSize: size, range: range ?? TrimRange(duration: frames.duration), cuts: cuts, fps: fps, maxWidth: maxWidth, speed: speed)
    }

    /// A frame may come from up to half a frame either side of its time.
    private static func tolerance(_ fps: Double) -> Double {
        0.5 / fps
    }
}
