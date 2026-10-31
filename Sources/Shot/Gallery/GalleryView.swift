import AppKit
import ShotCore
import SwiftUI
import UniformTypeIdentifiers

struct GalleryRootView: View {
    let model: GalleryModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.allTags.isEmpty {
                GalleryTagRow(model: model)
            }
            HStack(alignment: .top, spacing: 14) {
                // Folders stay out of the way until someone opens the sidebar.
                if model.showsSidebar {
                    GallerySidebar(model: model)
                        .frame(width: model.sidebarWidth)
                        .overlay(alignment: .trailing) {
                            // Centred in the gap before the grid.
                            PanelResizeHandle(width: Bindable(model).sidebarWidth, range: GalleryModel.sidebarWidths, defaultWidth: GalleryModel.defaultSidebarWidth) {
                                model.showsSidebar = false
                            }
                            .offset(x: 14)
                        }
                }
                content
            }
            GalleryFooter(model: model)
        }
        .onChange(of: model.searchFocusRequest) {
            searchFocused = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            sidebarToggle
            BrutalSegmented(selection: Bindable(model).filter, options: GalleryFilter.allCases.map { ($0, $0.title) }, color: Brutal.violet)
            Spacer(minLength: 8)
            searchField
            sortMenu
            Image(systemName: "photo")
                .font(.scaled(10, weight: .bold))
                .foregroundStyle(Brutal.faded(0.6))
            Slider(value: Bindable(model).tileSize, in: Gallery.tileSizes)
                .frame(minWidth: 40, idealWidth: 80, maxWidth: 80)
                .tint(Brutal.ink)
                .brutalTip("Thumbnail size (⌘+ and ⌘−)")
                .accessibilityLabel(Text("Thumbnail size"))
            Image(systemName: "photo")
                .font(.scaled(15, weight: .bold))
                .foregroundStyle(Brutal.faded(0.6))
        }
        .padding(.horizontal, 3)
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: 36)
    }

    private var sidebarTip: LocalizedStringResource { model.showsSidebar ? "Hide folders" : "Show folders" }

    private var sidebarToggle: some View {
        let on = model.showsSidebar
        return Button {
            model.showsSidebar.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.scaled(13, weight: .bold))
                .foregroundStyle(Brutal.ink)
                .inkOnFill(on ? Brutal.violet : nil)
                .frame(width: 30, height: 30)
                .brutalSurface(on ? Brutal.violet : Brutal.paper.opacity(0.85), radius: Brutal.Radius.button, shadow: on ? 0 : 2)
        }
        .buttonStyle(.plain)
        .brutalTip(sidebarTip)
        .accessibilityLabel(Text("Folders"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.scaled(11, weight: .bold))
                .foregroundStyle(Brutal.faded(0.6))
            TextField("Search", text: Bindable(model).query)
                .textFieldStyle(.plain)
                .font(.scaled(13, weight: .semibold))
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Brutal.faded(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 90, idealWidth: 170, maxWidth: 170, minHeight: 30, maxHeight: 30)
        .brutalSurface(Brutal.paper.opacity(0.85), radius: Brutal.Radius.button, shadow: 2)
        .brutalTip("Search by file name or by text in screenshots (⌘F)")
    }

    private var sortMenu: some View {
        BrutalDropdown(title: "Sort", entries: GallerySort.allCases.map { sort in
            .item(sort.title, selected: sort == model.sort) { model.sort = sort }
        }) {
            HStack(spacing: 5) {
                Text(model.sort.title)
                Image(systemName: "chevron.down")
                    .font(.scaled(9, weight: .black))
            }
            .font(.scaled(12, weight: .bold))
            .foregroundStyle(Brutal.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .brutalSurface(Brutal.paper.opacity(0.85), radius: Brutal.Radius.button, shadow: 2)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .brutalTip("Sort")
    }

    // MARK: Grid

    @ViewBuilder
    private var content: some View {
        if model.sections.isEmpty {
            emptyState
        } else {
            GalleryGrid(model: model)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if !model.hasLoaded {
                ProgressView().controlSize(.small)
            } else if model.items.isEmpty {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.scaled(34, weight: .bold))
                    .foregroundStyle(Brutal.faded(0.55))
                Text("No captures yet")
                    .font(Brutal.title(17))
                    .foregroundStyle(Brutal.ink)
                Text("Screenshots and recordings saved to \((model.folder.path as NSString).abbreviatingWithTildeInPath) show up here.")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.faded(0.7))
                Button("Open Folder") { NSWorkspace.shared.open(model.folder) }
                    .buttonStyle(BrutalButtonStyle(compact: true))
            } else if let shown = model.shownFolder, !model.items.contains(where: { $0.folder == shown }) {
                Image(systemName: "folder")
                    .font(.scaled(34, weight: .bold))
                    .foregroundStyle(Brutal.faded(0.55))
                Text("This folder is empty")
                    .font(Brutal.title(17))
                    .foregroundStyle(Brutal.ink)
                Text("Drag captures onto this folder in the sidebar, or use Move to in a capture's menu. Captures in the folders inside it show when you open them.")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.faded(0.7))
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.scaled(34, weight: .bold))
                    .foregroundStyle(Brutal.faded(0.55))
                Text("Nothing matches")
                    .font(Brutal.title(17))
                    .foregroundStyle(Brutal.ink)
                Text("Try another search, or show All.")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.faded(0.7))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The grid is its own view, so a selection change re-evaluates it and the tiles that changed, not the header or footer.
