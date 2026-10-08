import AppKit
import SwiftUI

private final class MainWindow: NSWindow {
    var onCommand: ((String, Bool) -> Bool)?
    var onKey: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(), onCommand?(key, flags.contains(.shift)) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

/// Shot's one window: the gallery and every settings section, picked from a sidebar.
@MainActor
enum MainWindowController {
    private static var window: NSWindow?
    private static var contentReleased = false
    static let size = NSSize(width: 1080, height: 720)
    /// Narrowest width that fits the gallery toolbar beside the sidebar.
    static let minSize = NSSize(width: 1020, height: 520)

    private static var showingGallery: Bool { SettingsNavigation.shared.section == .gallery }

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
        if showingGallery {
            // Keeps the search field from taking focus, so the arrow keys move through the grid.
            window.makeFirstResponder(nil)
        }
    }

    /// Opens a settings section, moving off the gallery if that was last shown.
    static func showSettings(section: SettingsSection? = nil) {
        show(section: section ?? (showingGallery ? .general : nil))
    }

    private static func makeWindow() {
        let visible = (NSScreen.underPointer ?? NSScreen.screens[0]).visibleFrame
        let window = MainWindow()
        GlassWindow.make(window, size: NSSize(width: min(size.width, visible.width), height: min(size.height, visible.height)), title: "Shot", resizable: true) {
            SettingsView()
        }
        window.minSize = minSize
        window.onCommand = { key, shift in
            showingGallery && GalleryController.shared.handleCommand(key, shift: shift, in: window)
        }
        window.onKey = { event in
            showingGallery && GalleryController.shared.handleKey(event, in: window)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                if showingGallery {
                    GalleryController.shared.model.reload()
                }
            }
        }
        // The window is kept when closed, so its views never disappear on their own: stop watching the folder, turn off any camera or
        // microphone test, and once closed drop the views, as the gallery grid keeps every tile it has built. `show` builds them again.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                GalleryController.shared.model.stop()
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
