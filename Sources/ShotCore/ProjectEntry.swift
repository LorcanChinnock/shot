import Foundation

/// A file a project points at: where it was, a bookmark that follows it when it moves, and enough of its identity to
/// tell it from another file put at the same path.
public struct ProjectFile: Codable, Equatable, Sendable {
    public var path: String
    /// Made and resolved by ShotCore; `nil` where bookmarks don't exist.
    public var bookmark: Data?
    /// The UUID of the volume it's on.
    public var volume: String?
    /// Its inode on that volume, which survives a rename or a move within the volume.
    public var number: UInt64?
    public var size: Int64?
    /// To the second.
    public var modified: Date?

    public init(path: String, bookmark: Data? = nil, volume: String? = nil, number: UInt64? = nil, size: Int64? = nil, modified: Date? = nil) {
        self.path = path
        self.bookmark = bookmark
        self.volume = volume
        self.number = number
        self.size = size
        self.modified = modified.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.down)) }
    }

    /// Whether `other`, as found on disk now, is this file. The same inode on the same volume is, wherever it went.
    /// Failing that, a file at the same path with the same size and modification date is, since saving through a
    /// temporary file gives it a new inode. Anything else at the path is a different file.
    public func matches(_ other: ProjectFile) -> Bool {
        if let volume, let number, volume == other.volume, number == other.number {
            return true
        }
        return path == other.path && size != nil && size == other.size && modified != nil && modified == other.modified
    }
}

/// One project in the store: a capture or version and the original it was edited from. The layers themselves sit
/// beside it in the same file, in a shape only ShotCore knows. Entries an older Shot wrote also carry an `origin`, which
/// decoding ignores.
public struct ProjectEntry: Codable, Equatable, Sendable {
    public static let currentSchema = "shot.project/1"

    public var schema: String
    /// The ID stamped in the file's metadata, or for a file that can't hold one, a key made from its identity.
    public var id: String
    /// Whether `id` is stamped in the file, so the file is found by it rather than by `file`'s identity.
    public var stamped: Bool
    public var file: ProjectFile
    /// What the layers sit on: the capture a version was edited from. `nil` for a capture with no layers.
    public var original: ProjectFile?

    public init(id: String, stamped: Bool, file: ProjectFile, original: ProjectFile? = nil) {
        schema = Self.currentSchema
        self.id = id
        self.stamped = stamped
        self.file = file
        self.original = original
    }

    /// Whether `sighting`, a file found where this entry's file was or where its bookmark led, is still its file.
    public func isFile(_ sighting: ProjectSighting) -> Bool {
        stamped ? sighting.stampedID == id : file.matches(sighting.file)
    }

    /// Writes a project, its placed images as PNG.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// A project as the store keeps it: the entry's fields with the layers beside them under `document`.
public struct StoredProject<Document: Codable & Sendable>: Codable, Sendable {
    public var entry: ProjectEntry
    /// `nil` for an entry with no layers.
    public var document: Document?

    public init(entry: ProjectEntry, document: Document?) {
        self.entry = entry
        self.document = document
    }

    private enum CodingKeys: String, CodingKey {
        case document
    }

    public init(from decoder: Decoder) throws {
        entry = try ProjectEntry(from: decoder)
        document = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Document.self, forKey: .document)
    }

    public func encode(to encoder: Encoder) throws {
        try entry.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(document, forKey: .document)
    }
}

extension StoredProject: Equatable where Document: Equatable {}

/// A file found on disk while looking for an entry's file, with the project ID stamped in it if it has one.
public struct ProjectSighting: Equatable, Sendable {
    public var file: ProjectFile
    public var stampedID: String?

    public init(file: ProjectFile, stampedID: String? = nil) {
        self.file = file
        self.stampedID = stampedID
    }
}

/// How projects are named in the store, one file each.
public enum ProjectKey {
    /// The formats whose metadata holds a project ID: XMP in PNG and JPEG, a metadata item in MP4 and MOV. Anything
    /// else, such as a GIF, is keyed by its path and file identity.
    public static func stamps(pathExtension: String) -> Bool {
        ["png", "jpg", "jpeg", "mp4", "mov"].contains(pathExtension.lowercased())
    }

    /// A new ID to stamp in a file.
    public static func newID() -> String {
        UUID().uuidString
    }

    /// The ID of a file that can't hold one, from its volume and inode, so the store finds it without reading the
    /// others; `nil` when either is unknown.
    public static func id(identifying file: ProjectFile) -> String? {
        guard let volume = file.volume, let number = file.number else {
            return nil
        }
        return "file-\(volume)-\(number)"
    }

    /// Whether `id` is one `id(identifying:)` made, so its entry may need finding by path instead.
    public static func isIdentity(_ id: String) -> Bool {
        id.hasPrefix("file-")
    }

    /// The store's file name for `id`, or `nil` when `id` could escape the folder.
    public static func fileName(for id: String) -> String? {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            return nil
        }
        return id + ".json"
    }

    /// The ID in the store's file name `name`, or `nil` when it isn't one.
    public static func id(fromFileName name: String) -> String? {
        guard name.hasSuffix(".json") else {
            return nil
        }
        let id = String(name.dropLast(5))
        return fileName(for: id) == name ? id : nil
    }
}

/// Which projects to drop at launch: those whose files are gone.
public enum ProjectPruning {
    /// Whether to keep `entry`, given the files found where it points (`sightings`) and whether the volume its file
    /// was on is mounted. A file on an unmounted disk isn't gone, so its project stays.
    public static func keeps(_ entry: ProjectEntry, sightings: [ProjectSighting], volumeMounted: Bool) -> Bool {
        sightings.contains(where: entry.isFile) || !volumeMounted
    }
}
