import Foundation

public enum MediaProbe {
    public enum ProbeError: LocalizedError {
        case unreadable(String)
        case empty(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let name): shotLocalized("Can't open \(name)")
            case .empty(let name): shotLocalized("\(name) has no video or sound")
            }
        }
    }

    /// What `reader` finds in `url`: how long it plays, the size of its picture as it plays, and whether it has sound.
    public static func probe(_ url: URL, reader: any VideoReader) async throws -> ImportedMedia {
        let name = url.lastPathComponent
        let media: ImportedMedia
        do {
            media = try await reader.info(of: url)
        } catch {
            throw ProbeError.unreadable(name)
        }
        guard media.duration.isFinite, media.duration > 0, media.size != nil || media.hasAudio else {
            throw ProbeError.empty(name)
        }
        return media
    }
}
