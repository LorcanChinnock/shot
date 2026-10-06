import AppKit
import AVFoundation
import ImageIO
import ShotCore

final class Thumbnail: @unchecked Sendable {
    let image: NSImage
    let duration: Double?

    init(image: NSImage, duration: Double?) {
        self.image = image
        self.duration = duration
    }
}

/// Small previews for the gallery, kept until memory is needed elsewhere.
enum Thumbnails {
    private static let maxPixels = 640
    nonisolated(unsafe) private static let cache = NSCache<NSString, Thumbnail>()

    static func thumbnail(for item: GalleryItem) async -> Thumbnail? {
        let key = "\(item.url.path)|\(item.date.timeIntervalSinceReferenceDate)|\(item.bytes)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let made = await Task.detached(priority: .utility) { await make(item) }.value
        if let made {
            cache.setObject(made, forKey: key)
        }
        return made
    }

    private static func make(_ item: GalleryItem) async -> Thumbnail? {
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
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { Thumbnail(image: NSImage(cgImage: $0, size: .zero), duration: nil) }
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
            return Thumbnail(image: NSImage(cgImage: image, size: .zero), duration: duration)
        }
    }
}
