import Foundation

public enum FileNaming {
    public static func baseName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Shot \(formatter.string(from: date))"
    }

    public static func uniqueURL(in folder: URL, date: Date, pathExtension: String, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let base = baseName(for: date)
        var url = folder.appendingPathComponent("\(base).\(pathExtension)")
        var counter = 2
        while exists(url) {
            url = folder.appendingPathComponent("\(base) (\(counter)).\(pathExtension)")
            counter += 1
        }
        return url
    }
}
