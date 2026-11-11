import AppKit
import ShotCore
import SwiftUI
import UniformTypeIdentifiers

/// The gallery's see-through sidebar: Library picks a kind of capture, Folders the folders in the save folder as a tree, and
/// Tags the captures with a tag. One row is picked at a time. At the foot, how much room the captures take.
struct GallerySidebar: View {
    let model: GalleryModel
    @State private var listTargeted = false
    @State private var managingTags = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    SidebarHeading(title: "Library")
                    ForEach(GalleryFilter.allCases, id: \.self) { filter in
                        GalleryLibraryRow(model: model, filter: filter, count: model.counts.count(of: .library(filter)), selected: model.source == .library(filter))
                    }
                    folders
                    if !model.allTags.isEmpty {
                        tags
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            // Dropping on the empty space below the rows takes a folder out of the one it's in, to the top, where the save
            // folder's row lights up to show it.
            .modifier(FolderDrop(model: model, folder: "", targeted: $listTargeted))
            GalleryStorage(model: model)
        }
    }

    @ViewBuilder
    private var folders: some View {
        SidebarHeading(title: "Folders") {
            SidebarIconButton(symbol: "folder.badge.plus", label: "New Folder") {
                Self.beginNewFolder(model, in: "")
            }
        }
        GalleryFolderRow(model: model, title: model.rootName, folder: "", extraTargeted: listTargeted)
        if model.folderEdit == .new(parent: "") {
            FolderNameField(model: model, edit: .new(parent: ""), level: 1)
        }
        ForEach(model.listedFolders, id: \.self) { path in
            GalleryFolderRow(model: model, title: Gallery.folderLeaf(of: path), folder: path)
            if model.folderEdit == .new(parent: path) {
                FolderNameField(model: model, edit: .new(parent: path), level: GalleryFolderRow.level(of: path) + 1)
            }
        }
        if model.folders.isEmpty && model.folderEdit == nil {
            Text("Make a folder, then drag captures onto it.")
                .font(.scaled(11.5))
                .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var tags: some View {
        SidebarHeading(title: "Tags") {
            SidebarIconButton(symbol: "ellipsis.circle", label: "Rename or remove tags") {
                managingTags.toggle()
            }
            .popover(isPresented: $managingTags, arrowEdge: .trailing) {
                GalleryTagManager(model: model)
            }
        }
        ForEach(model.allTags, id: \.self) { tag in
            GalleryTagRow(model: model, tag: tag, count: model.counts.count(ofTag: tag), selected: model.isShowing(tag)) {
                managingTags = true
            }
        }
    }

    /// Opens the sidebar's text field for a new folder inside the folder at `parent`.
    static func beginNewFolder(_ model: GalleryModel, in parent: String) {
        model.expandedFolders.formUnion(Gallery.ancestors(of: parent) + (parent.isEmpty ? [] : [parent]))
        model.folderEdit = .new(parent: parent)
    }
}

// MARK: Rows

/// How far each level of folder moves a row to the right.
private let folderIndent: CGFloat = 16
/// The space before a row's icon, which a folder's arrow sits in.
private let rowLeading: CGFloat = 8

/// A section's name over its rows, with an optional button at its end.
private struct SidebarHeading<Accessory: View>: View {
    let title: LocalizedStringResource
    let accessory: Accessory

    init(title: LocalizedStringResource, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.scaled(11, weight: .semibold))
                .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            accessory
        }
        .padding(.leading, rowLeading)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(minHeight: 22)
    }
}

/// A small symbol button at the end of a section's heading.
private struct SidebarIconButton: View {
    let symbol: String
    let label: LocalizedStringResource
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.scaled(12, weight: .medium))
                .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                .frame(width: 22, height: 20)
                .background(hovering ? Brutal.hover : .clear, in: RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .brutalTip(label)
        .accessibilityLabel(Text(label))
    }
}

/// A row's icon, name and count, laid out the same in every section.
private struct SidebarRowLabel<Icon: View>: View {
    let title: String
    let count: Int?
    let selected: Bool
    /// Keeps the count's room but hides it, while a folder's menu button sits over it.
    var hidesCount = false
    let icon: Icon

    init(title: String, count: Int?, selected: Bool, hidesCount: Bool = false, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.count = count
        self.selected = selected
        self.hidesCount = hidesCount
        self.icon = icon()
    }

