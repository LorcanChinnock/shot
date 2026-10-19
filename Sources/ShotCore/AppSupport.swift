import Foundation

public enum AppSupport {
    /// The app-private folder of the app with `bundleID`, so Shot and ShotDev keep their own:
    /// `~/Library/Application Support/<bundle ID>` on a Mac, and on Linux `<bundle ID>` in `$XDG_DATA_HOME`, which is
    /// `~/.local/share` when it isn't set. Linux Foundation has no `URL.applicationSupportDirectory`; `FileManager`
    /// finds both.
    public static func folder(bundleID: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(bundleID, isDirectory: true)
    }
}
