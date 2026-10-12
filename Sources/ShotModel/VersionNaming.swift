import Foundation

/// How a saved version is named beside the file it was made from: "a.png" gives "a (2).png", then "a (3).png". The app's
/// editors and the `shot` commands name versions the same way, through `VersionWriter` in ShotCore.
public enum VersionNaming {
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

    /// Where a `shot` command writes `input` as `pathExtension` when no output is named: beside it with that extension,
    /// or as its next version when that would be the input itself or a file that's there.
    public static func commandOutputURL(for input: URL, pathExtension: String, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let candidate = input.deletingPathExtension().appendingPathExtension(pathExtension)
        return candidate == input || exists(candidate) ? nextVersionURL(of: candidate, exists: exists) : candidate
    }

    /// The extension of a copy of the video at `url`: a MOV stays a MOV, and anything else is written as MP4.
    public static func videoCopyExtension(of url: URL) -> String {
        url.pathExtension.lowercased() == "mov" ? "mov" : "mp4"
    }
}
