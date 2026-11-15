import AppKit
import SwiftUI

/// Hands ↑ and ↓ to `SettingsWindowController` once no focused control, such as a scroll view or a slider, has used them.
private final class SettingsWindow: NSWindow {
    var onKey: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

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
        Perf.measureWindowOpen("settings")
        if let section {
            SettingsNavigation.shared.open(section)
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
        let window = SettingsWindow()
        GlassWindow.make(window, size: NSSize(width: min(size.width, visible.width), height: min(size.height, visible.height)), title: String(localized: "Settings"), resizable: true) {
            SettingsView()
        }
        window.minSize = minSize
        window.onKey = { event in
            guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
                return false
            }
            return moveBetweenSections(keyCode: event.keyCode)
        }
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

    /// ↑ and ↓ move between sections, as in a sidebar list, unless a text field, a shortcut recorder, a menu or a sheet has
    /// the keyboard.
    private static func moveBetweenSections(keyCode: UInt16) -> Bool {
        let navigation = SettingsNavigation.shared
        guard let window, window.isKeyWindow, window.attachedSheet == nil, window.childWindows?.isEmpty ?? true,
              !navigation.recordingShortcut, !(window.firstResponder is NSText) else {
            return false
        }
        switch keyCode {
        case 126: navigation.step(by: -1)
        case 125: navigation.step(by: 1)
        default: return false
        }
        return true
    }
}
