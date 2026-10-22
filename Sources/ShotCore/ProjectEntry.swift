import Foundation

/// Who made a capture or version, kept in Shot's own project store rather than in the file, so a file you share never
/// says an agent made it.
public struct ProjectOrigin: Codable, Equatable, Sendable {
    public enum Via: String, Codable, Sendable {
        case app, cli, mcp
    }

    public var via: Via
    /// The MCP client's name, from `clientInfo` in `initialize`, such as "claude-code".
    public var client: String?
    /// The MCP tool or command that made it, such as "annotate" or "record_window"; `nil` for the app.
    public var action: String?
    /// To the second.
    public var date: Date

    public init(via: Via, client: String? = nil, action: String? = nil, date: Date = Date()) {
        self.via = via
        self.client = client
        self.action = action
        self.date = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

extension ProjectOrigin {
    /// Whether an agent or the command line made it, which the gallery marks.
    public var isAgent: Bool { via != .app }

    /// `client` as people know it: the product for the MCP clients Shot knows, or the name as the client sent it.
    public var clientName: String? {
        client.map { Self.knownClients[$0.lowercased()] ?? $0 }
    }

    /// The `clientInfo` names some MCP clients send, and the product each one is.
    private static let knownClients = [
        "claude-code": "Claude Code",
        "claude-ai": "Claude",
        "cursor-vscode": "Cursor",
        "codex-mcp-client": "Codex",
    ]
}

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

/// One project in the store: a capture or version, the original it was edited from, and who made it. The layers
/// themselves sit beside it in the same file, in a shape only ShotCore knows.
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
    public var origin: ProjectOrigin

    public init(id: String, stamped: Bool, file: ProjectFile, original: ProjectFile? = nil, origin: ProjectOrigin) {
        schema = Self.currentSchema
        self.id = id
        self.stamped = stamped
        self.file = file
        self.original = original
        self.origin = origin
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
    /// `nil` for a capture with no layers, which keeps only its origin.
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
    /// How long a new entry is kept even when its file can't be found, since the CLI may write the project a moment
    /// before the app looks for it.
    public static let grace: TimeInterval = 10 * 60

    /// Whether to keep `entry`, given the files found where it points (`sightings`) and whether the volume its file
    /// was on is mounted. A file on an unmounted disk isn't gone, so its project stays.
    public static func keeps(_ entry: ProjectEntry, sightings: [ProjectSighting], volumeMounted: Bool, now: Date = Date()) -> Bool {
        sightings.contains(where: entry.isFile) || !volumeMounted || now.timeIntervalSince(entry.origin.date) < grace
    }
}

/// Which files an agent or the command line made, for the gallery's mark and its Made by agents filter.
public enum ProjectProvenance {
    /// The origin of each file an agent or the command line made, keyed by the path it's at now. Each entry comes with
    /// the files found where it points (`ProjectStore` looks only for these, so the cost follows the number of agent
    /// entries, not the size of the folder). App entries are left out. Where two entries claim one file, the newer wins.
    public static func agentOrigins(_ located: [(entry: ProjectEntry, sightings: [ProjectSighting])]) -> [String: ProjectOrigin] {
        var origins: [String: ProjectOrigin] = [:]
        for (entry, sightings) in located where entry.origin.isAgent {
            guard let sighting = sightings.first(where: entry.isFile) else {
                continue
            }
            if let claimed = origins[sighting.file.path], claimed.date > entry.origin.date {
                continue
            }
            origins[sighting.file.path] = entry.origin
        }
        return origins
    }
}

extension ProjectOrigin {
    /// Who made a file and how, as the gallery's mark says: "Made by Claude Code · annotate · 14:03", or
    /// "Command line · trim · 14:03" for a `shot` run, whoever started it. The date shows too when it isn't today.
    public func summary(now: Date = Date(), calendar: Calendar = .current) -> String {
        let who: String? = switch via {
        case .app: nil
        case .cli: String(localized: "Command line")
        case .mcp: clientName.map { String(localized: "Made by \($0)") } ?? String(localized: "Made by an agent")
        }
        let when = calendar.isDate(date, inSameDayAs: now) ? date.formatted(date: .omitted, time: .shortened) : date.formatted(date: .abbreviated, time: .shortened)
        return [who, action, when].compactMap { $0 }.joined(separator: " · ")
    }
}
