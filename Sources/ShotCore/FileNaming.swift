import Foundation

public enum FileNaming {
    public static func baseName(for date: Date, prefix: String = Preferences.defaultFilePrefix) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date))"
    }

    public static func uniqueURL(in folder: URL, date: Date, pathExtension: String, prefix: String = Preferences.defaultFilePrefix, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let base = baseName(for: date, prefix: prefix)
        var url = folder.appendingPathComponent("\(base).\(pathExtension)")
        var counter = 2
        while exists(url) {
            url = folder.appendingPathComponent("\(base) (\(counter)).\(pathExtension)")
            counter += 1
        }
        return url
    }

    /// The first "name (n)" from 2 up that doesn't exist beside `url`, so a save never overwrites
    /// the original or an earlier version. A version's own suffix is dropped first, so "a (2)" gives "a (3)".
    public static func nextVersionURL(of url: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        let base = name.replacingOccurrences(of: #" \(\d+\)$"#, with: "", options: .regularExpression)
        let folder = url.deletingLastPathComponent()
        var counter = 2
        var next = folder.appendingPathComponent("\(base) (\(counter))").appendingPathExtension(url.pathExtension)
        while exists(next) {
            counter += 1
            next = folder.appendingPathComponent("\(base) (\(counter))").appendingPathExtension(url.pathExtension)
        }
        return next
    }
}
