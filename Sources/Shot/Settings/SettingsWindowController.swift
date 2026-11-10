import AppKit
import SwiftUI

/// The Settings window, with every section picked from a sidebar. The gallery has its own window, `GalleryWindowController`.
@MainActor
enum SettingsWindowController {
    private static var window: NSWindow?
    private static var contentReleased = false
    static let size = NSSize(width: 1080, height: 720)
    /// Narrowest window that still shows every section.
    static let minSize = NSSize(width: 800, height: 420)

    /// The window's ID for screen capture, so captures can include it while Shot's overlays stay out.
    static var windowID: CGWindowID? { window.map { CGWindowID($0.windowNumber) } }

    static func show(section: SettingsSection? = nil) {
        if let section {
            SettingsNavigation.shared.section = section
        }
        if window == nil {
            makeWindow()
        }
        guard let window else {
            return
        }
        if contentReleased {
            GlassWindow.setContent(of: window) { SettingsView() }
            contentReleased = false
        }
        GlassWindow.present(window)
        window.invalidateShadow()
    }

    private static func makeWindow() {
        let visible = (NSScreen.underPointer ?? NSScreen.screens[0]).visibleFrame
        let window = GlassWindow.make(size: NSSize(width: min(size.width, visible.width), height: min(size.height, visible.height)), title: String(localized: "Settings"), resizable: true) {
            SettingsView()
        }
        window.minSize = minSize
        // The window is kept when closed, so its views never disappear on their own: turn off any camera or microphone test, and
        // once closed drop the views. `show` builds them again.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                DevicePreview.stopAll()
                DispatchQueue.main.async {
                    guard !window.isVisible else {
                        return
                    }
                    window.contentView = NSView()
                    contentReleased = true
                }
            }
        }
        self.window = window
    }
}
