import AVFoundation
import Foundation

/// Draws a project and encodes it to a file: its pictures composited frame by frame with its annotations, and its audio
/// tracks mixed, through the project's composition and an export session. `ProjectExporter` picks the codec and calls
/// it for the work.
public enum AVVideoWriter {
    /// Writes `project` to `output`, replacing it, as `fileType`, drawn at its output size with its annotations. `codec` picks the encoding from the frame rate it's drawn at, its fastest picture's. Throws
    /// `ProjectExporter.ExportError` when it can't write that type or the export fails, and
    /// `CompositionBuilder.BuildError` when a clip can't be read.
    public static func write(_ project: Project, to output: URL, as fileType: AVFileType, codec: (_ frameRate: Int) -> VideoCodec) async throws {
        let built = try await CompositionBuilder.build(project)
        let frameRate = Int((1 / built.videoComposition.frameDuration.seconds).rounded())
        let preset = codec(frameRate) == .hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let export = AVAssetExportSession(asset: built.asset, presetName: preset) else {
            throw ProjectExporter.ExportError.failed
        }
        guard export.supportedFileTypes.contains(fileType) else {
            throw ProjectExporter.ExportError.unsupportedFileType
        }
        export.videoComposition = built.videoComposition
        export.audioMix = built.audioMix
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        try await export.export(to: output, as: fileType)
    }
}
