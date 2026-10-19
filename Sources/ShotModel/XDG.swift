import Foundation

/// The folders a Linux desktop names through the XDG specs. Linux Foundation's `.picturesDirectory` reads
/// `user-dirs.dirs`, but not the quotes and `$HOME` that xdg-user-dirs-update writes, so on most desktops it gives a
/// folder that doesn't exist; this reads the file as `xdg-user-dir` does.
public enum XDG {
    /// `$HOME`, which the XDG folders and Linux Foundation's `UserDefaults` are under, or when it's unset the user's
    /// home from the password database, which is what `homeDirectoryForCurrentUser` always gives.
    public static func home(environment: [String: String]) -> URL {
        if let path = environment["HOME"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// `$XDG_CONFIG_HOME`, or `~/.config` when it's unset or not an absolute path.
    public static func configHome(environment: [String: String], home: URL) -> URL {
        if let path = environment["XDG_CONFIG_HOME"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return home.appendingPathComponent(".config", isDirectory: true)
    }

    /// The user's pictures folder, `XDG_PICTURES_DIR` in `user-dirs.dirs`, or `~/Pictures` when that doesn't name one.
    public static func picturesFolder(environment: [String: String], home: URL) -> URL {
        let file = configHome(environment: environment, home: home).appendingPathComponent("user-dirs.dirs")
        let contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return userFolder("XDG_PICTURES_DIR", in: contents, home: home) ?? home.appendingPathComponent("Pictures", isDirectory: true)
    }

    /// The folder `key` names in the contents of a `user-dirs.dirs`, whose lines are `KEY="$HOME/path"` or
    /// `KEY="/path"`. A folder that's just `$HOME` means the user turned it off, so it names none.
    static func userFolder(_ key: String, in contents: String, home: URL) -> URL? {
        let line = contents.split(whereSeparator: \.isNewline).last { $0.hasPrefix("\(key)=") }
        guard var value = line?.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        let path: String
        if value.hasPrefix("$HOME/") {
            path = home.path + value.dropFirst("$HOME".count)
        } else if value.hasPrefix("/") {
            path = value
        } else {
            return nil
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        return folder.path == home.standardizedFileURL.path ? nil : folder
    }
}
