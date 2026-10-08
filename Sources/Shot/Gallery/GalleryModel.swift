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
    var filter = GalleryFilter.all { didSet { refilter() } }
    var sort = GallerySort.newest { didSet { refilter() } }
    var query = "" { didSet { refilter() } }
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
    var tileSize = Preferences().galleryTileSize {
        didSet { UserDefaults.standard.set(tileSize, forKey: PreferenceKey.galleryTileSize) }
    }

    /// Opening more items than this at once asks first.
    private static let editConfirmationThreshold = 8

    @ObservationIgnored private var trashHistory: [[(trashed: URL, original: URL)]] = []
    @ObservationIgnored var onEdit: ((URL) -> Void)?
    @ObservationIgnored var onExportGIF: ((URL) -> Void)?

    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchedFolder: URL?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var debounce: Task<Void, Never>?

    var selectedItems: [GalleryItem] { visible.filter { selection.contains($0.url) } }
    var allSelected: Bool { Gallery.allSelected(selection, in: visible) }

    private func refilter() {
        visible = Gallery.visible(items, filter: filter, sort: sort, query: query)
        sections = Gallery.sections(visible, sort: sort)
        selection.formIntersection(visible.map(\.url))
    }

    // MARK: Loading

    /// Lists the folder now and keeps the list current while the gallery is open.
    func start() {
        reload()
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        watchedFolder = nil
        debounce?.cancel()
        loadTask?.cancel()
    }

    func reload() {
        folder = Preferences().saveFolder
        if watchedFolder != folder {
            watch(folder)
        }
        let folder = folder
        loadTask?.cancel()
        loadTask = Task {
            let found = await Task.detached { Gallery.items(in: folder) }.value
            guard !Task.isCancelled else {
                return
            }
            if found != items {
                items = found
            }
            hasLoaded = true
            selection.formIntersection(Set(found.map(\.url)))
        }
    }

    private func watch(_ folder: URL) {
        watcher?.cancel()
        watcher = nil
        watchedFolder = folder
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reloadSoon() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
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

    func edit(_ items: [GalleryItem]) {
        guard Gallery.canEdit(items) else {
            Toast.error("GIFs can't be edited")
            return
        }
        guard items.count > Self.editConfirmationThreshold, let window = NSApp.keyWindow else {
            items.forEach { onEdit?($0.url) }
            return
        }
        let alert = NSAlert()
        alert.messageText = "Open \(items.count) items?"
        alert.informativeText = "Each one opens in its own editor window."
        alert.addButton(withTitle: "Open \(items.count)")
        alert.addButton(withTitle: "Cancel")
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
                Toast.error("Could not read \(first.name)")
                return
            }
        } else {
            Clipboard.copy(fileURLs: items.map(\.url))
        }
        Toast.show(items.count == 1 ? "Copied" : "Copied \(items.count) files")
    }

    func exportGIF(_ item: GalleryItem) {
        onExportGIF?(item.url)
    }

    func reveal(_ items: [GalleryItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    func rename(_ item: GalleryItem) {
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
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
            Toast.error("Rename failed: \(error.localizedDescription)")
        }
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
            Toast.error("Could not move \(items.count - trashed.count) to the Trash")
        } else {
            Toast.show(items.count == 1 ? "Moved to the Trash (⌘Z to undo)" : "Moved \(items.count) files to the Trash (⌘Z to undo)")
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
            Toast.error("Could not put the files back")
            return
        }
        selection = Set(restored)
        reload()
        Toast.show(restored.count == 1 ? "Put back" : "Put back \(restored.count) files")
    }

    func zoom(by step: Double) {
        tileSize = min(max(tileSize + step, Gallery.tileSizes.lowerBound), Gallery.tileSizes.upperBound)
    }
}

/// The system Quick Look panel for the gallery's selection.
@MainActor
final class GalleryPreview: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = GalleryPreview()
    private var urls: [URL] = []

    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    func toggle(_ urls: [URL]) {
        let panel = QLPreviewPanel.shared()!
        if isVisible {
            panel.orderOut(nil)
            return
        }
        guard !urls.isEmpty else {
            return
        }
        show(urls)
    }

    /// Shows `urls`, or follows the selection when the panel is already open.
    func show(_ urls: [URL]) {
        self.urls = urls
        let panel = QLPreviewPanel.shared()!
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }
}
