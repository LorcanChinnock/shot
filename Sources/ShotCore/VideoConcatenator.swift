import AVFoundation

public enum VideoConcatenator {
    public enum ConcatError: Error {
        case noSegments
        case exportFailed
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

public enum ControlPlacement {
    /// Below the region if there is room, else above it, else inside its bottom edge; all in AppKit space.
    public static func origin(for size: CGSize, region: CGRect, visible: CGRect, gap: CGFloat = 14, margin: CGFloat = 8) -> CGPoint {
        var origin = CGPoint(x: region.midX - size.width / 2, y: region.minY - gap - size.height)
        if origin.y < visible.minY + margin {
            let above = region.maxY + gap
            if above + size.height <= visible.maxY - margin {
                origin.y = above
            } else {
                origin.y = max(region.minY, visible.minY) + 20
            }
        }
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
        return origin
    }
}
