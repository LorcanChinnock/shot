import Foundation
import ShotCore

/// The menu's newest captures and their small pictures. It reads the save folder and decodes off the main thread, and keeps
/// what it found, so opening the menu shows the last pictures at once and swaps in anything newer when it arrives.
@MainActor
final class RecentCapturesStore {
    struct Entry {
        let item: GalleryItem
        var thumbnail: Thumbnail?
    }

    /// Enough for a 60 × 40 pt thumbnail of a tall or wide capture at 2×.
    private static let maxPixels = 240

    private(set) var entries: [Entry] = []
    var onChange: (() -> Void)?
    private var task: Task<Void, Never>?

    func refresh() {
        let folder = Preferences().saveFolder
        task?.cancel()
        task = Task { [weak self] in
            let newest = await Task.detached(priority: .userInitiated) { RecentCaptures.newest(Gallery.items(in: folder)) }.value
            guard let self, !Task.isCancelled else {
                return
            }
            if newest != entries.map(\.item) {
                let decoded = Dictionary(entries.map { ($0.item, $0.thumbnail) }, uniquingKeysWith: { first, _ in first })
                entries = newest.map { Entry(item: $0, thumbnail: decoded[$0] ?? nil) }
                onChange?()
            }
            for entry in entries where entry.thumbnail == nil {
                let thumbnail = await Thumbnails.make(entry.item, maxPixels: Self.maxPixels)
                guard !Task.isCancelled, let index = entries.firstIndex(where: { $0.item == entry.item }) else {
                    return
                }
                entries[index].thumbnail = thumbnail
                onChange?()
            }
        }
    }
}
