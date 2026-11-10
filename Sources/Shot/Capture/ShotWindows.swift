import AppKit

/// Shot's windows that screenshots and recordings keep in, unlike its overlays and panels, so they can be captured themselves.
@MainActor
enum ShotWindows {
    static var capturable: Set<CGWindowID> {
        Set([SettingsWindowController.windowID, GalleryWindowController.windowID].compactMap(\.self))
    }
}
