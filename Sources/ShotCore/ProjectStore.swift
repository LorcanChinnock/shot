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
        self.init(folder: AppSupport.folder(bundleID: bundleID).appendingPathComponent("Projects", isDirectory: true))
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
    public func project<Document: Codable & Sendable>(for file: URL, as type: Document.Type = Document.self) -> StoredProject<Document>? {
        guard let id = id(of: file), let data = read(id) else {
            return nil
        }
        return try? ProjectEntry.decoder().decode(StoredProject<Document>.self, from: data)
    }

    /// The entry of `file`, without its layers, such as for the provenance the gallery shows.
    public func entry(for file: URL) -> ProjectEntry? {
        guard let id = id(of: file) else {
            return nil
        }
        return entry(id)
    }

    /// Who made each file an agent or the command line made, keyed by its path now with symlinks resolved. Run off the
    /// main actor: it reads every entry, then looks only for the agent entries' files.
    public func agentOrigins() -> [String: ProjectOrigin] {
        let located = ids().compactMap(entry).filter(\.origin.isAgent).map { ($0, sightings(of: $0)) }
        var origins: [String: ProjectOrigin] = [:]
        for (path, origin) in ProjectProvenance.agentOrigins(located) {
            origins[URL(fileURLWithPath: path).resolvingSymlinksInPath().path] = origin
        }
        return origins
    }

    /// Removes the projects whose files are gone, and returns how many. Run at launch, off the main actor: it reads
    /// every entry and looks for its file. An entry it can't read, perhaps from a newer Shot, is left alone.
    @discardableResult
    public func prune(now: Date = Date()) -> Int {
        let mounted = Set((FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeUUIDStringKey], options: []) ?? [])
            .compactMap { try? $0.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString })
        var pruned = 0
        for id in ids() {
            guard let entry = entry(id) else {
                continue
            }
            let volumeMounted = entry.file.volume.map(mounted.contains) ?? true
            if !ProjectPruning.keeps(entry, sightings: sightings(of: entry), volumeMounted: volumeMounted, now: now) {
                remove(id)
                pruned += 1
            }
        }
        return pruned
    }

    // MARK: Keys

    /// The ID `file`'s project is kept under: the one stamped in it, or for a file that can't hold one, the entry whose
    /// file it is, by inode first and then by path.
    private func id(of file: URL) -> String? {
        if ProjectKey.stamps(pathExtension: file.pathExtension) {
            return ProjectStamp.id(ofFileAt: file)
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
    private func sightings(of entry: ProjectEntry) -> [ProjectSighting] {
        var urls = [URL(fileURLWithPath: entry.file.path)]
        if let moved = entry.file.resolvedBookmark(), moved.standardizedFileURL.path != urls[0].standardizedFileURL.path {
            urls.append(moved)
        }
        var sightings: [ProjectSighting] = []
        for url in urls {
            guard let file = ProjectFile(at: url, bookmark: false) else {
                continue
            }
            sightings.append(ProjectSighting(file: file, stampedID: entry.stamped ? ProjectStamp.id(ofFileAt: url) : nil))
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

/// The project ID in a file's own metadata: for PNG and JPEG, what `ImageCodec` writes as `ImageMetadata`, and a `uuid` box
/// of Shot's own for MP4 and MOV (`MovieStampBox`).
public enum ProjectStamp {
    /// The ID stamped in the image or movie at `url`, or `nil` when it has none.
    public static func id(ofFileAt url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov":
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                return nil
            }
            defer { try? handle.close() }
            return ownBoxes(in: handle).last?.id
        default:
            return ImageCodec.projectID(ofFileAt: url)
        }
    }

    /// Stamps `id` in the movie at `url`, such as a recording or an export, by adding a box after its own and retiring
    /// any earlier stamp as free space. It works on a clone, which costs nothing on APFS, and swaps it in, so the movie
    /// is never left half-written. Throws when the movie's boxes don't run to its end, since a box added then would be lost.
    public static func stamp(movieAt url: URL, id: String) throws {
        let copy = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: copy) }
        try FileManager.default.copyItem(at: url, to: copy)
        let handle = try FileHandle(forUpdating: copy)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard MovieStampBox.tiles(boxes(in: handle, fileSize: fileSize), fileSize: fileSize) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for own in ownBoxes(in: handle) {
            try handle.seek(toOffset: own.box.offset + 4)
            try handle.write(contentsOf: Data("free".utf8))
        }
        try handle.seek(toOffset: fileSize)
        try handle.write(contentsOf: MovieStampBox.box(id: id))
        try handle.synchronize()
        _ = try FileManager.default.replaceItemAt(url, withItemAt: copy)
    }

    /// The movie's top-level boxes, as far as they're whole.
    private static func boxes(in handle: FileHandle, fileSize: UInt64) -> [MovieStampBox.Box] {
        var boxes: [MovieStampBox.Box] = []
        var offset: UInt64 = 0
        while offset < fileSize {
            guard (try? handle.seek(toOffset: offset)) != nil, let header = try? handle.read(upToCount: 16),
                  let box = MovieStampBox.box(header: header, at: offset, fileSize: fileSize)
            else {
                break
            }
            boxes.append(box)
            offset += box.size
        }
        return boxes
    }

    /// Shot's own `uuid` boxes in the movie, with the ID each holds.
    private static func ownBoxes(in handle: FileHandle) -> [(box: MovieStampBox.Box, id: String)] {
        guard let fileSize = try? handle.seekToEnd() else {
            return []
        }
        // An ID is a UUID; a box much longer than one isn't Shot's, and isn't worth reading.
        let longest: UInt64 = 16 + 256
        return boxes(in: handle, fileSize: fileSize).compactMap { box in
            let length = box.size - box.headerSize
            guard box.type == "uuid", length <= longest, (try? handle.seek(toOffset: box.offset + box.headerSize)) != nil,
                  let body = try? handle.read(upToCount: Int(length)), let id = MovieStampBox.id(inUUIDBody: body)
            else {
                return nil
            }
            return (box, id)
        }
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
        let bookmarkData = bookmark ? try? url.bookmarkData() : nil
        let volume = values.volumeUUIDString
        self.init(
            path: url.standardizedFileURL.path,
            bookmark: bookmarkData,
            volume: volume,
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
