import AppKit
import SwiftUI

/// Passes the gallery's shortcuts to `GalleryController` before the menus and the focused view see them.
private final class GalleryWindow: NSWindow {
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

/// The gallery's own window. It opens where it was last closed, at the same size.
@MainActor
enum GalleryWindowController {
    private static var window: NSWindow?
    private static var contentReleased = false
    /// Larger than Settings, as on the board, so the two windows never open exactly over each other.
    static let size = NSSize(width: 1224, height: 764)
    /// Narrowest window that still fits the toolbar and two columns of thumbnails.
    static let minSize = NSSize(width: 640, height: 420)
    /// The user defaults name AppKit saves the window's frame under.
    private static let frameName = "Gallery"

    /// The window's ID for screen capture, so captures can include it while Shot's overlays stay out.
    static var windowID: CGWindowID? { window.map { CGWindowID($0.windowNumber) } }

    static func show() {
        if window == nil {
            makeWindow()
        }
        guard let window else {
            return
        }
        if contentReleased {
            GlassWindow.setContent(of: window) { GalleryWindowView() }
            contentReleased = false
        }
        GlassWindow.present(window)
        window.invalidateShadow()
        // Keeps the search field from taking focus, so the arrow keys move through the grid.
        window.makeFirstResponder(nil)
    }

    private static func makeWindow() {
        let visible = (NSScreen.underPointer ?? NSScreen.screens[0]).visibleFrame
        let window = GalleryWindow()
        GlassWindow.make(window, size: NSSize(width: min(size.width, visible.width), height: min(size.height, visible.height)), title: String(localized: "Gallery"), resizable: true) {
            GalleryWindowView()
        }
        window.minSize = minSize
        // `make` centres the window; a frame saved from an earlier session puts it back where it was.
        window.setFrameUsingName(frameName)
        window.setFrameAutosaveName(frameName)
        window.onCommand = { key, shift in
            GalleryController.shared.handleCommand(key, shift: shift, in: window)
        }
        window.onKey = { event in
            GalleryController.shared.handleKey(event, in: window)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                GalleryController.shared.model.reload()
            }
        }
        // The window is kept when closed, so its views never disappear on their own: stop watching the folder, and once closed
        // drop the views, as the grid keeps every tile it has built. `show` builds them again.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                GalleryController.shared.model.stop()
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

/// The gallery filling its window: the sidebar runs under the traffic lights and the toolbar sits in the title bar.
private struct GalleryWindowView: View {
    var body: some View {
        let model = GalleryController.shared.model
        GalleryRootView(model: model)
            .onAppear { model.start() }
            .onDisappear { model.stop() }
            .frame(minWidth: GalleryWindowController.minSize.width, maxWidth: .infinity, maxHeight: .infinity)
    }
}
