import AVFoundation
import Foundation

/// The layered projects behind captures and versions, kept app-private in
/// `~/Library/Application Support/<bundle ID>/Projects/` rather than in the files, so hidden layers, full-resolution
/// placed images and who made a file never leak into anything you share. One JSON file per project, written
/// atomically, so the CLI can write while the app runs without a lock. A project is keyed by an ID stamped in its file's
/// metadata (`ProjectStamp`), or for a GIF, which can't hold one, by its volume and inode.
public struct ProjectStore: Sendable {
    public enum StoreError: Error, Equatable {
        /// The file to keep a project for isn't there.
        case noFile
        /// The file can't hold an ID and its identity can't be read, so the project couldn't be found again.
        case noKey
    }

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The store of the app with `bundleID`, so Shot and ShotDev keep their own, as `AgentSocket` does.
    public init(bundleID: String) {
        self.init(folder: URL.applicationSupportDirectory.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("Projects", isDirectory: true))
    }

    /// Keeps `document`, the layers of `file` over `original`, and who made it. `id` is the ID stamped in `file`, or
    /// `nil` for a file that can't hold one. A capture with no layers passes no document or original, and keeps only
    /// its origin. Write `file` first: its identity and a bookmark to it go in the entry.
    @discardableResult
    public func save<Document: Codable & Sendable>(_ document: Document?, for file: URL, id: String?, original: URL? = nil, origin: ProjectOrigin) throws -> ProjectEntry {
        guard let located = ProjectFile(at: file) else {
            throw StoreError.noFile
        }
        guard let key = id ?? ProjectKey.id(identifying: located), let name = ProjectKey.fileName(for: key) else {
            throw StoreError.noKey
        }
        let saved = ProjectEntry(id: key, stamped: id != nil, file: located, original: original.flatMap { ProjectFile(at: $0) }, origin: origin)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ProjectEntry.encoder().encode(StoredProject(entry: saved, document: document)).write(to: folder.appendingPathComponent(name), options: .atomic)
        // A GIF saved again at the same path has a new inode, so the entries keyed by its old ones are stale.
        if id == nil {
            for stale in ids().filter(ProjectKey.isIdentity) where stale != key && entry(stale)?.file.path == located.path {
                remove(stale)
            }
        }
        return saved
    }

    /// Keeps only who made `file`, for a capture or recording with no layers.
    @discardableResult
    public func save(origin: ProjectOrigin, for file: URL, id: String?) throws -> ProjectEntry {
        try save(String?.none, for: file, id: id, origin: origin)
    }

    /// The project of `file`, with its layers decoded as `Document`; `nil` when it has none, or they aren't one.
    public func project<Document: Codable & Sendable>(for file: URL, as type: Document.Type = Document.self) async -> StoredProject<Document>? {
        guard let id = await id(of: file), let data = read(id) else {
            return nil
        }
        return try? ProjectEntry.decoder().decode(StoredProject<Document>.self, from: data)
    }

    /// The entry of `file`, without its layers, such as for the provenance the gallery shows.
    public func entry(for file: URL) async -> ProjectEntry? {
        guard let id = await id(of: file) else {
            return nil
        }
        return entry(id)
    }

