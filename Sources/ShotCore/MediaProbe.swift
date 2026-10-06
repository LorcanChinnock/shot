import AVFoundation

public enum MediaProbe {
    public enum ProbeError: LocalizedError {
        case unreadable(String)
        case empty(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let name): "Cannot open \(name)"
            case .empty(let name): "\(name) has no video or sound"
            }
        }
    }

    /// What AVFoundation finds in `url`: how long it plays, the size of its picture as it plays, and whether it has sound.
    public static func probe(_ url: URL) async throws -> ImportedMedia {
        let asset = AVURLAsset(url: url)
        let name = url.lastPathComponent
        let duration: Double, video: [AVAssetTrack], audio: [AVAssetTrack]
        do {
            duration = try await asset.load(.duration).seconds
            video = try await asset.loadTracks(withMediaType: .video)
            audio = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw ProbeError.unreadable(name)
        }
        guard duration.isFinite, duration > 0, !video.isEmpty || !audio.isEmpty else {
            throw ProbeError.empty(name)
        }
        var size: CGSize?
        if let track = video.first {
            let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
            let shown = natural.applying(transform)
            size = CGSize(width: abs(shown.width), height: abs(shown.height))
        }
        return ImportedMedia(source: url, duration: duration, size: size, hasAudio: !audio.isEmpty)
    }
}
