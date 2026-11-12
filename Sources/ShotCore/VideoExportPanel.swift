import Foundation

/// What the video editor's Export panel shows for a set of options: its groups in order, whether Speed can change, and
/// how long the file it writes plays for.
public enum VideoExportPanel {
    /// The panel's groups, top to bottom.
    public enum Group: Equatable, Sendable {
        case format, frameRate, width, mute, speed
    }

    /// A GIF picks its frames per second and width and has no sound; an MP4 can leave its sound out.
    public static func groups(for format: VideoExportFormat) -> [Group] {
        switch format {
        case .gif: [.format, .frameRate, .width, .speed]
        case .mp4: [.format, .mute, .speed]
        }
    }

    /// An MP4 drawn from the project (with imports, annotations or transforms) ignores the speed, so Speed is locked.
    public static func speedIsLocked(format: VideoExportFormat, isComposite: Bool) -> Bool {
        isComposite && format == .mp4
    }

    /// How long the export plays for, given the edit's `keptLength` in seconds.
    public struct Length: Equatable, Sendable {
        public var seconds: Double
        /// True when a GIF keeps only its first `GIFExporter.maxDuration` seconds.
        public var truncated: Bool
    }

    public static func length(of keptLength: Double, options: VideoExportOptions, isComposite: Bool) -> Length {
        let speed = speedIsLocked(format: options.format, isComposite: isComposite) ? 1 : options.speed
        let played = keptLength / max(speed, 0.01)
        guard options.format == .gif, played > GIFExporter.maxDuration else {
            return Length(seconds: played, truncated: false)
        }
        return Length(seconds: GIFExporter.maxDuration, truncated: true)
    }

    /// "480", or "Full" for the recording's own width.
    public static func widthLabel(_ width: Int) -> String {
        width == VideoExportOptions.originalWidth ? String(localized: "Full", comment: "Export panel, GIF width: keep the video's own width.") : "\(width)"
    }

    /// "1×", "1.5×".
    public static func speedLabel(_ speed: Double) -> String {
        (speed.rounded() == speed ? "\(Int(speed))" : "\(speed)") + "×"
    }
}
