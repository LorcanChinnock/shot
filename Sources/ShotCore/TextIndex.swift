import Foundation

/// The text read from each screenshot in the capture folder, kept so search finds a screenshot by what's in it without
/// reading it again. The app's indexer fills it in the background, after captures, and saves it in its Application
/// Support folder, never in the files; the gallery and `list_captures` read it. An entry counts only while its file has
/// the path, size and modification date it had when it was read, so a changed file is read again.
public struct TextIndex: Codable, Equatable, Sendable {
    /// A file as the folder lists it, which its entry is checked against.
    public struct File: Hashable, Sendable {
        public var path: String
        public var bytes: Int
        public var modified: Date

        public init(path: String, bytes: Int, modified: Date) {
            self.path = path
            self.bytes = bytes
            self.modified = modified
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var bytes: Int
        /// Seconds since the reference date, which JSON keeps exactly, so a date read back equals the file's.
        public var modified: Double
        /// The lines read, one to a line; empty when the image has no text.
        public var text: String

        func isFor(_ file: File) -> Bool {
            bytes == file.bytes && modified == file.modified.timeIntervalSinceReferenceDate
        }
    }

    /// Bumped when what's read changes, so an older index is read again rather than trusted.
    public static let currentVersion = 1
    public var version = currentVersion
    /// By path.
    public var entries: [String: Entry] = [:]

    public init() {}

    /// Only screenshots are read: not recordings, and not GIFs, which are made from recordings.
    public static func reads(_ url: URL) -> Bool {
        GalleryKind(fileExtension: url.pathExtension) == .image
    }

    /// The text read from `file`, or `nil` when it hasn't been read as it is now.
    public func text(of file: File) -> String? {
        entries[file.path].flatMap { $0.isFor(file) ? $0.text : nil }
    }

    public mutating func set(_ text: String, for file: File) {
        entries[file.path] = Entry(bytes: file.bytes, modified: file.modified.timeIntervalSinceReferenceDate, text: text)
    }

    /// Brings the entries for `folder` up to date with `files`, the screenshots directly inside it, and returns those
    /// still to read, newest first. An entry whose file has gone is dropped, unless a file of the same size and
    /// modification date has appeared without an entry: that's the same file renamed, so its text moves to the new path
    /// rather than being read again. Entries in other folders stay, so switching back to one doesn't read it all again.
    public mutating func reconcile(folder: String, files: [File]) -> [File] {
        let folder = Self.standardized(folder)
        let present = Set(files.map(\.path))
        var gone: [String: Entry] = [:]
        for (path, entry) in entries where !present.contains(path) && Self.parent(of: path) == folder {
            gone[path] = entry
            entries[path] = nil
        }
        var unread: [File] = []
        for file in files where text(of: file) == nil {
            if let (path, entry) = gone.first(where: { $0.value.isFor(file) }) {
                gone[path] = nil
                entries[file.path] = entry
            } else {
                unread.append(file)
            }
        }
        return unread.sorted { $0.modified != $1.modified ? $0.modified > $1.modified : $0.path < $1.path }
    }

    /// The text of each of `files` that's been read, folded as `TextSearch` compares it, by path. Built once when the
    /// index changes, so a keystroke only looks through strings.
    public func folded(_ files: [File]) -> [String: String] {
        var folded: [String: String] = [:]
        for file in files {
            if let text = text(of: file), !text.isEmpty {
                folded[file.path] = TextSearch.searchable(text)
            }
        }
        return folded
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// The index in `data`, or an empty one when it's unreadable or from another version.
    public static func decoded(_ data: Data?) -> TextIndex {
        guard let data, let index = try? JSONDecoder().decode(TextIndex.self, from: data), index.version == currentVersion else {
            return TextIndex()
        }
        return index
    }

    static func parent(of path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL.path
    }

    static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }
}

/// How search compares text, ignoring case and accents as the gallery's name search does.
public enum TextSearch {
    /// `text` folded to compare: without case or accents.
    public static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// `text` folded, and stored as contiguous UTF-8, which `contains` can look through without copying it.
    public static func searchable(_ text: String) -> String {
        var folded = folded(text)
        folded.makeContiguousUTF8()
        return folded
    }

    /// Whether `text`, from `searchable`, contains `query`, from `query(_:)`. Compares the bytes, which is several times
    /// faster than comparing characters: a keystroke in the gallery looks through every screenshot's text.
    public static func contains(_ text: String, _ query: String) -> Bool {
        text.utf8.withContiguousStorageIfAvailable { haystack in
            query.utf8.withContiguousStorageIfAvailable { needle in
                guard let base = haystack.baseAddress, let wanted = needle.baseAddress, !needle.isEmpty else {
                    return needle.isEmpty
                }
                return memmem(base, haystack.count, wanted, needle.count) != nil
            }
        }.flatMap { $0 } ?? text.contains(query)
    }

    /// `query` folded and trimmed, or `nil` when it's blank and matches nothing.
    public static func query(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : searchable(trimmed)
    }

    /// The lines of `text` that contain `query`, ignoring case and accents, in order.
    public static func lines(in text: String, matching query: String) -> [String] {
        guard let wanted = self.query(query) else {
            return []
        }
        return text.split(separator: "\n").filter { folded(String($0)).contains(wanted) }.map(String.init)
    }
}
