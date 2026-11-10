import AppKit
import ShotCore
import SwiftUI
import UniformTypeIdentifiers

struct GalleryRootView: View {
    let model: GalleryModel
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Room after the traffic lights for the sidebar button, which the toolbar keeps clear of while the sidebar is hidden.
    private static let sidebarButtonEnd = GlassWindow.trafficLightsWidth + 34

    var body: some View {
        HStack(spacing: 0) {
            if model.showsSidebar {
                // The see-through sidebar runs the window's full height, under the traffic lights.
                GallerySidebar(model: model)
                    .padding(.top, GlassWindow.titlebarHeight)
                    .frame(width: model.sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background { SidebarMaterial() }
                    .overlay(alignment: .trailing) {
                        Brutal.separator.frame(width: 1)
                    }
                    .overlay(alignment: .trailing) {
                        PanelResizeHandle(width: Bindable(model).sidebarWidth, range: GalleryModel.sidebarWidths, defaultWidth: GalleryModel.defaultSidebarWidth) {
                            setSidebar(shown: false)
                        }
                        .offset(x: 4)
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
                    .zIndex(1)
            }
            VStack(spacing: 0) {
                header
                content
                    .padding(.horizontal, 15)
                    .overlay(alignment: .bottom) {
                        GallerySelectionBar(model: model)
                            .padding(.bottom, 20)
                            .padding(.horizontal, 16)
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            sidebarToggle
                .frame(height: GlassWindow.titlebarHeight)
                .padding(.leading, GlassWindow.trafficLightsWidth)
        }
        .onChange(of: model.searchFocusRequest) {
            searchFocused = true
        }
    }

    private func setSidebar(shown: Bool) {
        withAnimation(Motion.animation(.panelArrive, reduceMotion: reduceMotion)) {
            model.showsSidebar = shown
        }
    }

    // MARK: Header

    /// The toolbar, in the title bar beside the sidebar: what's shown and how many, then search, sort and thumbnail size.
    private var header: some View {
        HStack(spacing: 12) {
            GalleryHeading(model: model)
            Spacer(minLength: 8)
            searchField
            sortMenu
            HStack(spacing: 6) {
                Image(systemName: "square")
                    .font(.scaled(10, weight: .medium))
                BrutalSlider(value: Bindable(model).tileSize, range: Gallery.tileSizes, width: 70)
                    .brutalTip("Thumbnail size (⌘+ and ⌘−)")
                    .accessibilityLabel(Text("Thumbnail size"))
                Image(systemName: "square")
                    .font(.scaled(14, weight: .medium))
            }
            .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
        }
        .padding(.leading, model.showsSidebar ? 22 : Self.sidebarButtonEnd)
        .padding(.trailing, 16)
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: GlassWindow.titlebarHeight)
        .overlay(alignment: .bottom) {
            Brutal.separator.frame(height: 1)
        }
    }

    private var sidebarTip: LocalizedStringResource { model.showsSidebar ? "Hide sidebar" : "Show sidebar" }

    private var sidebarToggle: some View {
        Button {
            setSidebar(shown: !model.showsSidebar)
        } label: {
            Image(systemName: "sidebar.left")
                .font(.scaled(13, weight: .medium))
        }
        .buttonStyle(BrutalButtonStyle(.toolbar))
        .brutalTip(sidebarTip)
        .accessibilityLabel(Text("Sidebar"))
        .accessibilityAddTraits(model.showsSidebar ? .isSelected : [])
    }

    private var searchField: some View {
        BrutalSearchField(prompt: "Search names and text in screenshots", text: Bindable(model).query, focus: $searchFocused)
            .frame(minWidth: 120, idealWidth: 290, maxWidth: 290, minHeight: 28, maxHeight: 28)
            .brutalTip("Search by file name or by text in screenshots (⌘F)")
    }

    private var sortMenu: some View {
        BrutalPopUp(title: "Sort", entries: GallerySort.allCases.map { sort in
            .item(sort.title, selected: sort == model.sort) { model.sort = sort }
        }, value: model.sort.title)
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

    @ViewBuilder
    private var emptyState: some View {
        Group {
            if !model.hasLoaded {
                ProgressView().controlSize(.small)
            } else if model.items.isEmpty {
                EmptyState(
                    symbol: "photo.on.rectangle.angled", title: String(localized: "No captures yet"),
                    message: String(localized: "Screenshots and recordings saved to \((model.folder.path as NSString).abbreviatingWithTildeInPath) show up here.")
                ) {
                    Button("Open Folder") { NSWorkspace.shared.open(model.folder) }
                        .buttonStyle(BrutalButtonStyle())
                }
            } else if let shown = model.shownFolder, !model.items.contains(where: { $0.folder == shown }) {
                EmptyState(symbol: "folder", title: "This folder is empty", message: "Drag captures onto this folder in the sidebar, or use Move to in a capture's menu. Captures in the folders inside it show when you open them.")
            } else {
                EmptyState(symbol: "magnifyingglass", title: "Nothing matches", message: "Try another search, or show All.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The grid is its own view, so a selection change re-evaluates it and the tiles that changed, not the header or footer.
/// It builds only the headers and tiles near the view, at the places `GalleryGridLayout` gives them. A lazy grid
/// estimates the height of rows it hasn't built, and as that estimate changes the scroll bar jumps.
private struct GalleryGrid: View {
    static let spacing: CGFloat = 16
    /// Room under the last row for the selection bar, which floats over the grid's foot.
    static let barClearance: CGFloat = 64
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
            let (columns, cellWidth) = Gallery.grid(available: available, tileSize: model.tileSize, spacing: Self.spacing)
            let cell = CGFloat(cellWidth)
            let layout = GalleryGridLayout(sectionSizes: model.sections.map(\.items.count), titled: model.sections.contains { !$0.title.isEmpty },
                                           columns: columns, rowHeight: GalleryTile.thumbnailHeight(width: cell) + captionHeight,
                                           headerHeight: headerHeight, spacing: Self.spacing)
            ScrollView {
                ZStack(alignment: .topLeading) {
                    ForEach(placed(layout.blocks(in: built), cell: cell)) { place in
                        switch place {
                        case let .header(section, top):
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(section.title)
                                    .font(.scaled(13, weight: .bold))
                                    .foregroundStyle(Brutal.ink)
                                    .accessibilityAddTraits(.isHeader)
                                Text(section.items.count, format: .number)
                                    .font(.scaled(12, tabular: true))
                                    .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                                Spacer()
                            }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                            .offset(y: top)
                        case let .tile(item, x, y):
                            GalleryTile(item: item, model: model, slot: model.thumbnails.slot(for: item), width: cell,
                                        selected: model.selection.contains(item.url), selectionActive: !model.selection.isEmpty,
                                        tagging: model.taggingItem == item.url, tag: model.tags[item.url]?.first,
                                        detail: Gallery.tileDetail(for: item, sort: model.sort))
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
                .padding(.top, Self.margin)
                .padding(.bottom, Self.margin + Self.barClearance)
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

/// The name of the sidebar row picked and how many captures it holds. It's its own view, so only it re-evaluates when they
/// change.
private struct GalleryHeading: View {
    let model: GalleryModel

    var body: some View {
        let count = model.counts.count(of: model.source)
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title)
                .font(.scaled(15, weight: .bold))
                .foregroundStyle(Brutal.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(count) items")
                .font(.scaled(11, tabular: true))
                .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
        }
        // The title bar behind it moves the window.
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var title: String {
        switch model.source {
        case let .library(filter): filter.libraryTitle
        case let .folder(path): path.isEmpty ? model.rootName : Gallery.folderLeaf(of: path)
        case let .tag(name): name
        }
    }
}

/// Floats over the grid's foot while something is selected: how many, what can be done to them, and Copy as the one ink
/// button. It's its own view, so only it re-evaluates when the selection changes, not the grid around it.
private struct GallerySelectionBar: View {
    let model: GalleryModel
    @State private var tagging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let selected = model.selectedItems
        ZStack {
            if !selected.isEmpty {
                bar(selected)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.animation(.panelArrive, reduceMotion: reduceMotion), value: selected.isEmpty)
    }

    private func bar(_ selected: [GalleryItem]) -> some View {
        HStack(spacing: 6) {
            Text("\(selected.count) selected")
                .font(.scaled(13, weight: .semibold, tabular: true))
                .foregroundStyle(Brutal.ink)
                .padding(.trailing, 6)
                .lineLimit(1)
            Button("Edit") { model.edit(selected) }
                .buttonStyle(BrutalButtonStyle(.toolbar))
                // Whether a GIF has a project is read from the store only on a click, so one never greys it out.
                .disabled(!Gallery.canEdit(selected) { _ in true })
                .brutalTip("Open in the editor (Return)")
            BrutalDropdown(title: "Move to", entries: moveEntries(selected)) {
                Text("Move to…")
            }
            .buttonStyle(BrutalButtonStyle(.toolbar))
            Button("Tag") { tagging = true }
                .buttonStyle(BrutalButtonStyle(.toolbar))
                .popover(isPresented: $tagging, arrowEdge: .top) {
                    GalleryTagPopover(model: model, targets: selected.map(\.url))
                }
            Button("Show in Finder") { model.reveal(selected) }
                .buttonStyle(BrutalButtonStyle(.toolbar))
                .brutalTip("Show in Finder (⌘R)")
            Button {
                model.trash(selected)
            } label: {
                Image(systemName: "trash")
                    .font(.scaled(13, weight: .medium))
                    .foregroundStyle(Brutal.destructiveText)
            }
            .buttonStyle(BrutalButtonStyle(.toolbar))
            .brutalTip("Move to the Trash (⌘⌫)")
            .accessibilityLabel(Text("Move to Trash"))
            Button("Copy") { model.copy(selected) }
                .buttonStyle(BrutalButtonStyle(.main))
                .brutalTip("Copy (⌘C)")
        }
        .padding(.vertical, 6)
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .fixedSize()
        .depth(.float, fill: Brutal.group, radius: Brutal.Radius.panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Selection"))
    }

    private func moveEntries(_ selected: [GalleryItem]) -> [BrutalMenuEntry] {
        var entries: [BrutalMenuEntry] = ([""] + model.folders).map { path in
            // A folder inside another reads as its path, such as Clients › Acme.
            let title = path.isEmpty ? model.rootName : path.replacingOccurrences(of: "/", with: " › ")
            return .item(title, symbol: "folder", enabled: !selected.allSatisfy { $0.folder == path }) { model.move(selected, to: path) }
        }
        entries.append(.divider)
        entries.append(.item("New Folder…", symbol: "folder.badge.plus") { model.newFolder(moving: selected) })
        return entries
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
            } else if bottom > view.maxY - GalleryGrid.barClearance {
                // Clear of the selection bar, which floats over the grid's foot while something is selected.
                position.scrollTo(y: bottom - view.height + GalleryGrid.barClearance)
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
    /// The capture's first tag, which shows as a dot before its detail.
    let tag: String?
    /// The file's type and the time, size or date, as `Gallery.tileDetail` gives it.
    let detail: String
    @State private var hovering = false

    nonisolated static func == (lhs: GalleryTile, rhs: GalleryTile) -> Bool {
        lhs.item == rhs.item && lhs.model === rhs.model && lhs.slot === rhs.slot && lhs.width == rhs.width
            && lhs.selected == rhs.selected && lhs.selectionActive == rhs.selectionActive && lhs.tagging == rhs.tagging
            && lhs.tag == rhs.tag && lhs.detail == rhs.detail
    }

    private var thumbnail: Thumbnail? { slot.thumbnail }
    private var height: CGFloat { Self.thumbnailHeight(width: width) }

    static func thumbnailHeight(width: CGFloat) -> CGFloat {
        (width * 0.75).rounded()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Brutal.Radius.group, style: .circular)
        VStack(alignment: .leading, spacing: 7) {
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
                        .font(.scaled(22, weight: .medium))
                        .foregroundStyle(Brutal.tertiaryText)
                }
                badge
                if selected || hovering || selectionActive {
                    SelectionCheckbox(checked: selected) {
                        model.click(item, command: true, shift: false)
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
                }
                if hovering, item.kind.isEditable {
                    CornerButton(symbol: item.kind == .video ? "scissors" : "pencil", help: item.kind == .video ? "Edit video" : "Annotate") {
                        model.edit([item])
                    }
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
                }
            }
            .frame(width: width, height: height)
            .background(Brutal.well)
            .clipShape(shape)
            .overlay {
                if selected {
                    // A 2.5 pt ring in selection blue with a soft halo outside it.
                    shape.inset(by: -1.25).stroke(Brutal.selection, lineWidth: 2.5)
                    shape.inset(by: -3.5).stroke(Brutal.selection.opacity(0.2), lineWidth: 2)
                } else {
                    Color.clear.inkBorder(shape, width: 1, color: Brutal.hairline)
                }
            }
            .shadow(color: .black.opacity(selected ? 0 : 0.06), radius: 1.5, y: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.scaled(12.5, weight: .medium))
                    .foregroundStyle(Brutal.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    if let tag {
                        TagDot(tag: tag, size: 7)
                    }
                    Text(verbatim: detail)
                        .lineLimit(1)
                }
                .font(.scaled(11, tabular: true))
                .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
            }
            .padding(.horizontal, 2)
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

    /// A recording's length or "GIF", in white on a dark tab in the thumbnail's corner.
    @ViewBuilder
    private var badge: some View {
        let text: String? = switch item.kind {
        case .video: thumbnail?.duration.map(Gallery.duration)
        case .gif: "GIF"
        case .image: nil
        }
        if let text {
            Text(verbatim: text)
                .font(.scaled(10.5, weight: .bold, design: .monospaced, tabular: true))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color(hex: 0x16161A).opacity(0.78), in: RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular))
                .padding(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
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
            ZStack {
                if checked {
                    Circle().fill(Brutal.selection)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                } else {
                    Circle().fill(.white.opacity(0.85))
                    Circle().strokeBorder(Color(hex: 0x16161A).opacity(0.25), lineWidth: 1)
                }
            }
            .frame(width: 20, height: 20)
            .overlay {
                Circle().strokeBorder(.white, lineWidth: 2).padding(-2)
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
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

/// Every tag in use, each with a field to rename it and a button to remove it from all the captures that have it.
/// Renaming one to the name of another merges them.
struct GalleryTagManager: View {
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
    @FocusState private var focused: Bool

    init(model: GalleryModel, tag: String) {
        self.model = model
        self.tag = tag
        _name = State(initialValue: tag)
    }

    var body: some View {
        HStack(spacing: 6) {
            TagDot(tag: tag)
            TextField("Tag name", text: $name)
                .font(Brutal.body)
                .focused($focused)
                .brutalField(focused: focused)
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

/// A Finder tag's colour, for the tags named like Finder's coloured ones; other tags are grey.
struct TagDot: View {
    let tag: String
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(Self.color(of: tag).map { Color(nsColor: $0) } ?? Brutal.tertiaryText)
            .frame(width: size, height: size)
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
                .font(Brutal.body)
                .focused($focused)
                .brutalField(focused: focused)
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
