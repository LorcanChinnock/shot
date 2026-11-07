import Foundation

/// The captures the menu bar menu's Recent row shows: the newest few in the save folder, each with a short badge.
public enum RecentCaptures {
    /// How many thumbnails fit across the 290 pt menu.
    public static let limit = 4

    /// The newest captures in `items`, newest first, one for each capture and its edited versions (`Gallery.latest`).
    public static func newest(_ items: [GalleryItem]) -> [GalleryItem] {
        Gallery.latest(in: items, limit: limit)
    }

    /// The thumbnail's badge: the file type for a picture, such as PNG or GIF, and the length for a recording.
    /// A recording has none until its length has been read.
    public static func badge(for item: GalleryItem, duration: Double?) -> String? {
        switch item.kind {
        case .image:
            let type = item.url.pathExtension.uppercased()
            return type.isEmpty ? nil : type
        case .gif:
            return "GIF"
        case .video:
            return duration.map(Gallery.duration)
        }
    }
}
