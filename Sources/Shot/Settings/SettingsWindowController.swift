import AppKit
import SwiftUI

@MainActor
enum SettingsWindowController {
    private static var window: NSWindow?
    /// Tall enough to show all of General, the first tab people see, without scrolling.
    static let size = NSSize(width: 820, height: 644)

    static func show(section: SettingsSection? = nil) {
        if let section {
            SettingsNavigation.shared.section = section
        }
        if window == nil {
            window = GlassWindow.make(size: size, title: "Shot Settings", resizable: true) { SettingsView() }
        }
        guard let window else {
            return
        }
        GlassWindow.present(window)
        window.invalidateShadow()
    }
}
