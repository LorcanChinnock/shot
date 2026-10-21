import AVFoundation
import Foundation

/// The Mac's `VideoWriter`: the project's composition, drawn by its compositor, through an export session.
public struct AVVideoWriter: VideoWriter {
    public init() {}

    public func write(_ project: Project, to output: URL, as fileType: String, canvasType: any Canvas.Type, codec: (_ frameRate: Int) -> VideoCodec) async throws {
        let fileType = AVFileType(rawValue: fileType)
        let built = try await CompositionBuilder.build(project, canvasType: canvasType)
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
