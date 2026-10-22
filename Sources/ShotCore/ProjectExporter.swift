import AVFoundation
import Foundation

public enum ProjectExporter {
    public enum ExportError: LocalizedError {
        case failed
        case unsupportedFileType

        public var errorDescription: String? {
            switch self {
            case .failed: String(localized: "Couldn't export the video")
            case .unsupportedFileType: String(localized: "Can't write this kind of video")
            }
        }
    }

    /// The largest canvas H.264 export keeps above 30 fps at; past it the export halves the frame rate.
    static let largestH264Canvas = CGSize(width: 2560, height: 1600)

    /// Whether the export is HEVC rather than H.264: only when H.264 would drop frames. It caps every canvas at 60 fps,
    /// and halves the rate of one larger than `largestH264Canvas`, such as a 60 fps Retina recording.
    static func usesHEVC(canvas: CGSize, frameRate: Int) -> Bool {
        RecordingFrameRate.usesHEVC(fps: frameRate)
            || frameRate > 30 && canvas.width * canvas.height > largestH264Canvas.width * largestH264Canvas.height
    }

    /// Writes the project to `output`, replacing it, as `fileType`, drawn at the canvas size and re-encoded as H.264, or
    /// HEVC when `usesHEVC`.
    public static func export(_ project: Project, to output: URL, as fileType: AVFileType = .mp4) async throws {
        try await AVVideoWriter.write(project, to: output, as: fileType) { frameRate in
            usesHEVC(canvas: project.outputRect.size, frameRate: frameRate) ? .hevc : .h264
        }
    }

    /// Roughly how many bytes `export` writes: a typical H.264 rate for the canvas, and AAC for any sound.
    public static func estimatedSize(of project: Project) -> Int {
        let pixels = Double(project.outputRect.width * project.outputRect.height)
        let hasSound = project.tracks.contains { $0.kind == .audio && !$0.isMuted && !$0.clips.isEmpty }
        let bitRate = pixels * 30 * 0.07 + (hasSound ? 128_000 : 0)
        return Int((bitRate * project.duration / 8).rounded())
    }
}
