import AppKit
import SwiftUI

@MainActor
enum SettingsWindowController {
    private static var window: NSWindow?
    static let size = NSSize(width: 820, height: 600)

    static func show(section: SettingsSection? = nil) {
        if let section {
            SettingsNavigation.shared.section = section
        }
        if window == nil {
            window = GlassWindow.make(size: size, title: "Shot Settings") { SettingsView() }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.invalidateShadow()
    }
}
