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

    /// The name of the capture a version was saved from: "a (2).png" and "a (3).png" both give "a.png", and a name
    /// without a version suffix gives itself.
    public static func originalName(of url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: #" \(\d+\)$"#, with: "", options: .regularExpression)
        return url.pathExtension.isEmpty ? base : "\(base).\(url.pathExtension)"
    }

    /// The first "name (n)" from 2 up that doesn't exist beside `url`, so a save never overwrites
    /// the original or an earlier version. A version's own suffix is dropped first, so "a (2)" gives "a (3)".
    public static func nextVersionURL(of url: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let base = URL(fileURLWithPath: originalName(of: url)).deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent()
        var counter = 2
        var next = folder.appendingPathComponent("\(base) (\(counter))").appendingPathExtension(url.pathExtension)
        while exists(next) {
            counter += 1
            next = folder.appendingPathComponent("\(base) (\(counter))").appendingPathExtension(url.pathExtension)
        }
        return next
    }

    /// The next version of `url` for a file written as `format`. It keeps the original's extension when that names
    /// `format`, so "a.jpeg" gives "a (2).jpeg", and otherwise takes the format's own, so "a.heic" saved as PNG gives "a (2).png".
    public static func nextVersionURL(of url: URL, savedAs format: ImageFormat, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let names = format == .png ? ["png"] : ["jpg", "jpeg"]
        let ext = names.contains(url.pathExtension.lowercased()) ? url.pathExtension : format.fileExtension
        return nextVersionURL(of: url.deletingPathExtension().appendingPathExtension(ext), exists: exists)
    }
}
