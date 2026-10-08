import AppKit
import AVFoundation
import ImageIO
import Observation
import ShotCore

final class Thumbnail: @unchecked Sendable {
    let image: NSImage
    let duration: Double?
    let bytes: Int

    init(image: CGImage, duration: Double?) {
        self.image = NSImage(cgImage: image, size: .zero)
        self.duration = duration
        bytes = image.bytesPerRow * image.height
    }
}

/// The gallery's decoded previews, keeping only the most recently shown. Tiles read them from here rather than
/// holding them, so dropping one frees it however many tiles the grid keeps built.
@MainActor
final class ThumbnailStore {
    @MainActor
    @Observable
    final class Slot {
        fileprivate(set) var thumbnail: Thumbnail?
    }

    private var slots: [GalleryItem: Slot] = [:]
    private var recent = RecentlyUsed<GalleryItem>(limit: 200 * 1024 * 1024)

    func slot(for item: GalleryItem) -> Slot {
        if let slot = slots[item] {
            return slot
        }
        let slot = Slot()
        slots[item] = slot
        return slot
    }

    func load(_ item: GalleryItem) async {
        let slot = slot(for: item)
        if slot.thumbnail == nil {
            let made = await Thumbnails.make(item)
            guard !Task.isCancelled, slots[item] === slot else {
                return
            }
            slot.thumbnail = made
        }
        guard let thumbnail = slot.thumbnail else {
            return
        }
        for dropped in recent.use(item, cost: thumbnail.bytes) {
            slots[dropped]?.thumbnail = nil
        }
    }

    func removeAll() {
        slots.values.forEach { $0.thumbnail = nil }
        slots.removeAll()
        recent.removeAll()
    }
}

enum Thumbnails {
    private static let maxPixels = 640

    /// Decodes off the main actor; cancelling the caller skips the decode if it hasn't started yet.
    static func make(_ item: GalleryItem) async -> Thumbnail? {
        let task = Task.detached(priority: .utility) { await decode(item) }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func decode(_ item: GalleryItem) async -> Thumbnail? {
        guard !Task.isCancelled else {
            return nil
        }
        switch item.kind {
        case .image, .gif:
            guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { Thumbnail(image: $0, duration: nil) }
        case .video:
            let asset = AVURLAsset(url: item.url)
            let duration = (try? await asset.load(.duration))?.seconds
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
            let time = CMTime(seconds: min(1, (duration ?? 0) / 2), preferredTimescale: 600)
            guard let image = try? await generator.image(at: time).image else {
                return nil
            }
            return Thumbnail(image: image, duration: duration)
        }
    }
}
