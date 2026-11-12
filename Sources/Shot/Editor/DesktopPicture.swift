import AppKit
import ImageIO
import os
import ShotCore

/// The desktop picture of the screen in front, which the Style panel's Desktop background draws. Each document that
/// uses it reads it once, at most 2,400 pixels on its long side, and lets it go when it closes.
@MainActor
enum DesktopPicture {
    /// The picture, or `nil` when the desktop has none Shot can read, such as a dynamic wallpaper that isn't a file;
    /// the fill then draws its own warm grey.
    static func current() async -> CGImage? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return nil
        }
        let loaded = await Task.detached { () -> SendableImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(SendableImage.init)
        }.value
        guard let loaded else {
            Logger.shot("style").notice("Couldn't read the desktop picture, so Desktop draws its own grey")
            return nil
        }
        return loaded.image
    }
}
