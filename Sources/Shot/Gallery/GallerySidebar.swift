import AppKit
import ShotCore
import SwiftUI
import UniformTypeIdentifiers

/// The folders in the save folder as a tree under the save folder itself. Each one can be opened, renamed in place, moved
/// by dragging it onto another, given new folders, made the place new captures go to, and put in the Trash.
struct GallerySidebar: View {
    let model: GalleryModel
    @State private var listTargeted = false

    var body: some View {
        let lasts = Self.lastSiblings(model.folders)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Folders")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.faded(0.7))
                Spacer(minLength: 0)
                SidebarIconButton(symbol: "folder.badge.plus", label: "New Folder") {
                    Self.beginNewFolder(model, in: "")
                }
            }
            .padding(.horizontal, 3)
            .padding(.bottom, 2)
            GalleryFolderRow(model: model, title: String(localized: "All"), symbol: "square.grid.2x2", folder: nil, lasts: lasts)
            GalleryFolderRow(model: model, title: model.rootName, symbol: "tray", folder: "", lasts: lasts, extraTargeted: listTargeted)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.folderEdit == .new(parent: "") {
                        FolderNameField(model: model, edit: .new(parent: ""), kinds: TreeGuides.kinds(of: "", new: true, lasts: lasts, hasSiblingsAfter: !model.folders.isEmpty))
                    }
                    ForEach(model.listedFolders, id: \.self) { path in
                        GalleryFolderRow(model: model, title: Gallery.folderLeaf(of: path), symbol: "folder", folder: path, lasts: lasts)
                        if model.folderEdit == .new(parent: path) {
                            FolderNameField(model: model, edit: .new(parent: path), kinds: TreeGuides.kinds(of: path, new: true, lasts: lasts, hasSiblingsAfter: model.hasFolders(in: path)))
                        }
                    }
                }
                // The scroll view clips what's outside its edge, so the selected row's border and shadow need room inside it.
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
            // Dropping on the empty space below the folders takes a folder out of the one it's in, to the top, where the
            // save folder's row lights up to show it.
            .modifier(FolderDrop(model: model, folder: "", targeted: $listTargeted))
            if model.folders.isEmpty && model.folderEdit == nil {
                Text("Make a folder, then drag captures onto it.")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.faded(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 8)
        .padding(.leading, 3)
        // Room for the selected row's shadow, which the gallery's edge would cut off.
        .padding(.trailing, 6)
    }

    /// The folders that come last among those in the same folder, which end the line that joins a folder's folders.
    static func lastSiblings(_ folders: [String]) -> Set<String> {
        var last: [String: String] = [:]
        for path in folders {
            last[Gallery.parentFolder(of: path)] = path
        }
        return Set(last.values)
    }

    /// Opens the sidebar's text field for a new folder inside the folder at `parent`.
    static func beginNewFolder(_ model: GalleryModel, in parent: String) {
        model.expandedFolders.formUnion(Gallery.ancestors(of: parent) + (parent.isEmpty ? [] : [parent]))
        model.folderEdit = .new(parent: parent)
    }
}

/// The lines that join a folder to the folders around it, as a column of cells for each level it's in. A line runs down
/// from the arrow's column of each folder that has more folders after it, and a short tick reaches into each row.
private struct TreeGuides: View {
    enum Kind {
        /// Nothing in this column.
        case blank
        /// A line that carries on through the row.
        case pipe
        /// A line that carries on, with a tick into the row.
        case tee
        /// A line that ends at the row's tick.
        case elbow
    }

    /// How far each level moves a row to the right: the width of the arrow's slot, which the lines run down the middle of.
    static let step: CGFloat = 20

    let kinds: [Kind]

    /// The cells for a folder at `path`, or for a new folder inside it when `new`. The first is blank, so the lines start
    /// under the save folder's icon, not under its arrow's slot. `hasSiblingsAfter` says whether a new folder is followed
    /// by others in the same folder.
    static func kinds(of path: String, new: Bool = false, lasts: Set<String>, hasSiblingsAfter: Bool = false) -> [Kind] {
        // The folders the row is in, outermost first: a line runs down past each unless it was the last in its own folder.
        let outer = new ? (path.isEmpty ? [] : Gallery.ancestors(of: path) + [path]) : Gallery.ancestors(of: path)
        let last = new ? !hasSiblingsAfter : lasts.contains(path)
        return [.blank] + outer.map { lasts.contains($0) ? Kind.blank : Kind.pipe } + [last ? .elbow : .tee]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(kinds.indices, id: \.self) { index in
                Canvas { context, size in
                    let x = Self.step / 2, middle = size.height / 2
                    var path = Path()
                    switch kinds[index] {
                    case .blank:
                        break
                    case .pipe:
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    case .tee:
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        path.move(to: CGPoint(x: x, y: middle))
                        path.addLine(to: CGPoint(x: size.width, y: middle))
                    case .elbow:
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: middle))
                        path.addLine(to: CGPoint(x: size.width, y: middle))
                    }
                    context.stroke(path, with: .color(Brutal.ink.opacity(0.3)), lineWidth: 2)
                }
                .frame(width: Self.step)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A small square button with a symbol, for the sidebar's header.
private struct SidebarIconButton: View {
    let symbol: String
    let label: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.scaled(12, weight: .bold))
                .foregroundStyle(Brutal.ink)
                .frame(width: 26, height: 26)
                .brutalSurface(Brutal.paper.opacity(0.85), radius: Brutal.Radius.button, shadow: 2)
        }
        .buttonStyle(.plain)
        .brutalTip(label)
        .accessibilityLabel(Text(label))
    }
}

