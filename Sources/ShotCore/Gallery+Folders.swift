import Foundation

/// What moving files into a folder did.
public struct GalleryMove {
    /// Each file moved, where it was and where it is now.
    public var moved: [(from: URL, to: URL)] = []
    /// Files left where they were because a file of the same name is already in the folder.
    public var taken: [URL] = []
    /// Files that couldn't be moved for another reason, such as having gone.
    public var failed: [URL] = []
}

/// Why a folder couldn't be made, renamed or moved.
public enum GalleryFolderError: Error, Equatable {
    /// The name is empty or would be hidden.
    case invalidName
    /// The place already has a folder or file of that name.
    case exists
    /// The folder was dropped into itself or a folder inside it.
    case intoItself
    /// The folder isn't there any more.
    case missing
    /// The file system refused.
    case failed
}

extension Gallery {
    /// The longest a folder name typed in the gallery can be, short of the file system's limit.
    static let maxFolderName = 120

    /// `typed` as a folder's name: trimmed, with path separators replaced, and `nil` when nothing is left or it would
    /// be hidden.
    public static func folderName(_ typed: String) -> String? {
        let name = String(typed.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .prefix(maxFolderName))
        guard !name.isEmpty, !name.hasPrefix(".") else {
            return nil
        }
        return name
    }