/// It builds only the headers and tiles near the view, at the places `GalleryGridLayout` gives them. A lazy grid
/// estimates the height of rows it hasn't built, and as that estimate changes the scroll bar jumps.
private struct GalleryGrid: View {
    static let spacing: CGFloat = 20
    /// Room above the first section and below the last.
    static let margin: CGFloat = 8
    /// How far past the view headers and tiles are built. The built range moves in steps this size, so scrolling
    /// re-evaluates the grid only every so often.
    private static let overscan: CGFloat = 400

    let model: GalleryModel
    @State private var position = ScrollPosition()
    /// The part of the layout that's built, in steps of `overscan`.
    @State private var built: Range<CGFloat> = 0..<(overscan * 3)
    /// A tile's height below its thumbnail, and a header's height. They start at typical values, and the first tile
    /// and header built correct them.
    @State private var captionHeight: CGFloat = 26
    @State private var headerHeight: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            // An overlay scroller needs the content's room; a legacy one takes the same width from the scroll view.
            let available = geometry.size.width - Brutal.groupInset * 2 - SystemScroller.shared.width
            let columns = max(1, Int((available + Self.spacing) / (model.tileSize + Self.spacing)))
            let cell = (available - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let layout = GalleryGridLayout(sectionSizes: model.sections.map(\.items.count), titled: model.sections.contains { !$0.title.isEmpty },
                                           columns: columns, rowHeight: GalleryTile.thumbnailHeight(width: cell) + captionHeight,
                                           headerHeight: headerHeight, spacing: Self.spacing)
            ScrollView {
                ZStack(alignment: .topLeading) {
                    ForEach(placed(layout.blocks(in: built), cell: cell)) { place in
                        switch place {
                        case let .header(section, top):
                            HStack(spacing: 8) {
                                Text(section.title)
                                    .font(Brutal.title(15))
                                    .foregroundStyle(Brutal.ink)
                                BrutalChip(text: "\(section.items.count)")
                                Spacer()
                            }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                            .offset(y: top)
                        case let .tile(item, x, y):
                            GalleryTile(item: item, model: model, slot: model.thumbnails.slot(for: item), width: cell,
                                        selected: model.selection.contains(item.url), selectionActive: !model.selection.isEmpty,
                                        tagging: model.taggingItem == item.url)
                                .equatable()
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { captionHeight = $0 - GalleryTile.thumbnailHeight(width: cell) }
                                .offset(x: x, y: y)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: layout.height, alignment: .top)
                .padding(.leading, Brutal.groupInset)
                .padding(.trailing, Brutal.groupInset + SystemScroller.shared.overlayRoom)
                .padding(.vertical, Self.margin)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { model.clearSelection() }
                }
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, visible in
                model.viewport = visible
                let lower = ((visible.minY - Self.margin - Self.overscan) / Self.overscan).rounded(.down) * Self.overscan
                let upper = ((visible.maxY - Self.margin + Self.overscan) / Self.overscan).rounded(.up) * Self.overscan
                if built != lower..<upper {
                    built = lower..<upper
                }
            }
            .background { LeadScroller(model: model, layout: layout, position: $position) }
            .onChange(of: columns, initial: true) {
                model.columns = columns
            }
        }
        .clipped()
    }

