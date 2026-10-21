import Foundation

/// The `shot` command for a copy of Shot that Homebrew didn't install: a link in `/usr/local/bin`, which every shell has
/// on its PATH, to the `shot-cli` inside the app. Settings › Agents makes and removes it. The link points into the app,
/// so an update replaces the command too.
public enum CommandLink {
    public static let folder = "/usr/local/bin"
    /// Where Homebrew's cask links `shot` on Apple silicon.
    public static let homebrewFolder = "/opt/homebrew/bin"

    /// `shot` for a release and `shot-dev` for a dev build, so installing a dev build's command never replaces the
    /// release's.
    public static func name(bundleID: String?) -> String {
        bundleID == "dev.lorcan.Shot" ? "shot" : "shot-dev"
    }

    public enum Status: Equatable, Sendable {
        /// Nothing is there, so it can be installed.
        case missing
        /// The link in `folder` points at this copy of Shot.
        case linked
        /// Homebrew's link points at this copy of Shot, so there's nothing to do.
        case homebrew
        /// The link in `folder` points at a `shot-cli` that isn't this one, such as a copy of Shot that has since moved,
        /// so it can be pointed here.
        case stale(String)
        /// Something that isn't Shot's is in `folder` under that name, so it's left alone.
        case taken(String)
    }

    /// What's installed as `name` for the `shot-cli` at `cli`.
    public static func status(name: String, cli: String, folder: String = folder, homebrewFolder: String = homebrewFolder) -> Status {
        let link = (folder as NSString).appendingPathComponent(name)
        let target = destination(of: link)
        if let target, same(target, cli) {
            return .linked
        }
        if let brewed = destination(of: (homebrewFolder as NSString).appendingPathComponent(name)), same(brewed, cli) {
            return .homebrew
        }
        guard let target else {
            return .missing
        }
        return target.hasSuffix("/Contents/MacOS/shot-cli") ? .stale(target) : .taken(target)
    }

    /// The AppleScript that makes the link, asking for an administrator's password since `/usr/local/bin` belongs to
    /// root. `ln -sfn` replaces a stale link in one step.
    public static func installScript(name: String, cli: String, folder: String = folder) -> String {
        let link = (folder as NSString).appendingPathComponent(name)
        return privileged("mkdir -p \(quoted(folder)) && ln -sfn \(quoted(cli)) \(quoted(link))")
    }

    /// The AppleScript that removes the link, which `rm` does without touching the app it points into.
    public static func uninstallScript(name: String, folder: String = folder) -> String {
        privileged("rm -f \(quoted((folder as NSString).appendingPathComponent(name)))")
    }

    /// Where the link at `path` points, made absolute; `path` itself for a file that isn't a link; nil when nothing is
    /// there. A link to a file that no longer exists still counts, since it still takes the name.
    static func destination(of path: String) -> String? {
        if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
            return target.hasPrefix("/") ? target : ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(target)
        }
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    static func same(_ a: String, _ b: String) -> Bool {
        URL(fileURLWithPath: a).resolvingSymlinksInPath().path == URL(fileURLWithPath: b).resolvingSymlinksInPath().path
    }

    /// `text` as one shell word.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    static func privileged(_ command: String) -> String {
        let escaped = command.replacingOccurrences(of: #"\"#, with: #"\\"#).replacingOccurrences(of: "\"", with: #"\""#)
        return "do shell script \"\(escaped)\" with administrator privileges"
    }
}
