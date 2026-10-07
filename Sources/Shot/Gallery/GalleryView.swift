import AppKit
import ShotCore
import SwiftUI

struct GalleryRootView: View {
    private static let spacing: CGFloat = 20

    let model: GalleryModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
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
        .brutalSurface(Color.white.opacity(0.85), radius: 8, shadow: 2)
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
            .brutalSurface(Color.white.opacity(0.85), radius: 8, shadow: 2)
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
            grid
        }
    }

    private var grid: some View {
        GeometryReader { geometry in
            let available = geometry.size.width - Brutal.groupInset * 2
            let columns = max(1, Int((available + Self.spacing) / (model.tileSize + Self.spacing)))
            let cell = (available - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns)
            ScrollViewReader { proxy in
                ScrollView {
                    // One lazy grid, so scrolling can reach a tile that hasn't been built yet.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing, alignment: .top), count: columns), alignment: .leading, spacing: Self.spacing) {
                        ForEach(model.sections) { section in
                            Section {
                                ForEach(section.items) { item in
                                    GalleryTile(item: item, model: model, width: cell)
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
                    .padding(.horizontal, Brutal.groupInset)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { model.clearSelection() }
                    }
                }
                .onChange(of: model.lead) {
                    if let lead = model.lead {
                        proxy.scrollTo(lead)
                    }
                }
                .onChange(of: columns, initial: true) {
                    model.columns = columns
                }
            }
        }
        .clipped()
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
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        let selected = model.selectedItems
        return HStack(spacing: 10) {
            Text(status)
                .font(Brutal.mono)
                .foregroundStyle(Brutal.ink.opacity(0.7))
                .lineLimit(1)
            if model.allSelected {
                Button("Deselect All") { model.clearSelection() }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                    .brutalTip("Deselect all (⌘⇧A)")
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

    private var status: String {
        let total = model.visible.count
        let noun = total == 1 ? "item" : "items"
        let count = model.selection.count
        return count > 0 ? "\(count) of \(total) selected" : "\(total) \(noun)"
    }
}

private struct GalleryTile: View {
    let item: GalleryItem
    let model: GalleryModel
    let width: CGFloat
    @State private var thumbnail: Thumbnail?
    @State private var hovering = false

    private var height: CGFloat { (width * 0.75).rounded() }
    private var selected: Bool { model.selection.contains(item.url) }

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
                if hovering || !model.selection.isEmpty {
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
        .onTapGesture(count: 2) { model.edit([item]) }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            model.click(item, command: flags.contains(.command), shift: flags.contains(.shift))
        }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu { menu }
        .task(id: item) {
            thumbnail = await Thumbnails.thumbnail(for: item)
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

    @ViewBuilder
    private var menu: some View {
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
                .brutalSurface(checked ? Brutal.violet : Color.white, radius: 6, shadow: 2)
        }
        .buttonStyle(.plain)
        // Focus stays on the grid, so the keyboard shortcuts keep working after a click.
        .focusable(false)
        .brutalTip(checked ? "Deselect (⌘-click)" : "Select (⌘-click)")
    }
}