    /// The headers and tiles of `blocks`, each where it goes in the grid.
    private func placed(_ blocks: [GalleryGridLayout.Block], cell: CGFloat) -> [Placed] {
        blocks.flatMap { block -> [Placed] in
            let section = model.sections[block.section]
            guard let items = block.items else {
                return [.header(section, top: block.top)]
            }
            return items.map { index in
                .tile(section.items[index], x: CGFloat(index - items.lowerBound) * (cell + Self.spacing), y: block.top)
            }
        }
    }

    private enum Placed: Identifiable {
        case header(GallerySection, top: CGFloat)
        case tile(GalleryItem, x: CGFloat, y: CGFloat)

        /// A tile keeps its identity, and so its hover and loaded thumbnail, when a new capture moves it to another row.
        var id: String {
            switch self {
            case let .header(section, _): "header " + section.title
            case let .tile(item, _, _): item.url.path
            }
        }
    }
}

private struct GalleryFooter: View {
    let model: GalleryModel

    var body: some View {
        let selected = model.selectedItems
        return HStack(spacing: 10) {
            GalleryStatus(model: model)
                .font(Brutal.mono)
                .foregroundStyle(Brutal.faded(0.7))
                .lineLimit(1)
            if model.allSelected {
                Button("Deselect All") { model.clearSelection() }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                    .brutalTip("Deselect all (⇧⌘A)")
            } else {
                Button("Select All") { model.selectAll() }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                    .disabled(model.visible.isEmpty)
                    .brutalTip("Select all (⌘A)")
            }
            Spacer()
            Group {
                Button("Edit") { model.edit(selected) }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.yellow, compact: true))
                    // Whether a GIF has a project is read from the store only on a click, so one never greys it out.
                    .disabled(!Gallery.canEdit(selected) { _ in true })
                    .brutalTip("Open in the editor (Return)")
                Button("Copy") { model.copy(selected) }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                    .brutalTip("Copy (⌘C)")
                Button("Show in Finder") { model.reveal(selected) }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                    .brutalTip("Show in Finder (⌘R)")
                Button("Move to Trash") { model.trash(selected) }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.red, compact: true))
                    .brutalTip("Move to the Trash (⌘⌫)")
            }
            .disabled(selected.isEmpty)
        }
        .padding(.horizontal, 3)
        .frame(height: 34)
        .padding(.top, 6)
    }
}

private struct GalleryStatus: View {
    let model: GalleryModel

    var body: some View {
        let total = model.visible.count
        let count = model.selection.count
        Text(count > 0 ? String(localized: "\(count) of \(total) selected") : String(localized: "\(total) items"))
    }
}

/// Scrolls the grid to the lead item, unless it is already fully in view. It is a view of its own so the grid doesn't
/// re-evaluate when the lead changes.
private struct LeadScroller: View {
    let model: GalleryModel
    let layout: GalleryGridLayout
    @Binding var position: ScrollPosition

    var body: some View {
        Color.clear.onChange(of: model.lead) {
            guard let lead = model.lead, let index = model.visible.firstIndex(where: { $0.url == lead }), let row = layout.rowSpan(ofItem: index) else {
                return
            }
            // The layout starts below the top margin.
            let top = row.lowerBound + GalleryGrid.margin, bottom = row.upperBound + GalleryGrid.margin
            let view = model.viewport
            if top < view.minY {
                position.scrollTo(y: top)
            } else if bottom > view.maxY {
                position.scrollTo(y: bottom - view.height)
            }
        }
    }
}

