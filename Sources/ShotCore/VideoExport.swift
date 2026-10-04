import CoreGraphics

public enum VideoExportFormat: String, CaseIterable, Sendable {
    case mp4, gif

    public var fileExtension: String { rawValue }
}

/// What the video editor's Export writes; the trim and cuts come from its `TrimRange` and `CutList`.
public struct VideoExportOptions: Equatable, Sendable {
    public static let gifFrameRates = [10, 15, 24]
    /// Stands for the recording's own width in `gifWidths`.
    public static let originalWidth = 0
    public static let gifWidths = [480, 720, 1080, originalWidth]
    public static let speeds: [Double] = [1, 1.5, 2]

    public var format: VideoExportFormat
    public var gifFrameRate: Int
    public var gifWidth: Int
    /// Drops the audio from an MP4; a GIF never has any.
    public var muted: Bool
    public var speed: Double

    public init(format: VideoExportFormat = .mp4, gifFrameRate: Int = 15, gifWidth: Int = 720, muted: Bool = false, speed: Double = 1) {
        self.format = format
        self.gifFrameRate = gifFrameRate
        self.gifWidth = gifWidth
        self.muted = muted
        self.speed = speed
    }

    /// `nil` keeps the recording's width.
    public var gifMaxWidth: CGFloat? { gifWidth == Self.originalWidth ? nil : CGFloat(gifWidth) }

    /// Describes a GIF made with these options, for Settings.
    public var gifSummary: String {
        let width = gifWidth == Self.originalWidth ? "full width" : "up to \(gifWidth) px wide"
        return "\(gifFrameRate) fps, \(width), first \(Int(GIFExporter.maxDuration)) seconds."
    }

    /// How long `range`, less `cuts`, plays for at this speed.
    public func outputLength(of range: TrimRange, cuts: CutList = CutList()) -> Double { cuts.keptLength(in: range) / speed }
}
