import AppKit
import Observation
import os
import QuickLookUI
import ShotCore

private let log = Logger.shot("gallery")

@MainActor
@Observable
final class GalleryModel {
    private(set) var items: [GalleryItem] = [] { didSet { refilter() } }
    /// The text read from the screenshots so far, folded for search, which `TextIndexer` hands over as it reads more.
    /// Only a search uses it, and more text usually finds nothing new, so the grid redraws only when the matches change.
    @ObservationIgnored private var texts: [URL: String] = [:] {
        didSet {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty, matching() != visible {
                refilter()
            }
        }
    }
    var filter = GalleryFilter.all { didSet { measure("Gallery filter"); refilter() } }
    var sort = GallerySort.newest { didSet { measure("Gallery filter"); refilter() } }
    var query = "" {
        didSet {
            measure("Gallery filter")
            refilter()
            readTextIfSearching()
        }
    }
    /// The folder shown, by name, empty for the save folder itself, or `nil` for everything in all of them.
    var shownFolder: String? = nil { didSet { measure("Gallery filter"); refilter() } }
    /// The tags picked in the tag row; an item has to carry all of them.
    var tagFilter: Set<String> = [] { didSet { measure("Gallery filter"); refilter() } }
    /// The folders in the save folder, by name. The sidebar shows only once there's one.
    private(set) var folders: [String] = []
    /// The Finder tags of each item read so far. They're read after the list, off the main actor, and kept until the
    /// gallery closes, so a tag added in Finder shows the next time it opens.
    private(set) var tags: [URL: [String]] = [:] {
        didSet {
            allTags = GalleryTags.all(tags)
            if !tagFilter.isEmpty || !GalleryQuery(query).tags.isEmpty {
                refilter()
            }
        }
    }
    /// Every tag on the items, which the tag row and the Tag menu offer.
    private(set) var allTags: [String] = []
    /// The item whose Tag popover is open.
    var taggingItem: URL?
    /// The files the open Tag popover tags, fixed when it opens.
    @ObservationIgnored private(set) var taggingTargets: [URL] = []
    /// The files being dragged from the grid, which a folder in the sidebar takes when they're dropped on it.
    @ObservationIgnored var dragged: [URL] = []
    /// The folder new captures are saved to, by name; empty for the save folder itself.
    var captureSubfolder: String {
        get { folders.contains(storedCaptureSubfolder) ? storedCaptureSubfolder : "" }
        set { storedCaptureSubfolder = newValue }
    }
    @ObservationIgnored @Setting(PreferenceKey.captureSubfolder) private var storedCaptureSubfolder: String
    private(set) var visible: [GalleryItem] = []
    private(set) var sections: [GallerySection] = []
    private(set) var hasLoaded = false
    private(set) var folder = Preferences().saveFolder
    var selection: Set<URL> = []
    /// The item the keyboard moves from, which the grid keeps in view.
    private(set) var lead: URL?
    private var anchor: URL?
    /// Set by the grid as it lays out, so the up and down arrows know a row's width.
    var columns = 1
    var searchFocusRequest = 0
    /// Read through `SettingsStore`, so Reset All in Settings shows here while the gallery is open.
    var tileSize: Double {
        get { Gallery.tileSizes.contains(storedTileSize) ? storedTileSize : Gallery.defaultTileSize }
        set { storedTileSize = newValue }
    }
    @ObservationIgnored @Setting(PreferenceKey.galleryTileSize) private var storedTileSize: Double

    /// Opening more items than this at once asks first.
    private static let editConfirmationThreshold = 8

    @ObservationIgnored let thumbnails = ThumbnailStore()
    @ObservationIgnored private var trashHistory: [[(trashed: URL, original: URL)]] = []
    /// The part of the grid in view, which the grid sets as it scrolls, so a keyboard move scrolls only when it has to.
    @ObservationIgnored var viewport: CGRect = .zero
    @ObservationIgnored var onEdit: ((URL) -> Void)?
    @ObservationIgnored var onExportGIF: ((URL) -> Void)?

    /// One for the save folder and one for each folder in it, so a capture saved into a folder shows too.
    @ObservationIgnored private var watchers: [URL: DispatchSourceFileSystemObject] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var tagTask: Task<Void, Never>?
    @ObservationIgnored private var debounce: Task<Void, Never>?

    var selectedItems: [GalleryItem] { visible.filter { selection.contains($0.url) } }
    var allSelected: Bool { Gallery.allSelected(selection, in: visible) }

    private func matching() -> [GalleryItem] {
        Gallery.visible(items, filter: filter, sort: sort, query: query, texts: texts, folder: shownFolder, tags: tagFilter, tagsOf: tags)
    }

