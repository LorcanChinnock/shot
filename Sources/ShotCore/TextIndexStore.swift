import Foundation
import os

private let log = Logger.shot("text-index")

/// Where the text index is kept: app-private in `~/Library/Application Support/<bundle ID>/text-index.json`, beside the
/// recording marks, never in the capture folder or the files. One JSON file, written atomically, so the MCP server can
/// read it while the indexer writes.
public struct TextIndexStore: Sendable {
    public let url: URL
    /// Reads the screenshots for Vision.
    let codec: any ImageCoding

    public init(url: URL, codec: any ImageCoding) {
        self.url = url
        self.codec = codec
    }

    /// The index of the app with `bundleID`, so Shot and ShotDev keep their own, as `ProjectStore` does.
    public init(bundleID: String, codec: any ImageCoding) {
        self.init(url: URL.applicationSupportDirectory.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("text-index.json"), codec: codec)
    }

    /// The index, or an empty one when there's none yet or it can't be read.
    public func load() -> TextIndex {
        TextIndex.decoded(try? Data(contentsOf: url))
    }

    public func save(_ index: TextIndex) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try index.encoded().write(to: url, options: .atomic)
    }

    /// Reads the text of each screenshot directly inside `folder` that the index hasn't, newest first, with Vision on
    /// this Mac. It saves after every `saveEvery` and at the end, calling `saved` each time, so the gallery can show what's
    /// been read and a run cut short keeps it. An image Vision can't read is kept as having no text, so it isn't tried
    /// again until it changes. Returns how many it read.
    @discardableResult
    public func update(folder: URL, saveEvery: Int = 10, saved: @Sendable () -> Void = {}) async throws -> Int {
        var index = load()
        let before = index
        let files = Gallery.items(in: folder).filter { $0.kind == .image }.map(\.textFile)
        let unread = index.reconcile(folder: folder.path, files: files)
        if index != before {
            try save(index)
            saved()
        }
        for (count, file) in unread.enumerated() {
            try Task.checkCancellation()
            let url = URL(fileURLWithPath: file.path)
            do {
                index.set(try await TextRecognizer.recognize(fileAt: url, codec: codec)?.string ?? "", for: file)
            } catch {
                try Task.checkCancellation()
                log.error("Couldn't read the text in \(url.lastPathComponent): \(error.localizedDescription)")
                index.set("", for: file)
            }
            if (count + 1) % saveEvery == 0 || count == unread.count - 1 {
                try save(index)
                saved()
            }
        }
        return unread.count
    }
}