    /// The folder at `path` in `root`, a path of names with `/` between them, or `root` itself when `path` is empty.
    public static func folderURL(_ path: String, in root: URL) -> URL {
        path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1), isDirectory: true) }
    }

    /// The path of the folder called `name` inside the folder at `parent`, which is empty for the save folder itself.
    public static func folderPath(_ name: String, in parent: String) -> String {
        parent.isEmpty ? name : parent + "/" + name
    }

    /// The path of the folder the folder at `path` is in, empty for the save folder itself.
    public static func parentFolder(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    /// The paths of the folders the folder at `path` is in, outermost first: `Clients` and `Clients/Acme` for
    /// `Clients/Acme/Q1`.
    public static func ancestors(of path: String) -> [String] {
        let names = path.split(separator: "/")
        return names.indices.dropLast().map { names[...$0].joined(separator: "/") }
    }

    /// The name of the folder at `path`, without the folders it's in.
    public static func folderLeaf(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }

    /// Whether the folder at `path` is `folder` or in it at any depth.
    public static func folder(_ path: String, isIn folder: String) -> Bool {
        path == folder || path.hasPrefix(folder + "/")
    }

    /// Where new captures go: the folder at `subfolder` in `root` when it's set and still there, otherwise `root`, so a
    /// folder deleted in Finder never loses a capture.
    public static func captureFolder(in root: URL, subfolder: String, fileManager: FileManager = .default) -> URL {
        let names = subfolder.split(separator: "/").map(String.init)
        guard !names.isEmpty, names.allSatisfy({ folderName($0) == $0 }) else {
            return root
        }
        let folder = folderURL(subfolder, in: root)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue ? folder : root
    }

    /// What `subfolder`, the folder new captures go to, becomes when the folder at `old` is renamed or moved to `new`: the
    /// same folder in its new place, whether it's that folder or one inside it.
    public static func relocated(_ subfolder: String, from old: String, to new: String) -> String {
        folder(subfolder, isIn: old) ? new + subfolder.dropFirst(old.count) : subfolder
    }

    /// How many captures are in the folder at `path` and in the folders in it, and how many folders are inside it, for
    /// saying what deleting it takes along.
    public static func contents(of path: String, items: [GalleryItem], folders: [String]) -> (captures: Int, folders: Int) {
        (items.filter { folder($0.folder, isIn: path) }.count, folders.filter { $0 != path && folder($0, isIn: path) }.count)
    }

    /// Where each of `files` would go when moved into `destination`, as pairs; files already there are left out. A file
    /// whose name is taken in `destination`, or by another of `files`, is in `taken` instead, since replacing one capture
    /// with another would lose it.
    public static func movePlan(_ files: [URL], to destination: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> (moves: [(from: URL, to: URL)], taken: [URL]) {
        let folder = destination.standardizedFileURL.path
        var moves: [(from: URL, to: URL)] = []
        var taken: [URL] = []
        var claimed: Set<String> = []
        for file in files {
            guard file.deletingLastPathComponent().standardizedFileURL.path != folder else {
                continue
            }
            let target = destination.appendingPathComponent(file.lastPathComponent)
            let key = target.lastPathComponent.lowercased()
            if claimed.contains(key) || exists(target) {
                taken.append(file)
                continue
            }
            claimed.insert(key)
            moves.append((from: file, to: target))
        }
        return (moves, taken)
    }

    /// Moves `files` into `destination`, creating it if it isn't there. A project kept for a file follows it, since the
    /// project store finds a file by the ID stamped in it, or by its inode, which a move on the same disk keeps.
    public static func move(_ files: [URL], to destination: URL, fileManager: FileManager = .default) -> GalleryMove {
        var result = GalleryMove()
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            result.failed = files
            return result
        }
        let plan = movePlan(files, to: destination) { fileManager.fileExists(atPath: $0.path) }
        result.taken = plan.taken
        for move in plan.moves {
            do {
                try fileManager.moveItem(at: move.from, to: move.to)
                result.moved.append(move)
            } catch {
                result.failed.append(move.from)
            }
        }
        return result
    }

    /// Makes a folder called `typed` inside the folder at `parent` in `root`, and returns its path.
    public static func createFolder(_ typed: String, in parent: String, root: URL, fileManager: FileManager = .default) throws -> String {
        guard let name = folderName(typed) else {
            throw GalleryFolderError.invalidName
        }
        let path = folderPath(name, in: parent)
        let url = folderURL(path, in: root)
        guard !fileManager.fileExists(atPath: url.path) else {
            throw GalleryFolderError.exists
        }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw GalleryFolderError.failed
        }
        return path
    }

    /// Renames the folder at `path` to `typed`, and returns its new path.
    public static func renameFolder(_ path: String, to typed: String, root: URL, fileManager: FileManager = .default) throws -> String {
        guard let name = folderName(typed) else {
            throw GalleryFolderError.invalidName
        }
        return try relocate(path, to: folderPath(name, in: parentFolder(of: path)), root: root, fileManager: fileManager)
    }

    /// Moves the folder at `path`, with what's in it, into the folder at `parent`, and returns its new path.
    public static func moveFolder(_ path: String, into parent: String, root: URL, fileManager: FileManager = .default) throws -> String {
        guard !folder(parent, isIn: path) else {
            throw GalleryFolderError.intoItself
        }
        return try relocate(path, to: folderPath(folderLeaf(of: path), in: parent), root: root, fileManager: fileManager)
    }

    /// Puts the folder at `path` in the Trash, where Finder can put it back, with the captures in it.
    public static func trashFolder(_ path: String, root: URL, fileManager: FileManager = .default) throws {
        let url = folderURL(path, in: root)
        guard fileManager.fileExists(atPath: url.path) else {
            throw GalleryFolderError.missing
        }
        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        } catch {
            throw GalleryFolderError.failed
        }
    }

    private static func relocate(_ path: String, to new: String, root: URL, fileManager: FileManager) throws -> String {
        let from = folderURL(path, in: root), to = folderURL(new, in: root)
        guard fileManager.fileExists(atPath: from.path) else {
            throw GalleryFolderError.missing
        }
        guard new != path else {
            return path
        }
        // Finder ignores case in names, so a rename that changes only the case is the same place, not a clash.
        guard !fileManager.fileExists(atPath: to.path) || to.path.lowercased() == from.path.lowercased() else {
            throw GalleryFolderError.exists
        }
        do {
            try fileManager.moveItem(at: from, to: to)
        } catch {
            throw GalleryFolderError.failed
        }
        return new
    }
}
