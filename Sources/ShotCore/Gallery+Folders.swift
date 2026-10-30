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

    /// The folder `name` in `root`, or `root` itself when `name` is empty.
    public static func folderURL(_ name: String, in root: URL) -> URL {
        name.isEmpty ? root : root.appendingPathComponent(name, isDirectory: true)
    }

    /// Where new captures go: the folder `subfolder` in `root` when it's set and still there, otherwise `root`, so a
    /// folder deleted in Finder never loses a capture.
    public static func captureFolder(in root: URL, subfolder: String, fileManager: FileManager = .default) -> URL {
        guard let name = folderName(subfolder), name == subfolder else {
            return root
        }
        let folder = folderURL(name, in: root)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue ? folder : root
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
}