/// A tile takes its selection state as plain values and is `Equatable`, so one click re-evaluates only the tiles whose
/// values changed. Don't read `model.selection` in here.
private struct GalleryTile: View, Equatable {
    let item: GalleryItem
    let model: GalleryModel
    let slot: ThumbnailStore.Slot
    let width: CGFloat
    let selected: Bool
    /// Whether anything is selected, which shows every tile's checkbox.
    let selectionActive: Bool
    /// Whether the Tag popover is open on this tile.
    let tagging: Bool
    @State private var hovering = false

    nonisolated static func == (lhs: GalleryTile, rhs: GalleryTile) -> Bool {
        lhs.item == rhs.item && lhs.model === rhs.model && lhs.slot === rhs.slot && lhs.width == rhs.width
            && lhs.selected == rhs.selected && lhs.selectionActive == rhs.selectionActive && lhs.tagging == rhs.tagging
    }

    private var thumbnail: Thumbnail? { slot.thumbnail }
    private var height: CGFloat { Self.thumbnailHeight(width: width) }

    static func thumbnailHeight(width: CGFloat) -> CGFloat {
        (width * 0.75).rounded()
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail.image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipped()
                } else {
                    Image(systemName: item.kind == .video ? "film" : "photo")
                        .font(.scaled(22, weight: .bold))
                        .foregroundStyle(Brutal.ink.opacity(0.35))
                }
                badges
                if hovering || selectionActive {
                    VStack {
                        HStack {
                            SelectionCheckbox(checked: selected) {
                                model.click(item, command: true, shift: false)
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                    .transition(.opacity)
                }
                if hovering, item.kind.isEditable {
                    VStack {
                        HStack {
                            Spacer()
                            CornerButton(symbol: item.kind == .video ? "scissors" : "pencil", help: item.kind == .video ? "Edit video" : "Annotate") {
                                model.edit([item])
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                    .transition(.opacity)
                }
            }
            .frame(width: width, height: height)
            .background(Brutal.paper.opacity(0.6))
            .inkBorder(RoundedRectangle(cornerRadius: Brutal.radius, style: .circular), width: selected ? 3 : 2, color: selected ? Brutal.violet : Brutal.line)
            Text(item.name)
                .font(.scaled(11, weight: .semibold))
                .foregroundStyle(Brutal.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .inkOnFill(selected ? Brutal.violet : nil)
                .background(selected ? Brutal.violet : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .circular))
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                hovering = inside
            }
        }
        // One gesture, so a click selects at once instead of waiting out the double-click interval; the second click opens.
        .onTapGesture {
            let event = NSApp.currentEvent
            if event?.clickCount == 2 {
                model.edit([item])
                return
            }
            let flags = event?.modifierFlags ?? NSEvent.modifierFlags
            model.click(item, command: flags.contains(.command), shift: flags.contains(.shift))
        }
        // The file itself, so it drops into a chat or Finder. A folder in the sidebar moves the whole selection it's in.
        .onDrag {
            model.dragged = model.targets(for: item).map(\.url)
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu { GalleryTileMenu(model: model, item: item) }
        .popover(isPresented: Binding(get: { tagging }, set: { if !$0 { model.taggingItem = nil } }), arrowEdge: .bottom) {
            GalleryTagPopover(model: model, targets: model.taggingTargets)
        }
        .task(id: item) {
            await model.thumbnails.load(item)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
        // The checkbox shows only on hover and sits inside this one element, so its ⌘-click toggle is an action here.
        .accessibilityAction(named: Text(selected ? "Deselect" : "Select")) {
            model.click(item, command: true, shift: false)
        }
    }

    @ViewBuilder
    private var badges: some View {
        VStack {
            Spacer()
            HStack {
                switch item.kind {
                case .video:
                    Image(systemName: "play.fill")
                        .font(.scaled(10, weight: .black))
                        .foregroundStyle(Brutal.ink)
                        .frame(width: 26, height: 26)
                        .brutalCircle(Brutal.yellow, shadow: 2)
                    Spacer()
                    if let duration = thumbnail?.duration {
                        BrutalChip(text: Gallery.duration(duration), color: Brutal.paper)
                    }
                case .gif:
                    BrutalChip(text: "GIF", color: Brutal.mint)
                    Spacer()
                case .image:
                    Spacer()
                }
            }
        }
        .padding(8)
    }
}

/// The context menu is its own view, so reading the selection for its targets happens when it opens, not on every click.
private struct GalleryTileMenu: View {
    let model: GalleryModel
    let item: GalleryItem

    var body: some View {
        let targets = model.targets(for: item)
        if Gallery.canEdit(targets, hasProject: GalleryModel.hasProject) {
            Button(targets.count == 1 ? (item.kind == .image ? "Annotate" : "Edit Video") : "Edit") { model.edit(targets) }
        }
        if targets.count == 1, item.kind == .video {
            Button("Export GIF") { model.exportGIF(item) }
        }
        Divider()
        Button("Copy") { model.copy(targets) }
        Button("Quick Look") { GalleryPreview.shared.show(targets.map(\.url)) }
        if targets.count == 1, item.kind == .image {
            Button("Pin") { PinController.shared.pin(item.url) }
        }
        if targets.count == 1 {
            Button("Rename…") { model.rename(item) }
        }
        Menu("Move to") {
            ForEach([""] + model.folders, id: \.self) { path in
                // A folder inside another reads as its path, such as Clients › Acme.
                Button(path.isEmpty ? model.rootName : path.replacingOccurrences(of: "/", with: " › ")) { model.move(targets, to: path) }
                    .disabled(targets.allSatisfy { $0.folder == path })
            }
            Divider()
            Button("New Folder…") { model.newFolder(moving: targets) }
        }
        Button("Tag…") { model.startTagging(item) }
        Button("Show in Finder") { model.reveal(targets) }
        Divider()
        Button("Move to Trash") { model.trash(targets) }
    }
}

/// Toggles one tile in or out of the selection without touching the rest, like ⌘-click.
private struct SelectionCheckbox: View {
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.scaled(10, weight: .black))
                .foregroundStyle(Brutal.ink)
                .opacity(checked ? 1 : 0)
                .frame(width: 22, height: 22)
                .brutalSurface(checked ? Brutal.violet : Brutal.paper, radius: Brutal.Radius.chip, shadow: 2)
        }
        .buttonStyle(.plain)
        // Focus stays on the grid, so the keyboard shortcuts keep working after a click.
        .focusable(false)
        .brutalTip(checked ? "Deselect (⌘-click)" : "Select (⌘-click)")
        .accessibilityLabel(Text("Select"))
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

// MARK: Tags

/// The tags on the captures, as chips that narrow the grid to those carrying every one picked. It shows only once a
/// file has a tag.
private struct GalleryTagRow: View {
    let model: GalleryModel
    @State private var managing = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    managing.toggle()
                } label: {
                    Image(systemName: "tag")
                        .font(.scaled(12, weight: .bold))
                        .foregroundStyle(Brutal.ink)
                        .frame(width: 26, height: 26)
                        .brutalSurface(managing ? Brutal.violet : Brutal.paper.opacity(0.85), radius: Brutal.Radius.chip, shadow: managing ? 0 : 2)
                }
                .buttonStyle(.plain)
                .brutalTip("Rename or remove tags")
                .accessibilityLabel(Text("Manage tags"))
                .popover(isPresented: $managing, arrowEdge: .bottom) {
                    GalleryTagManager(model: model)
                }
                ForEach(model.allTags, id: \.self) { tag in
                    let on = model.tagFilter.contains(tag)
                    Button {
                        model.toggleTagFilter(tag)
                    } label: {
                        HStack(spacing: 5) {
                            TagDot(tag: tag)
                            Text(verbatim: tag)
                                .lineLimit(1)
                        }
                        .font(.scaled(12, weight: .bold))
                        .foregroundStyle(Brutal.ink)
                        .inkOnFill(on ? Brutal.violet : nil)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .brutalSurface(on ? Brutal.violet : Brutal.paper.opacity(0.85), radius: Brutal.Radius.chip, shadow: on ? 0 : 2)
                    }
                    .buttonStyle(.plain)
                    .brutalTip("Show only captures with this tag")
                    .contextMenu {
                        Button("Rename or Remove Tags…") { managing = true }
                        Button("Remove “\(tag)”…") { model.deleteTag(tag) }
                    }
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 6)
        }
    }
}

