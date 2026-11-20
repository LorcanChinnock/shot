import ShotCore

/// Every way in to the library and Settings: the menu bar, ⌘, and `shot://` links. While `PreferenceKey.oneWindow` is on,
/// both open the one Shot window at the right place; otherwise each has its own window, as before.
@MainActor
enum ShotWindowRouter {
    static func showLibrary() {
        if Preferences().oneWindow {
            MainWindowController.showLibrary()
        } else {
            GalleryController.shared.show()
        }
    }

    static func showSettings(section: SettingsSection? = nil) {
        if Preferences().oneWindow {
            MainWindowController.showSettings(section: section)
        } else {
            SettingsWindowController.show(section: section)
        }
    }
}
