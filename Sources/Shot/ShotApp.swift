import ShotCore
import SwiftUI

@main
struct ShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar icon and its menu are AppKit (`StatusMenu`), so the menu can hold the Recent row. A scene is
        // still required, and this one shows nothing: Shot's own main menu replaces the one it would add.
        Settings {
            EmptyView()
        }
    }
}