/// Every tag in use, each with a field to rename it and a button to remove it from all the captures that have it.
/// Renaming one to the name of another merges them.
private struct GalleryTagManager: View {
    let model: GalleryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(Brutal.caption)
                .foregroundStyle(Brutal.faded(0.7))
            if model.allTags.isEmpty {
                Text("No captures have a tag.")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.faded(0.7))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.allTags, id: \.self) { tag in
                            GalleryTagManagerRow(model: model, tag: tag)
                        }
                    }
                }
                .frame(maxHeight: 260)
                Text("Tags are Finder tags, so a change here shows in Finder too.")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.faded(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}

private struct GalleryTagManagerRow: View {
    let model: GalleryModel
    let tag: String
    @State private var name: String

    init(model: GalleryModel, tag: String) {
        self.model = model
        self.tag = tag
        _name = State(initialValue: tag)
    }

    var body: some View {
        HStack(spacing: 6) {
            TagDot(tag: tag)
            TextField("Tag name", text: $name)
                .textFieldStyle(.plain)
                .font(.scaled(13, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .brutalSurface(Brutal.paper.opacity(0.85), radius: Brutal.Radius.button, shadow: 2)
                .onSubmit { model.renameTag(tag, to: name) }
                .accessibilityLabel(Text("Tag name"))
            Button {
                model.deleteTag(tag)
            } label: {
                Image(systemName: "trash")
                    .font(.scaled(12, weight: .bold))
                    .foregroundStyle(Brutal.ink)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .brutalTip("Remove this tag from every capture")
            .accessibilityLabel(Text("Remove tag"))
        }
    }
}

/// A Finder tag's colour, for the tags named like Finder's coloured ones; other tags have none.
private struct TagDot: View {
    let tag: String

    var body: some View {
        if let color = Self.color(of: tag) {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 9, height: 9)
        }
    }

    static func color(of tag: String) -> NSColor? {
        let labels = NSWorkspace.shared.fileLabels, colors = NSWorkspace.shared.fileLabelColors
        // The first label is None.
        guard let index = labels.firstIndex(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }), index > 0, index < colors.count else {
            return nil
        }
        return colors[index]
    }
}

/// Adds a tag to the files it opened on, or takes one off them, from the tags already used.
private struct GalleryTagPopover: View {
    let model: GalleryModel
    let targets: [URL]
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Add a tag", text: $name)
                .textFieldStyle(.plain)
                .font(.scaled(13, weight: .semibold))
                .focused($focused)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .brutalSurface(Brutal.paper.opacity(0.85), radius: Brutal.Radius.button, shadow: 2)
                .onSubmit {
                    model.addTag(name, to: targets)
                    name = ""
                }
            if model.allTags.isEmpty {
                Text("Type a name and press Return. Tags show in Finder too.")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.faded(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.allTags, id: \.self) { tag in
                            row(tag)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .frame(width: 230)
        .onAppear { focused = true }
    }

    private func row(_ tag: String) -> some View {
        let coverage = GalleryTags.coverage(of: tag, on: targets, tagsOf: model.tags)
        return Button {
            model.toggleTag(tag, on: targets)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: coverage == .all ? "checkmark.square.fill" : coverage == .some ? "minus.square" : "square")
                    .font(.scaled(12, weight: .bold))
                TagDot(tag: tag)
                Text(verbatim: tag)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.scaled(13, weight: .semibold))
            .foregroundStyle(Brutal.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(coverage == .all ? .isSelected : [])
    }
}
