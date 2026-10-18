#if canImport(Darwin)
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

    /// Writes `data` as a new file in `folder` under the name `name` gives, asking again while that name is taken, and
    /// returns where it went. The data goes to a hidden file first and is renamed into place with `RENAME_EXCL`, so a
    /// crash or a full disk never leaves a truncated file under the real name and no existing file is ever replaced.
    /// Foundation can't do both at once: `write(to:options:)` traps on `.atomic` with `.withoutOverwriting`.
    public static func writeNew(_ data: Data, in folder: URL, name: () -> URL) throws -> URL {
        let temporary = folder.appendingPathComponent(".shot-\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for _ in 0 ..< 100 {
            let url = name()
            if renamex_np(temporary.path, url.path, UInt32(RENAME_EXCL)) == 0 {
                return url
            }
            let failure = errno
            guard failure == EEXIST else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path, NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)])
            }
        }
        throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: folder.path])
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
#endif
