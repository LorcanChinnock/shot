import Foundation
import os
import ShotCore

private let log = Logger.shot("text-index")

/// Reads the text in the save folder's screenshots so search can find them by it. It reads only while the gallery's
/// search field has something in it, at background priority and in the app's own process, and stops when the search is
/// cleared or the gallery closes, so a Mac that never searches never runs Vision. What it reads is kept in `store`, so
/// a screenshot is read once and the next search starts from what's there.
@MainActor
final class TextIndexer {
    static let shared = TextIndexer()

    /// This app's index, so ShotDev's stays apart from the release's.
    nonisolated static let store = TextIndexStore(bundleID: Bundle.main.bundleIdentifier ?? "dev.lorcan.Shot.dev")

    /// Set by the gallery while it's open: the folded text of each screenshot read so far, by URL, each time more is
    /// read. Nothing is loaded while it's `nil`, so the app holds no text while the gallery is closed.
    var onTexts: (([URL: String]) -> Void)? {
        didSet {
            if onTexts == nil {
                stop()
            }
        }
    }

    private var folder: URL?
    private var readTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    /// The folder changed while a run was reading it, so another run follows.
    private var rerun = false

    /// Hands the gallery what's been read so far in `folder`, then reads the screenshots that haven't been. Called when a
    /// search starts and when the folder's contents change during one.
    func read(folder: URL) {
        guard onTexts != nil else {
            return
        }
        self.folder = folder
        guard readTask == nil else {
            rerun = true
            return
        }
        rerun = false
        loadTexts()
        let work = Task.detached(priority: .utility) {
            try await Self.store.update(folder: folder) {
                Task { @MainActor in TextIndexer.shared.loadTexts() }
            }
        }
        readTask = Task {
            do {
                _ = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            } catch is CancellationError {
                return
            } catch {
                log.error("Reading screenshots' text stopped: \(error.localizedDescription)")
            }
            // A run that `stop()` cancelled has already been replaced, and mustn't touch the newer one's handle.
            guard !Task.isCancelled else {
                return
            }
            readTask = nil
            if rerun, let folder = self.folder {
                read(folder: folder)
            }
        }
    }

    /// Stops reading, keeping what's been read so far.
    func stop() {
        readTask?.cancel()
        readTask = nil
        loadTask?.cancel()
        rerun = false
    }

    /// Hands the gallery the text read so far for the folder's screenshots as they are now, folded for search. Reads the
    /// index off the main actor.
    private func loadTexts() {
        guard let folder, onTexts != nil else {
            return
        }
        loadTask?.cancel()
        loadTask = Task {
            let texts = await Task.detached(priority: .utility) {
                let items = Gallery.items(in: folder).filter { $0.kind == .image }
                let folded = Self.store.load().folded(items.map(\.textFile))
                var texts: [URL: String] = [:]
                for item in items {
                    texts[item.url] = folded[item.url.path]
                }
                return texts
            }.value
            if !Task.isCancelled {
                onTexts?(texts)
            }
        }
    }
}
