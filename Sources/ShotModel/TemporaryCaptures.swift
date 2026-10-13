import Foundation

/// Captures and recordings taken with saving off, which go to a temporary folder so Quick Access and the editors can open them.
public enum TemporaryCaptures {
    public static var folder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("Shot") }

    /// How long one is kept after it was last changed, which is long enough to be done with it from Quick Access or the clipboard.
    public static let maxAge: TimeInterval = 24 * 60 * 60

    /// Whether `file` sits directly in `folder`, so `sweep` will delete it once it's old enough.
    public static func isTemporary(_ file: URL, in folder: URL = folder) -> Bool {
        file.deletingLastPathComponent().resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path
    }

    /// Deletes the files directly in `folder` last changed before `cutoff`, and returns how many. Folders in it, such as
    /// the recording segments and export scratch, are left alone, since what's in them is cleaned up by what wrote it.
    @discardableResult
    public static func sweep(_ folder: URL = folder, before cutoff: Date = Date().addingTimeInterval(-maxAge)) -> Int {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        var swept = 0
        for file in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) < cutoff
            else {
                continue
            }
            if (try? FileManager.default.removeItem(at: file)) != nil {
                swept += 1
            }
        }
        return swept
    }
}
