import AVFoundation

public enum VideoConcatenator {
    public enum ConcatError: LocalizedError {
        case noSegments
        case exportFailed

        public var errorDescription: String? {
            switch self {
            case .noSegments: "Nothing was recorded"
            case .exportFailed: "Could not join the recording's segments"
            }
        }
    }

    /// Joins recording segments end to end without re-encoding; one segment is moved as is.
    public static func concatenate(_ segments: [URL], to output: URL) async throws {
        guard let first = segments.first else {
            throw ConcatError.noSegments
        }
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        if segments.count == 1 {
            try FileManager.default.moveItem(at: first, to: output)
            return
        }
        let composition = AVMutableComposition()
        var cursor = CMTime.zero
        for url in segments {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            try await composition.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: asset, at: cursor)
            cursor = cursor + duration
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw ConcatError.exportFailed
        }
        try await export.export(to: output, as: .mp4)
        for url in segments {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