/// A folder in the sidebar, which shows what's in it and takes captures and folders dropped on it. All shows everything
/// and takes no drops.
private struct GalleryFolderRow: View {
    let model: GalleryModel
    let title: String
    let symbol: String
    /// The folder's path, empty for the save folder itself, or `nil` for All.
    let folder: String?
    let lasts: Set<String>
    /// Whether something is held over the empty space below the list, which drops on the save folder, so its row shows it.
    var extraTargeted = false
    @State private var hovering = false
    @State private var targeted = false
    @State private var openTask: Task<Void, Never>?

    private var isFolder: Bool { !(folder ?? "").isEmpty }
    private var kinds: [TreeGuides.Kind] { isFolder ? TreeGuides.kinds(of: folder ?? "", lasts: lasts) : [] }

    var body: some View {
        if let folder, model.folderEdit == .rename(folder) {
            FolderNameField(model: model, edit: .rename(folder), kinds: kinds)
        } else {
            row
        }
    }

    private var row: some View {
        let selected = model.shownFolder == folder
        return HStack(spacing: 0) {
            TreeGuides(kinds: kinds)
            content(selected: selected)
                .padding(.vertical, 1)
        }
        .frame(height: 32)
        .onHover { hovering = $0 }
        .modifier(FolderDrop(model: model, folder: folder, targeted: $targeted))
        // Holding something over a closed folder opens it, so it can be dropped deeper.
        .onChange(of: targeted) {
            openTask?.cancel()
            guard targeted, let folder, isFolder, model.hasFolders(in: folder), !model.expandedFolders.contains(folder) else {
                return
            }
            openTask = Task {
                try? await Task.sleep(for: .milliseconds(700))
                if !Task.isCancelled {
                    model.expandedFolders.insert(folder)
                }
            }
        }
        .contextMenu {
            if let folder {
                GalleryFolderMenu(model: model, folder: folder)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func content(selected: Bool) -> some View {
        HStack(spacing: 0) {
            disclosure
            // Not a Button, which would swallow the mouse-down a drag starts with.
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.scaled(12, weight: .semibold))
                    .frame(width: 20)
                Text(verbatim: title)
                    .font(.scaled(13, weight: selected || folder == "" ? .heavy : .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Brutal.ink)
            .contentShape(Rectangle())
            .onTapGesture {
                if NSApp.currentEvent?.clickCount == 2, let folder, isFolder {
                    model.folderEdit = .rename(folder)
                } else {
                    model.shownFolder = folder
                    if let folder {
                        model.expandedFolders.formUnion(Gallery.ancestors(of: folder))
                    }
                }
            }
            .modifier(FolderDrag(model: model, folder: isFolder ? folder : nil))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.shownFolder = folder }
            if let folder, folder == model.captureSubfolder {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.scaled(11, weight: .bold))
                    .foregroundStyle(Brutal.ink)
                    .padding(.horizontal, 3)
                    .brutalTip("New captures are saved here")
                    .accessibilityLabel(Text("New captures are saved here"))
            }
            if let folder {
                menu(for: folder)
                    .opacity(hovering || selected ? 1 : 0)
            }
        }
        .padding(.trailing, 4)
        .frame(maxHeight: .infinity)
        .background {
            if targeted || extraTargeted {
                Color.clear.brutalSurface(Brutal.violet, radius: Brutal.Radius.panel, shadow: 0)
            } else if selected {
                Color.clear.brutalSurface(Brutal.paper.opacity(0.6), glass: true, radius: Brutal.Radius.panel, shadow: 3)
            } else if hovering {
                RoundedRectangle(cornerRadius: Brutal.Radius.panel, style: .circular).fill(Brutal.ink.opacity(0.06))
            }
        }
    }

    /// The arrow that opens or closes the folders inside this one; a gap of the same width when there are none, so names
    /// line up. The save folder is always open, so it has the gap too.
    @ViewBuilder
    private var disclosure: some View {
        if let folder, isFolder, model.hasFolders(in: folder) {
            let open = model.expandedFolders.contains(folder)
            Button {
                if open {
                    model.expandedFolders.remove(folder)
                } else {
                    model.expandedFolders.insert(folder)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.scaled(9, weight: .black))
                    .foregroundStyle(Brutal.faded(0.7))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: TreeGuides.step, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(open ? "Collapse" : "Expand"))
        } else {
            Color.clear.frame(width: TreeGuides.step, height: 24)
        }
    }

    private func menu(for folder: String) -> some View {
        BrutalDropdown(title: "Folder options", entries: GalleryFolderMenu.entries(model: model, folder: folder)) {
            Image(systemName: "ellipsis")
                .font(.scaled(12, weight: .black))
                .foregroundStyle(Brutal.ink)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// What can be done to a folder, as the "…" button's menu and the right-click menu both offer it.
private struct GalleryFolderMenu: View {
    let model: GalleryModel
    let folder: String

    var body: some View {
        Button("New Folder Inside") { GallerySidebar.beginNewFolder(model, in: folder) }
        if !folder.isEmpty {
            Button("Rename") { model.folderEdit = .rename(folder) }
        }
        Button("Save New Captures Here") { model.captureSubfolder = folder }
            .disabled(model.captureSubfolder == folder)
        Button("Show in Finder") { model.revealFolder(folder) }
        if !folder.isEmpty {
            Divider()
            Button("Move to Trash…") { model.deleteFolder(folder) }
        }
    }

    static func entries(model: GalleryModel, folder: String) -> [BrutalMenuEntry] {
        var entries: [BrutalMenuEntry] = [
            .item("New Folder Inside", symbol: "folder.badge.plus") { GallerySidebar.beginNewFolder(model, in: folder) },
        ]
        if !folder.isEmpty {
            entries.append(.item("Rename", symbol: "pencil") { model.folderEdit = .rename(folder) })
        }
        entries.append(.item("Save New Captures Here", symbol: "arrow.down.circle", selected: model.captureSubfolder == folder) {
            model.captureSubfolder = folder
        })
        entries.append(.item("Show in Finder", symbol: "magnifyingglass") { model.revealFolder(folder) })
        if !folder.isEmpty {
            entries.append(.divider)
            entries.append(.item("Move to Trash…", symbol: "trash") { model.deleteFolder(folder) })
        }
        return entries
    }
}

/// A text field in the sidebar that names a new folder or renames one. Return or leaving the field keeps the name, and
/// Escape drops it.
private struct FolderNameField: View {
    let model: GalleryModel
    let edit: GalleryModel.FolderEdit
    let kinds: [TreeGuides.Kind]
    @State private var name: String
    @FocusState private var focused: Bool

    init(model: GalleryModel, edit: GalleryModel.FolderEdit, kinds: [TreeGuides.Kind]) {
        self.model = model
        self.edit = edit
        self.kinds = kinds
        if case let .rename(path) = edit {
            _name = State(initialValue: Gallery.folderLeaf(of: path))
        } else {
            _name = State(initialValue: "")
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            TreeGuides(kinds: kinds)
            HStack(spacing: 5) {
                Color.clear.frame(width: TreeGuides.step, height: 24)
                Image(systemName: "folder")
                    .font(.scaled(12, weight: .semibold))
                    .frame(width: 20)
                TextField("Folder name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.scaled(13, weight: .semibold))
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { model.folderEdit = nil }
            }
            .foregroundStyle(Brutal.ink)
            .padding(.horizontal, 4)
            .frame(maxHeight: .infinity)
            .brutalSurface(Brutal.paper.opacity(0.85), radius: Brutal.Radius.panel, shadow: 2)
            .padding(.vertical, 1)
            .padding(.trailing, 4)
        }
        .frame(height: 32)
        .onAppear { focused = true }
        .onChange(of: focused) {
            if !focused {
                commit()
            }
        }
    }

    private func commit() {
        guard model.folderEdit == edit else {
            return
        }
        model.folderEdit = nil
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        switch edit {
        case let .new(parent):
            if let path = model.createFolder(name, in: parent) {
                model.shownFolder = path
            }
        case let .rename(path):
            model.renameFolder(path, to: name)
        }
    }
}

/// Lets a folder be dragged onto another, or onto the save folder to bring it back to the top. It also carries the
/// folder, so dropping it in Finder shows it there.
private struct FolderDrag: ViewModifier {
    let model: GalleryModel
    let folder: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let folder {
            content.onDrag {
                model.draggedFolder = folder
                return NSItemProvider(object: Gallery.folderURL(folder, in: model.folder) as NSURL)
            }
        } else {
            content
        }
    }
}

/// Moves the captures or the folder dropped on a folder into it.
private struct FolderDrop: ViewModifier {
    let model: GalleryModel
    let folder: String?
    @Binding var targeted: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let folder {
            content.dropDestination(for: URL.self) { urls, _ in
                model.drop(urls, on: folder)
                return true
            } isTargeted: { targeted = $0 }
        } else {
            content
        }
    }
}
