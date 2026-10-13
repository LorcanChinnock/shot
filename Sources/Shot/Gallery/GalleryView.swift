import AppKit
import ShotCore
import SwiftUI

struct GalleryRootView: View {
    let model: GalleryModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            GalleryFooter(model: model)
        }
        .onChange(of: model.searchFocusRequest) {
            searchFocused = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            BrutalSegmented(selection: Bindable(model).filter, options: GalleryFilter.allCases.map { ($0, $0.title) }, color: Brutal.violet)
            Spacer(minLength: 8)
            searchField
            sortMenu
            Image(systemName: "photo")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Brutal.ink.opacity(0.6))
            Slider(value: Bindable(model).tileSize, in: Gallery.tileSizes)
                .frame(width: 80)
                .tint(Brutal.ink)
                .brutalTip("Thumbnail size (⌘+ and ⌘−)")
                .accessibilityLabel(Text("Thumbnail size"))
            Image(systemName: "photo")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Brutal.ink.opacity(0.6))
        }
        .padding(.horizontal, 3)
        .frame(height: 36)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Brutal.ink.opacity(0.6))
            TextField("Search", text: Bindable(model).query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Brutal.ink.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 170, height: 30)
        .brutalSurface(Color.white.opacity(0.85), radius: Brutal.Radius.button, shadow: 2)
        .brutalTip("Search by file name (⌘F)")
    }

    private var sortMenu: some View {
        BrutalDropdown(title: "Sort", entries: GallerySort.allCases.map { sort in
            .item(sort.title, selected: sort == model.sort) { model.sort = sort }
        }) {
            HStack(spacing: 5) {
                Text(model.sort.title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .black))
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Brutal.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .brutalSurface(Color.white.opacity(0.85), radius: Brutal.Radius.button, shadow: 2)
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
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Brutal.ink.opacity(0.55))
                Text("No captures yet")
                    .font(Brutal.title(17))
                    .foregroundStyle(Brutal.ink)
                Text("Screenshots and recordings saved to \((model.folder.path as NSString).abbreviatingWithTildeInPath) show up here.")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.ink.opacity(0.7))
                Button("Open Folder") { NSWorkspace.shared.open(model.folder) }
                    .buttonStyle(BrutalButtonStyle(compact: true))
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Brutal.ink.opacity(0.55))
                Text("Nothing matches")
                    .font(Brutal.title(17))
                    .foregroundStyle(Brutal.ink)
                Text("Try another search, or show All.")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.ink.opacity(0.7))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The grid is its own view, so a selection change re-evaluates it and the tiles that changed, not the header or footer.
private struct GalleryGrid: View {
    private static let spacing: CGFloat = 20

    let model: GalleryModel

    var body: some View {
        GeometryReader { geometry in
            let available = geometry.size.width - Brutal.groupInset * 2 - BrutalScrollBar.width
            let columns = max(1, Int((available + Self.spacing) / (model.tileSize + Self.spacing)))
            let cell = (available - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns)
            ScrollViewReader { proxy in
                ScrollView {
                    // One lazy grid, so scrolling can reach a tile that hasn't been built yet.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing, alignment: .top), count: columns), alignment: .leading, spacing: Self.spacing) {
                        ForEach(model.sections) { section in
                            Section {
                                ForEach(section.items) { item in
                                    GalleryTile(item: item, model: model, slot: model.thumbnails.slot(for: item), width: cell,
                                                selected: model.selection.contains(item.url), selectionActive: !model.selection.isEmpty)
                                        .equatable()
                                        .id(item.url)
                                }
                            } header: {
                                if !section.title.isEmpty {
                                    HStack(spacing: 8) {
                                        Text(section.title)
                                            .font(Brutal.title(15))
                                            .foregroundStyle(Brutal.ink)
                                        BrutalChip(text: "\(section.items.count)")
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.leading, Brutal.groupInset)
                    .padding(.trailing, Brutal.groupInset + BrutalScrollBar.width)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { model.clearSelection() }
                    }
                }
                .brutalScrollBar()
                .background { LeadScroller(model: model, proxy: proxy) }
                .onChange(of: columns, initial: true) {
                    model.columns = columns
                }
            }
        }
        .clipped()
    }
}

private struct GalleryFooter: View {
    let model: GalleryModel

    var body: some View {
        let selected = model.selectedItems
        return HStack(spacing: 10) {
            GalleryStatus(model: model)
                .font(Brutal.mono)
                .foregroundStyle(Brutal.ink.opacity(0.7))
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
                    .disabled(!Gallery.canEdit(selected))
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
    let proxy: ScrollViewProxy

    var body: some View {
        Color.clear.onChange(of: model.lead) {
            if let lead = model.lead, !model.isFullyVisible(lead) {
                proxy.scrollTo(lead)
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
    @State private var hovering = false

    nonisolated static func == (lhs: GalleryTile, rhs: GalleryTile) -> Bool {
        lhs.item == rhs.item && lhs.model === rhs.model && lhs.slot === rhs.slot && lhs.width == rhs.width
            && lhs.selected == rhs.selected && lhs.selectionActive == rhs.selectionActive
    }

    private var thumbnail: Thumbnail? { slot.thumbnail }
    private var height: CGFloat { (width * 0.75).rounded() }

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
                        .font(.system(size: 22, weight: .bold))
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
            .background(Color.white.opacity(0.6))
            .inkBorder(RoundedRectangle(cornerRadius: Brutal.radius, style: .circular), width: selected ? 3 : 2, color: selected ? Brutal.violet : Brutal.ink)
            Text(item.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Brutal.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
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
        .onScrollVisibilityChange(threshold: 0.99) { model.setFullyVisible(item.url, $0) }
        .onDisappear { model.setFullyVisible(item.url, false) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu { GalleryTileMenu(model: model, item: item) }
        .task(id: item) {
            await model.thumbnails.load(item)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var badges: some View {
        VStack {
            Spacer()
            HStack {
                switch item.kind {
                case .video:
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Brutal.ink)
                        .frame(width: 26, height: 26)
                        .brutalCircle(Brutal.yellow, shadow: 2)
                    Spacer()
                    if let duration = thumbnail?.duration {
                        BrutalChip(text: Gallery.duration(duration), color: .white)
                    }
                case .gif:
                    BrutalChip(text: "GIF", color: Brutal.mint)
                    Spacer()
                case .image:
                    EmptyView()
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
        if Gallery.canEdit(targets) {
            Button(targets.count == 1 ? (item.kind == .video ? "Edit Video" : "Annotate") : "Edit") { model.edit(targets) }
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
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Brutal.ink)
                .opacity(checked ? 1 : 0)
                .frame(width: 22, height: 22)
                .brutalSurface(checked ? Brutal.violet : Color.white, radius: Brutal.Radius.chip, shadow: 2)
        }
        .buttonStyle(.plain)
        // Focus stays on the grid, so the keyboard shortcuts keep working after a click.
        .focusable(false)
        .brutalTip(checked ? "Deselect (⌘-click)" : "Select (⌘-click)")
    }
}
