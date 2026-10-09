import AVFoundation
import CoreGraphics

/// What the video editor writes and how: picked once from the edit and the options, then run or estimated.
///
/// An edit that's only a trim and cuts of the recording is cut from the file, and passes through without re-encoding when
/// it can; anything more is drawn from the project. A drawn MP4 ignores the speed, which the export bar doesn't offer for one.
public enum VideoExportPlan: Equatable, Sendable {
    /// The recording's `range` less `cuts`. `fileType` `nil` keeps the recording's own.
    case trimmed(source: URL, range: TrimRange, cuts: CutList, speed: Double, muted: Bool, fileType: AVFileType?)
    case trimmedGIF(source: URL, range: TrimRange, cuts: CutList, fps: Double, maxWidth: CGFloat?, speed: Double)
    /// The whole project, drawn at the canvas size and re-encoded.
    case composite(Project, fileType: AVFileType)
    case compositeGIF(Project, fps: Double, maxWidth: CGFloat?, speed: Double)

    /// Export: `project` with `options`' format, speed and sound.
    public init(project: Project, options: VideoExportOptions) {
        let fps = Double(options.gifFrameRate)
        guard let trim = project.trimEdit else {
            var drawn = project
            if options.muted {
                for index in drawn.tracks.indices where drawn.tracks[index].kind == .audio {
                    drawn.tracks[index].isMuted = true
                }
            }
            switch options.format {
            case .mp4: self = .composite(drawn, fileType: .mp4)
            case .gif: self = .compositeGIF(drawn, fps: fps, maxWidth: options.gifMaxWidth, speed: options.speed)
            }
            return
        }
        switch options.format {
        case .mp4:
            self = .trimmed(source: trim.source, range: trim.range, cuts: trim.cuts, speed: options.speed, muted: options.muted, fileType: .mp4)
        case .gif:
            self = .trimmedGIF(source: trim.source, range: trim.range, cuts: trim.cuts, fps: fps, maxWidth: options.gifMaxWidth, speed: options.speed)
        }
    }

    /// Copy and Save: `project` at its own speed and with its sound, in the recording's format, or `fileType` when it has to
    /// be drawn.
    public static func copy(of project: Project, as fileType: AVFileType) -> VideoExportPlan {
        guard let trim = project.trimEdit else {
            return .composite(project, fileType: fileType)
        }
        return .trimmed(source: trim.source, range: trim.range, cuts: trim.cuts, speed: 1, muted: false, fileType: nil)
    }

    /// What a run wrote.
    public struct Outcome: Equatable, Sendable {
        /// The frames in a GIF; `nil` for a video.
        public var frameCount: Int?
        /// True when a GIF stopped at `GIFExporter.maxDuration`.
        public var truncated: Bool
        /// True when a trimmed video was copied without re-encoding.
        public var passthrough: Bool
    }

    /// Writes the export to `output`. `progress` hears from 0 to 1 while a GIF is written.
    @discardableResult
    public func run(to output: URL, progress: @Sendable (Double) -> Void = { _ in }) async throws -> Outcome {
        switch self {
        case let .trimmed(source, range, cuts, speed, muted, fileType):
            let passthrough = try await VideoTrimmer.trim(source, range: range, cuts: cuts, speed: speed, muted: muted, to: output, as: fileType)
            return Outcome(frameCount: nil, truncated: false, passthrough: passthrough)
        case let .trimmedGIF(source, range, cuts, fps, maxWidth, speed):
            let result = try await GIFExporter.export(videoURL: source, to: output, range: range, cuts: cuts, fps: fps, maxWidth: maxWidth, speed: speed, progress: progress)
            return Outcome(frameCount: result.frameCount, truncated: result.truncated, passthrough: false)
        case let .composite(project, fileType):
            try await ProjectExporter.export(project, to: output, as: fileType)
            return Outcome(frameCount: nil, truncated: false, passthrough: false)
        case let .compositeGIF(project, fps, maxWidth, speed):
            let built = try await CompositionBuilder.build(project)
            let result = try await GIFExporter.export(composition: built, to: output, fps: fps, maxWidth: maxWidth, speed: speed, progress: progress)
            return Outcome(frameCount: result.frameCount, truncated: result.truncated, passthrough: false)
        }
    }

    /// Roughly how many bytes `run` writes.
    public func estimate() async throws -> Int {
        switch self {
        case let .trimmed(source, range, cuts, speed, muted, _):
            try await VideoTrimmer.estimatedSize(of: source, range: range, cuts: cuts, speed: speed, muted: muted)
        case let .trimmedGIF(source, range, cuts, fps, maxWidth, speed):
            try await GIFExporter.estimatedSize(of: source, range: range, cuts: cuts, fps: fps, maxWidth: maxWidth, speed: speed)
        case let .composite(project, _):
            ProjectExporter.estimatedSize(of: project)
        case let .compositeGIF(project, fps, maxWidth, speed):
            try await GIFExporter.estimatedSize(of: CompositionBuilder.build(project), fps: fps, maxWidth: maxWidth, speed: speed)
        }
    }
}

extension VideoExportPlan {
    /// Which of the four ways it writes, for logs.
    public enum Kind: String, Sendable {
        case trimmed, trimmedGIF, composite, compositeGIF
    }

    public var kind: Kind {
        switch self {
        case .trimmed: .trimmed
        case .trimmedGIF: .trimmedGIF
        case .composite: .composite
        case .compositeGIF: .compositeGIF
        }
    }
}
