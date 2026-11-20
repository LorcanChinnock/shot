import CryptoKit
import Foundation

/// What the gallery's Make room offers to clear: captures over a size, and exact copies of the same file. Everything it
/// offers goes to the Trash, so nothing is lost for good.
public enum MakeRoom {
    /// Captures over this many bytes count as large: long or high-resolution recordings and most GIFs, and almost no
    /// screenshots. Decimal megabytes, as Finder and `ByteCountFormatter` count them.
    public static let largeBytes = 25_000_000

    /// The captures over `largeBytes`, largest first, leaving out the extra copies Make room already lists as duplicates,
    /// so no file counts twice.
    public static func large(_ items: [GalleryItem], excluding copies: [GalleryItem] = []) -> [GalleryItem] {
        let listed = Set(copies.map(\.url))
        return items.filter { $0.bytes > largeBytes && !listed.contains($0.url) }.sorted { $0.bytes > $1.bytes }
    }

    /// The extra copies among `items`: files with the same contents as an older one, which stays. Only files of the same
    /// size are compared, so `fingerprint` reads few files. A file it can't read is never counted as a copy. Largest first.
    public static func duplicateCopies(_ items: [GalleryItem], fingerprint: (URL) -> String?) -> [GalleryItem] {
        var copies: [GalleryItem] = []
        for group in Dictionary(grouping: items.filter { $0.bytes > 0 }, by: \.bytes).values where group.count > 1 {
            var byContents: [String: [GalleryItem]] = [:]
            for item in group {
                if let print = fingerprint(item.url) {
                    byContents[print, default: []].append(item)
                }
            }
            for same in byContents.values where same.count > 1 {
                // The oldest stays, as it's the one most likely already pasted or linked somewhere.
                let oldestFirst = same.sorted { ($0.date, $0.url.path) < ($1.date, $1.url.path) }
                copies += oldestFirst.dropFirst()
            }
        }
        return copies.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.url.path < $1.url.path }
    }

    /// The SHA-256 of the file at `url`, read a megabyte at a time so a long recording doesn't fill memory. `nil` when it
    /// can't be read.
    public static func fingerprint(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            // `read` gives nil or no data at the end of the file, and throws only when the file can't be read.
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// How many bytes `items` take together.
    public static func bytes(_ items: [GalleryItem]) -> Int {
        items.reduce(0) { $0 + $1.bytes }
    }
}
