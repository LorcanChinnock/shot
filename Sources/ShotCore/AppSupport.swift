import Foundation

public enum AppSupport {
    /// The app-private folder of the app with `bundleID`, so Shot and ShotDev keep their own:
    /// `~/Library/Application Support/<bundle ID>`.
    public static func folder(bundleID: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(bundleID, isDirectory: true)
    }
}
