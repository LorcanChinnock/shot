import Foundation

/// Where the command line keeps its settings on Linux, which has no app bundle to name them.
public enum LinuxSettings {
    /// The release's suite, since Linux has no separate dev build.
    public static let suite = "dev.lorcan.Shot"

    /// The file Linux Foundation keeps `suite`'s settings in: `<suite>.plist` in `$XDG_CONFIG_HOME`, or `$HOME/.config`.
    public static func file(suite: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        XDG.configHome(environment: environment, home: XDG.home(environment: environment)).appendingPathComponent("\(suite).plist")
    }
}
