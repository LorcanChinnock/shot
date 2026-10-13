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

    /// A name for a recording rescued from its leftover segments: the usual name plus "(recovered)", and "part N" when
    /// the segments couldn't be joined and each is kept as its own file.
    public static func recoveredURL(in folder: URL, date: Date, part: Int? = nil, prefix: String = Preferences.defaultFilePrefix, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let base = baseName(for: date, prefix: prefix) + (part.map { " (recovered, part \($0))" } ?? " (recovered)")
        var url = folder.appendingPathComponent("\(base).mp4")
        var counter = 2
        while exists(url) {
            url = folder.appendingPathComponent("\(base) (\(counter)).mp4")
            counter += 1
        }
        return url
    }
}