    /// Removes the projects whose files are gone, and returns how many. Run at launch, off the main actor: it reads
    /// every entry and looks for its file. An entry it can't read, perhaps from a newer Shot, is left alone.
    @discardableResult
    public func prune(now: Date = Date()) async -> Int {
        let mounted = Set((FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeUUIDStringKey], options: []) ?? [])
            .compactMap { try? $0.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString })
        var pruned = 0
        for id in ids() {
            guard let entry = entry(id) else {
                continue
            }
            let volumeMounted = entry.file.volume.map(mounted.contains) ?? true
            if !ProjectPruning.keeps(entry, sightings: await sightings(of: entry), volumeMounted: volumeMounted, now: now) {
                remove(id)
                pruned += 1
            }
        }
        return pruned
    }

    // MARK: Keys

    /// The ID `file`'s project is kept under: the one stamped in it, or for a file that can't hold one, the entry whose
    /// file it is, by inode first and then by path.
    private func id(of file: URL) async -> String? {
        if ProjectKey.stamps(pathExtension: file.pathExtension) {
            return await ProjectStamp.id(ofFileAt: file)
        }
        guard let located = ProjectFile(at: file) else {
            return nil
        }
        if let key = ProjectKey.id(identifying: located), let entry = entry(key), entry.isFile(ProjectSighting(file: located)) {
            return key
        }
        return identityEntry(matching: located)?.id
    }

    private func identityEntry(matching file: ProjectFile) -> ProjectEntry? {
        ids().lazy.filter(ProjectKey.isIdentity).compactMap(entry).first { $0.isFile(ProjectSighting(file: file)) }
    }

    /// The files where `entry`'s file was and where its bookmark leads, as they are now.
    private func sightings(of entry: ProjectEntry) async -> [ProjectSighting] {
        var urls = [URL(fileURLWithPath: entry.file.path)]
        if let moved = entry.file.resolvedBookmark(), moved.standardizedFileURL.path != urls[0].standardizedFileURL.path {
            urls.append(moved)
        }
        var sightings: [ProjectSighting] = []
        for url in urls {
            guard let file = ProjectFile(at: url, bookmark: false) else {
                continue
            }
            sightings.append(ProjectSighting(file: file, stampedID: entry.stamped ? await ProjectStamp.id(ofFileAt: url) : nil))
        }
        return sightings
    }

    // MARK: Files

    private func ids() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).compactMap(ProjectKey.id(fromFileName:))
    }

    private func read(_ id: String) -> Data? {
        ProjectKey.fileName(for: id).flatMap { try? Data(contentsOf: folder.appendingPathComponent($0)) }
    }

    /// Reads only the entry: the decoder skips the layers' key.
    private func entry(_ id: String) -> ProjectEntry? {
        read(id).flatMap { try? ProjectEntry.decoder().decode(ProjectEntry.self, from: $0) }
    }

    private func remove(_ id: String) {
        if let name = ProjectKey.fileName(for: id) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
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

/// The project ID in a file's own metadata: XMP for PNG and JPEG, written by `ImageCodec`, and a QuickTime metadata
/// item for MP4 and MOV.
public enum ProjectStamp {
    /// A QuickTime metadata (`mdta`) key for MOV. An MP4 export drops `mdta` keys, so it gets an iTunes atom of its own,
    /// which it keeps.
    static let movieIdentifier = AVMetadataIdentifier(rawValue: "mdta/dev.lorcan.shot.project")
    static let mp4Identifier = AVMetadataIdentifier(rawValue: "itsk/shpj")

    /// The item an export adds to its `metadata` to stamp `id` in the movie of `fileType` it writes.
    public static func metadataItem(id: String, for fileType: AVFileType) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = fileType == .mov ? movieIdentifier : mp4Identifier
        item.value = id as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }

    /// The ID stamped in the image or movie at `url`, or `nil` when it has none.
    public static func id(ofFileAt url: URL) async -> String? {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov":
            guard let metadata = try? await AVURLAsset(url: url).load(.metadata),
                  let item = metadata.first(where: { [movieIdentifier, mp4Identifier].contains($0.identifier) })
            else {
                return nil
            }
            return try? await item.load(.stringValue)
        default:
            return ImageCodec.projectID(ofFileAt: url)
        }
    }

    /// Stamps `id` in the movie at `url`, such as a recording, by copying it without re-encoding and swapping the copy
    /// in. An export that writes the movie itself should add `metadataItem(id:for:)` instead.
    public static func stamp(movieAt url: URL, id: String) async throws {
        let asset = AVURLAsset(url: url)
        let kept = try await asset.load(.metadata).filter { ![movieIdentifier, mp4Identifier].contains($0.identifier) }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let fileType: AVFileType = url.pathExtension.lowercased() == "mov" ? .mov : .mp4
        export.metadata = kept + [metadataItem(id: id, for: fileType)]
        let copy = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: copy) }
        try await export.export(to: copy, as: fileType)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: copy)
    }
}

extension ProjectFile {
    /// The file at `url` as it is now, with a bookmark to it unless `bookmark` is false; `nil` when it isn't there.
    public init?(at url: URL, bookmark: Bool = true) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .volumeUUIDStringKey, .fileSizeKey, .contentModificationDateKey]
        // A URL caches what it read, so one kept across a rewrite of its file would report the old size and date.
        var url = url
        url.removeAllCachedResourceValues()
        guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else {
            return nil
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.init(
            path: url.standardizedFileURL.path,
            bookmark: bookmark ? try? url.bookmarkData() : nil,
            volume: values.volumeUUIDString,
            number: (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value,
            size: values.fileSize.map(Int64.init),
            modified: values.contentModificationDate
        )
    }

    /// Where the bookmark leads now, without asking to mount a disk; `nil` when it leads nowhere.
    public func resolvedBookmark() -> URL? {
        guard let bookmark else {
            return nil
        }
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// The file now, wherever it went: where its bookmark leads, or else where it was.
    public func locate() -> URL? {
        if let moved = resolvedBookmark(), FileManager.default.fileExists(atPath: moved.path) {
            return moved
        }
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
}