    private func refilter() {
        visible = matching()
        sections = Gallery.sections(visible, sort: sort)
        selection.formIntersection(visible.map(\.url))
    }

    // MARK: Loading

    /// Lists the folder now and keeps the list current while the gallery is open.
    func start() {
        TextIndexer.shared.onTexts = { [weak self] texts in
            if self?.texts != texts {
                self?.texts = texts
            }
        }
        readTextIfSearching()
        reload()
    }

    func stop() {
        TextIndexer.shared.onTexts = nil
        texts = [:]
        watchers.values.forEach { $0.cancel() }
        watchers = [:]
        debounce?.cancel()
        loadTask?.cancel()
        tagTask?.cancel()
        tags = [:]
        thumbnails.removeAll()
    }

    /// Text is read only while there's something in the search field, and stops when it's cleared.
    private func readTextIfSearching() {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            TextIndexer.shared.stop()
        } else {
            TextIndexer.shared.read(folder: folder)
        }
    }

    func reload() {
        let root = Preferences().saveFolder
        if root != folder {
            folder = root
            shownFolder = nil
        }
        let folder = folder
        loadTask?.cancel()
        loadTask = Task {
            let (found, names) = await Task.detached { (Gallery.items(in: folder), Gallery.folders(in: folder)) }.value
            guard !Task.isCancelled else {
                return
            }
            watch([folder] + names.map { Gallery.folderURL($0, in: folder) })
            if names != folders {
                folders = names
            }
            if let shownFolder, !shownFolder.isEmpty, !names.contains(shownFolder) {
                self.shownFolder = nil
            }
            if found != items {
                items = found
                readTextIfSearching()
            }
            hasLoaded = true
            selection.formIntersection(Set(found.map(\.url)))
            readTags()
        }
    }

    /// Reads the tags of the items not read yet, off the main actor, and drops those of items that have gone.
    private func readTags() {
        let unread = items.map(\.url).filter { tags[$0] == nil }
        let present = Set(items.map(\.url))
        if tags.keys.contains(where: { !present.contains($0) }) {
            tags = tags.filter { present.contains($0.key) }
        }
        guard !unread.isEmpty else {
            return
        }
        tagTask?.cancel()
        tagTask = Task {
            let read = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: unread.map { ($0, GalleryTags.tags(of: $0)) })
            }.value
            guard !Task.isCancelled else {
                return
            }
            tags.merge(read) { _, new in new }
        }
    }

    /// Watches each of `folders`, and stops watching any other.
    private func watch(_ folders: [URL]) {
        let wanted = Set(folders)
        for (url, source) in watchers where !wanted.contains(url) {
            source.cancel()
            watchers[url] = nil
        }
        for url in folders where watchers[url] == nil {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else {
                continue
            }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.reloadSoon() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            watchers[url] = source
        }
    }

    /// A capture or export writes several times; wait for it to settle.
    private func reloadSoon() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled {
                reload()
            }
        }
    }

    // MARK: Selection

    func click(_ item: GalleryItem, command: Bool, shift: Bool) {
        measure("Gallery selection")
        lead = item.url
        if shift, let anchor, let from = visible.firstIndex(where: { $0.url == anchor }), let to = visible.firstIndex(of: item) {
            selection = Set(visible[min(from, to)...max(from, to)].map(\.url))
            return
        }
        anchor = item.url
        if command {
            selection = Gallery.toggled(selection, item.url)
        } else {
            selection = [item.url]
        }
    }

    /// Times a click or arrow key ("Gallery selection"), or a change to the search, filter or sort ("Gallery filter"),
    /// until Core Animation commits the frame that shows it, as the intervals in `docs/performance.md`. Does nothing
    /// unless something is recording signposts.
    private func measure(_ name: StaticString) {
        guard Perf.signposter.isEnabled else {
            return
        }
        let interval = Perf.signposter.beginInterval(name, id: Perf.signposter.makeSignpostID())
        // Runs when this run loop pass's implicit transaction, which carries SwiftUI's update, commits.
        CATransaction.setCompletionBlock { [weak self] in
            Perf.signposter.endInterval(name, interval, "items=\(self?.visible.count ?? 0)")
        }
    }

    func selectAll() {
        selection = Set(visible.map(\.url))
    }

    func clearSelection() {
        selection = []
        anchor = nil
    }

    enum Direction { case left, right, up, down, first, last }

    func move(_ direction: Direction, extending: Bool) {
        let current = lead.flatMap { url in visible.firstIndex { $0.url == url } }
        let next: Int?
        switch direction {
        case .left: next = Gallery.moved(from: current, by: -1, count: visible.count)
        case .right: next = Gallery.moved(from: current, by: 1, count: visible.count)
        case .up, .down: next = Gallery.movedVertically(from: current, sectionSizes: sections.map(\.items.count), down: direction == .down, columns: columns)
        case .first: next = visible.isEmpty ? nil : 0
        case .last: next = visible.isEmpty ? nil : visible.count - 1
        }
        guard let next else {
            return
        }
        click(visible[next], command: false, shift: extending)
    }

    /// What an action on `item` applies to: the whole selection when `item` is in it, otherwise just `item`.
    func targets(for item: GalleryItem) -> [GalleryItem] {
        selection.contains(item.url) ? selectedItems : [item]
    }

    // MARK: Actions

    /// Whether the GIF at `url` was exported by the video editor with a project it can reopen.
    static func hasProject(_ url: URL) -> Bool {
        VersionWriter.project(of: url, in: .app) != nil
    }

    func edit(_ items: [GalleryItem]) {
        guard Gallery.canEdit(items, hasProject: Self.hasProject) else {
            Toast.error("Only GIFs exported from the video editor can be edited")
            return
        }
        guard items.count > Self.editConfirmationThreshold, let window = NSApp.keyWindow else {
            items.forEach { onEdit?($0.url) }
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Open \(items.count) items?")
        alert.informativeText = String(localized: "Each one opens in its own editor window.")
        alert.addButton(withTitle: String(localized: "Open \(items.count)"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                items.forEach { self?.onEdit?($0.url) }
            }
        }
    }

    func copy(_ items: [GalleryItem]) {
        guard let first = items.first else {
            return
        }
        if items.count == 1, first.kind == .image {
            guard Clipboard.copy(imageAt: first.url) else {
                Toast.error("Couldn't read \(first.name)")
                return
            }
        } else {
            Clipboard.copy(fileURLs: items.map(\.url))
        }
        Toast.show("Copied \(items.count) files")
    }

    func exportGIF(_ item: GalleryItem) {
        onExportGIF?(item.url)
    }

    func reveal(_ items: [GalleryItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    func rename(_ item: GalleryItem) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename")
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = NSTextField(string: item.url.deletingPathExtension().lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        guard let destination = Gallery.renamedURL(of: item.url, to: field.stringValue) else {
            Toast.error("Enter a name")
            return
        }
        guard destination != item.url else {
            return
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            Toast.error("\(destination.lastPathComponent) already exists")
            return
        }
        do {
            try FileManager.default.moveItem(at: item.url, to: destination)
            selection = [destination]
            lead = destination
            anchor = destination
            reload()
        } catch {
            Toast.error("Couldn't rename: \(error.localizedDescription)")
        }
    }

    // MARK: Folders

    /// The name the save folder itself goes by in menus.
    var rootName: String { folder.lastPathComponent }

    /// Moves `items` into the folder `name`, or out of folders into the save folder itself when it's empty.
    func move(_ items: [GalleryItem], to name: String) {
        move(items.map(\.url), to: name)
    }

    /// Moves the files dropped on the folder `name`: everything the grid dragged when they're among it, otherwise those
    /// of `urls` that are in the gallery, such as captures dragged in from Finder. Files from elsewhere stay put.
    func drop(_ urls: [URL], on name: String) {
        let fromGrid = dragged
        dragged = []
        let paths = Set(urls.map(\.standardizedFileURL.path))
        let files: [URL]
        if fromGrid.contains(where: { paths.contains($0.standardizedFileURL.path) }) {
            files = fromGrid
        } else {
            files = items.map(\.url).filter { paths.contains($0.standardizedFileURL.path) }
        }
        guard !files.isEmpty else {
            return
        }
        move(files, to: name)
    }

    private func move(_ files: [URL], to name: String) {
        let result = Gallery.move(files, to: Gallery.folderURL(name, in: folder))
        let place = name.isEmpty ? rootName : name
        for failed in result.failed {
            log.error("Could not move \(failed.path)")
        }
        if !result.taken.isEmpty {
            Toast.error("\(result.taken.count) files weren't moved: \(place) already has files with those names")
        } else if !result.failed.isEmpty {
            Toast.error("Couldn't move \(result.failed.count) files")
        } else if !result.moved.isEmpty {
            Toast.show("Moved \(result.moved.count) files to \(place)")
        }
        let renamed = Dictionary(uniqueKeysWithValues: result.moved.map { ($0.from, $0.to) })
        selection = Set(selection.map { renamed[$0] ?? $0 })
        lead = lead.map { renamed[$0] ?? $0 }
        anchor = anchor.map { renamed[$0] ?? $0 }
        for (from, to) in renamed {
            tags[to] = tags[from]
            tags[from] = nil
        }
        reload()
    }

    /// Asks for a name and makes a folder with it, then moves `items` into it.
    func newFolder(moving items: [GalleryItem] = []) {
        let alert = NSAlert()
        alert.messageText = String(localized: "New Folder")
        alert.informativeText = String(localized: "Folders are made in \(rootName), so they show in Finder too.")
        alert.addButton(withTitle: items.isEmpty ? String(localized: "Create") : String(localized: "Create and Move"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = NSTextField(string: "")
        field.placeholderString = String(localized: "Folder name")
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        guard let name = Gallery.folderName(field.stringValue) else {
            Toast.error("Enter a name")
            return
        }
        let url = Gallery.folderURL(name, in: folder)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            Toast.error("Couldn't create the folder: \(error.localizedDescription)")
            return
        }
        if items.isEmpty {
            reload()
        } else {
            move(items, to: name)
        }
    }

    func revealFolder(_ name: String) {
        NSWorkspace.shared.open(Gallery.folderURL(name, in: folder))
    }

    // MARK: Tags

    /// Opens the Tag popover on `item`, for it or the selection it's in.
    func startTagging(_ item: GalleryItem) {
        taggingTargets = targets(for: item).map(\.url)
        taggingItem = item.url
    }

    /// Adds `tag` to every one of `items`, or takes it off them all when they all carry it.
    func toggleTag(_ tag: String, on items: [URL]) {
        apply(GalleryTags.toggling(tag, on: items, tagsOf: tags))
    }

    /// Adds the tag typed in the Tag popover to every one of `items`.
    func addTag(_ typed: String, to items: [URL]) {
        let tag = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else {
            return
        }
        // A tag typed in another case is the one already used, as in Finder.
        let existing = allTags.first { $0.caseInsensitiveCompare(tag) == .orderedSame } ?? tag
        var changed: [URL: [String]] = [:]
        for url in items {
            let current = tags[url] ?? []
            let next = GalleryTags.adding(existing, to: current)
            if next != current {
                changed[url] = next
            }
        }
        apply(changed)
    }

    private func apply(_ changed: [URL: [String]]) {
        var failed = 0
        for (url, next) in changed {
            do {
                try GalleryTags.setTags(next, of: url)
                tags[url] = next
            } catch {
                failed += 1
                log.error("Could not tag \(url.path): \(error.localizedDescription)")
            }
        }
        if failed > 0 {
            Toast.error("Couldn't tag \(failed) files")
        }
        tagFilter = tagFilter.filter { tag in allTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
    }

    func toggleTagFilter(_ tag: String) {
        tagFilter = tagFilter.symmetricDifference([tag])
    }

    /// Moves the files to the Trash, where Finder can put them back, then selects the item that takes the first one's place.
    func trash(_ items: [GalleryItem]) {
        guard let first = items.first else {
            return
        }
        let position = visible.firstIndex { $0.url == first.url } ?? 0
        var trashed: Set<URL> = []
        var moves: [(trashed: URL, original: URL)] = []
        for item in items {
            do {
                var result: NSURL?
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &result)
                trashed.insert(item.url)
                if let result {
                    moves.append((trashed: result as URL, original: item.url))
                }
            } catch {
                log.error("Could not trash \(item.url.path): \(error.localizedDescription)")
            }
        }
        self.items.removeAll { trashed.contains($0.url) }
        selection.subtract(trashed)
        if trashed.count < items.count {
            let failed = items.count - trashed.count
            Toast.error("Couldn't move \(failed) files to the Trash")
        } else {
            Toast.show("Moved \(items.count) files to the Trash (⌘Z to undo)")
        }
        if !moves.isEmpty {
            trashHistory.append(moves)
        }
        if selection.isEmpty, !visible.isEmpty {
            click(visible[min(position, visible.count - 1)], command: false, shift: false)
        }
    }

    var canUndoTrash: Bool { !trashHistory.isEmpty }

    func undoTrash() {
        guard let moves = trashHistory.popLast() else {
            return
        }
        let restored = Gallery.restore(moves)
        guard !restored.isEmpty else {
            Toast.error("Couldn't restore the files from the Trash")
            return
        }
        selection = Set(restored)
        reload()
        Toast.show("Restored \(restored.count) files from the Trash")
    }

    func zoom(by step: Double) {
        tileSize = min(max(tileSize + step, Gallery.tileSizes.lowerBound), Gallery.tileSizes.upperBound)
    }
}