    var body: some View {
        HStack(spacing: 9) {
            icon.frame(width: 18)
            Text(verbatim: title)
                .font(.scaled(13, weight: selected ? .semibold : .regular))
                .foregroundStyle(Brutal.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if let count, count > 0 {
                Text(count, format: .number)
                    .font(.scaled(11.5, tabular: true))
                    .foregroundStyle(ContrastAware(standard: selected ? Brutal.ink.opacity(0.7) : Brutal.tertiaryText, increased: Brutal.ink))
                    .opacity(hidesCount ? 0 : 1)
                    .accessibilityHidden(hidesCount)
            }
        }
    }
}

/// All Captures, Screenshots, Recordings or GIFs, with how many there are.
private struct GalleryLibraryRow: View {
    let model: GalleryModel
    let filter: GalleryFilter
    let count: Int
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            model.source = .library(filter)
        } label: {
            SidebarRowLabel(title: filter.libraryTitle, count: count, selected: selected) {
                Image(systemName: symbol)
                    .font(.scaled(13, weight: .medium))
                    .foregroundStyle(selected ? AnyShapeStyle(Brutal.ink) : AnyShapeStyle(tint))
            }
            .padding(.vertical, 5)
            .padding(.horizontal, rowLeading)
            .contentShape(Rectangle())
            .modifier(SidebarRowBackground(selected: selected, hovering: hovering))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(verbatim: filter.libraryTitle))
        .accessibilityValue(Text("\(count) captures"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var symbol: String {
        switch filter {
        case .all: "square.grid.2x2"
        case .screenshots: "photo"
        case .videos: "video"
        case .gifs: "play.rectangle.on.rectangle"
        }
    }

    private var tint: Color {
        switch filter {
        case .all: Brutal.ink
        case .screenshots: Brutal.screenshotsIcon
        case .videos: Brutal.recordingsIcon
        case .gifs: Brutal.gifsIcon
        }
    }
}

/// A tag, with a dot in its Finder colour, or in grey when it isn't named after one.
private struct GalleryTagRow: View {
    let model: GalleryModel
    let tag: String
    let count: Int
    let selected: Bool
    let manage: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            model.source = .tag(tag)
        } label: {
            SidebarRowLabel(title: tag, count: count, selected: selected) {
                TagDot(tag: tag, size: 10)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, rowLeading)
            .contentShape(Rectangle())
            .modifier(SidebarRowBackground(selected: selected, hovering: hovering))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Rename or Remove Tags…", action: manage)
            Button("Remove “\(tag)”…") { model.deleteTag(tag) }
        }
        .accessibilityLabel(Text(verbatim: tag))
        .accessibilityValue(Text("\(count) captures"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A folder in the sidebar, which shows what's directly in it and takes captures and folders dropped on it. The save
/// folder itself is the empty path, at the top of the tree and always open.
private struct GalleryFolderRow: View {
    let model: GalleryModel
    let title: String
    let folder: String
    /// Whether something is held over the empty space below the rows, which drops on the save folder, so its row shows it.
    var extraTargeted = false
    @State private var hovering = false
    @State private var targeted = false
    @State private var openTask: Task<Void, Never>?

    /// How deep a folder is: 0 for the save folder, 1 for a folder in it, and so on.
    static func level(of path: String) -> Int {
        path.isEmpty ? 0 : Gallery.ancestors(of: path).count + 1
    }

    private var isFolder: Bool { !folder.isEmpty }

    private var hiddenCount: Text {
        let count = model.counts.count(of: .folder(folder))
        guard hovering || model.source == .folder(folder), count > 0 else {
            return Text(verbatim: "")
        }
        return Text(count, format: .number)
    }

    var body: some View {
        if model.folderEdit == .rename(folder) {
            FolderNameField(model: model, edit: .rename(folder), level: Self.level(of: folder))
        } else {
            row
        }
    }

    private var row: some View {
        let selected = model.source == .folder(folder)
        let leading = rowLeading + CGFloat(Self.level(of: folder)) * folderIndent
        return HStack(spacing: 0) {
            // Not a Button, which would swallow the mouse-down a drag starts with.
            SidebarRowLabel(title: title, count: model.counts.count(of: .folder(folder)), selected: selected, hidesCount: hovering || selected) {
                Image(systemName: "folder")
                    .font(.scaled(13, weight: .medium))
                    .foregroundStyle(selected ? AnyShapeStyle(Brutal.ink) : AnyShapeStyle(Brutal.secondaryText))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if NSApp.currentEvent?.clickCount == 2, isFolder {
                    model.folderEdit = .rename(folder)
                } else {
                    model.source = .folder(folder)
                    model.expandedFolders.formUnion(Gallery.ancestors(of: folder))
                }
            }
            .modifier(FolderDrag(model: model, folder: isFolder ? folder : nil))
            .accessibilityElement(children: .combine)
            // The count fades out under the "…" button on a selected or hovered row, so VoiceOver gets it here instead.
            .accessibilityValue(hiddenCount)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.source = .folder(folder) }
            if folder == model.captureSubfolder, isFolder {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.scaled(11, weight: .semibold))
                    .foregroundStyle(Brutal.ink)
                    .padding(.leading, 4)
                    .brutalTip("New captures are saved here")
                    .accessibilityLabel(Text("New captures are saved here"))
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, leading)
        .padding(.trailing, rowLeading)
        // Over the count, so showing it doesn't change the row's height or move its name.
        .overlay(alignment: .trailing) {
            if hovering || selected {
                menu.padding(.trailing, 2)
            }
        }
        .overlay(alignment: .leading) {
            disclosure.padding(.leading, leading - 15)
        }
        .modifier(SidebarRowBackground(selected: selected, hovering: hovering, targeted: targeted || extraTargeted))
        .onHover { hovering = $0 }
        .modifier(FolderDrop(model: model, folder: folder, targeted: $targeted))
        // Holding something over a closed folder opens it, so it can be dropped deeper.
        .onChange(of: targeted) {
            openTask?.cancel()
            guard targeted, isFolder, model.hasFolders(in: folder), !model.expandedFolders.contains(folder) else {
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
            GalleryFolderMenu(model: model, folder: folder)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The arrow that opens or closes the folders inside this one, in the space before its icon. The save folder is always
    /// open, so it has none.
    @ViewBuilder
    private var disclosure: some View {
        if isFolder, model.hasFolders(in: folder) {
            let open = model.expandedFolders.contains(folder)
            Button {
                if open {
                    model.expandedFolders.remove(folder)
                } else {
                    model.expandedFolders.insert(folder)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.scaled(9, weight: .bold))
                    .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: 14, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(open ? "Collapse \(title)" : "Expand \(title)"))
        }
    }

    private var menu: some View {
        BrutalDropdown(title: "Folder options", entries: GalleryFolderMenu.entries(model: model, folder: folder)) {
            Image(systemName: "ellipsis")
                .font(.scaled(12, weight: .bold))
                .foregroundStyle(Brutal.ink)
                .frame(width: 24, height: 18)
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
    /// How deep the folder is, which indents the field to where its row goes.
    let level: Int
    @State private var name: String
    @FocusState private var focused: Bool

    init(model: GalleryModel, edit: GalleryModel.FolderEdit, level: Int) {
        self.model = model
        self.edit = edit
        self.level = level
        if case let .rename(path) = edit {
            _name = State(initialValue: Gallery.folderLeaf(of: path))
        } else {
            _name = State(initialValue: "")
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "folder")
                .font(.scaled(13, weight: .medium))
                .foregroundStyle(Brutal.secondaryText)
                .frame(width: 18)
            TextField("Folder name", text: $name)
                .font(Brutal.body)
                .focused($focused)
                .brutalField(focused: focused)
                .onSubmit(commit)
                .onExitCommand { model.folderEdit = nil }
        }
        .padding(.leading, rowLeading + CGFloat(level) * folderIndent)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        // On the next turn of the run loop: the click that opened the field settles focus after it appears, and otherwise hands
        // it to the search field.
        .task {
            await Task.yield()
            focused = true
        }
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
                model.source = .folder(path)
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
    let folder: String
    @Binding var targeted: Bool

    func body(content: Content) -> some View {
        content.dropDestination(for: URL.self) { urls, _ in
            model.drop(urls, on: folder)
            return true
        } isTargeted: { targeted = $0 }
    }
}

// MARK: Storage

/// The save folder's name, how much room the captures in it take, and a bar of that against the disk, with a link that
/// shows the largest captures first.
private struct GalleryStorage: View {
    let model: GalleryModel

    var body: some View {
        let bytes = model.counts.bytes
        let share = model.counts.share(ofCapacity: model.diskCapacity)
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: folderName)
                    .foregroundStyle(ContrastAware(standard: Brutal.secondaryText, increased: Brutal.ink))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 4)
                Text(verbatim: size)
                    .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                    .monospacedDigit()
            }
            .font(.scaled(11.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Captures in \(folderName)"))
            .accessibilityValue(Text(verbatim: size))
            Capsule(style: .circular)
                .fill(Brutal.quietTrack)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        // A sliver shows even when the captures are a tiny part of the disk.
                        Capsule(style: .circular)
                            .fill(Brutal.ink)
                            .frame(width: bytes > 0 ? max(4, geometry.size.width * share) : 0)
                    }
                }
                .accessibilityHidden(true)
            if bytes > 0 {
                Button("Make room…") { model.makeRoom() }
                    .buttonStyle(PanelLinkStyle())
                    .brutalTip("Show every capture, largest first")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .overlay(alignment: .top) {
            Brutal.hairline.frame(height: 1).padding(.horizontal, 10)
        }
    }

    /// The save folder's path, from the home folder when it's inside it, such as `Pictures/Shot`.
    private var folderName: String {
        let path = (model.folder.path as NSString).abbreviatingWithTildeInPath
        return path.hasPrefix("~/") ? String(path.dropFirst(2)) : path
    }
}
