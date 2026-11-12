import AppKit
import AVFoundation
import AVKit
import ImageIO
import Observation
import ShotCore
import SwiftUI

/// The board's preview: one capture large over the grid, with Back, its name, where it is in the grid, Edit and Copy in
/// the toolbar, and a details panel beside it. ← and → step through the grid's captures and Space goes back
/// (`GalleryController`).
struct GalleryPreviewView: View {
    let model: GalleryModel
    @State private var loader = GalleryPreviewLoader()

    var body: some View {
        if let item = model.previewItem {
            let query = GalleryQuery(model.query).text
            VStack(spacing: 0) {
                GalleryPreviewToolbar(model: model, item: item)
                HStack(spacing: 0) {
                    GalleryPreviewStage(item: item, loader: loader, placeholder: model.thumbnails.slot(for: item).thumbnail?.image)
                    GalleryPreviewDetails(model: model, item: item, loader: loader, query: query)
                        .sidePanel(width: 250)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Text("Details"))
                }
                // Not into the title bar's safe area, where it would cover the toolbar.
                .background(Theme.window, ignoresSafeAreaEdges: [])
            }
            .task(id: GalleryPreviewLoader.Request(item: item, query: query, revision: model.textRevision)) {
                await loader.load(item, query: query, revision: model.textRevision)
            }
        }
    }
}

// MARK: Loading

/// What the preview shows of the capture: the image at full size, its size in pixels, the text the search index read from
/// it, and where the search's matches are in it. It reads the index `TextIndexer` keeps and never adds to it.
@MainActor
@Observable
final class GalleryPreviewLoader {
    struct Request: Equatable {
        let item: GalleryItem
        let query: String
        let revision: Int
    }

    /// The text panel's state for a screenshot.
    enum Text: Equatable {
        case loading
        /// The index has nothing for this screenshot yet.
        case unread
        /// The index read it and found no text.
        case empty
        case read(String)
    }

    private(set) var url: URL?
    private(set) var image: NSImage?
    private(set) var pixels: CGSize?
    private(set) var text = Text.loading
    /// Where the search matches in the image, in the pixels of `matchSpace`.
    private(set) var matches: [CGRect] = []
    private(set) var matchSpace: CGSize?

    @ObservationIgnored private var index: TextIndex?
    @ObservationIgnored private var indexRevision: Int?
    /// The text read with positions for the search's highlights, kept while the same screenshot is shown.
    @ObservationIgnored private var located: (url: URL, text: CaptureText?)?

    /// The largest an image is decoded to, which still fills a 5K display.
    private static let maxPixels = 5120

    func load(_ item: GalleryItem, query: String, revision: Int) async {
        if url != item.url {
            url = item.url
            image = nil
            pixels = nil
            text = .loading
            matches = []
            matchSpace = nil
        }
        switch item.kind {
        case .image:
            if image == nil {
                let url = item.url
                async let decoded = Thumbnails.make(item, maxPixels: Self.maxPixels)
                async let size = Task.detached(priority: .userInitiated) { Self.imagePixels(url) }.value
                let (thumbnail, found) = await (decoded, size)
                guard !Task.isCancelled else {
                    return
                }
                image = thumbnail?.image
                pixels = found
            }
            await loadText(item, query: query, revision: revision)
        case .gif:
            // NSImage plays a GIF's frames; ImageIO's decode would keep only the first.
            if image == nil {
                image = NSImage(contentsOf: item.url)
                pixels = Self.imagePixels(item.url)
            }
        case .video:
            if pixels == nil {
                pixels = await Self.videoPixels(item.url)
            }
        }
    }

    private func loadText(_ item: GalleryItem, query: String, revision: Int) async {
        if index == nil || indexRevision != revision {
            index = await Task.detached(priority: .userInitiated) { TextIndexer.store.load() }.value
            indexRevision = revision
        }
        guard !Task.isCancelled else {
            return
        }
        let read = index?.text(of: item.textFile)
        text = read.map { $0.isEmpty ? .empty : .read($0) } ?? .unread
        // Highlights need to know where the text is, which the index doesn't keep, so the screenshot shown is read again
        // with Vision, on this Mac, only while there's a search and the index found it in this screenshot's text.
        guard case let .read(string) = text, !TextSearch.ranges(of: query, in: string).isEmpty else {
            matches = []
            return
        }
        if located?.url != item.url {
            let url = item.url
            let found = try? await Task.detached(priority: .userInitiated) { try await TextRecognizer.recognize(fileAt: url) }.value
            guard !Task.isCancelled else {
                return
            }
            located = (url, found ?? nil)
        }
        guard let captured = located?.text else {
            return
        }
        matches = captured.boxes(matching: query)
        matchSpace = CGSize(width: captured.width, height: captured.height)
    }

    nonisolated private static func imagePixels(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private static func videoPixels(_ url: URL) async -> CGSize? {
        guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else {
            return nil
        }
        let turned = size.applying(transform)
        return CGSize(width: abs(turned.width), height: abs(turned.height))
    }
}

// MARK: Toolbar

/// Back, the capture's name and "3 of 248", then Edit and Copy as the one ink button, in the title bar.
private struct GalleryPreviewToolbar: View {
    let model: GalleryModel
    let item: GalleryItem

    var body: some View {
        let position = (model.visible.firstIndex(of: item) ?? 0) + 1
        HStack(spacing: 12) {
            Button {
                model.closePreview()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.scaled(13, weight: .semibold))
            }
            .buttonStyle(ThemeButtonStyle(.toolbar))
            .themeTip("Back to the grid", key: "Space")
            .accessibilityLabel(Text("Back to grid"))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: item.name)
                    .font(.scaled(13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                Text("\(position) of \(model.visible.count)")
                    .font(.scaled(12, tabular: true))
                    .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                    .lineLimit(1)
                    .fixedSize()
            }
            // The title bar behind them moves the window.
            .allowsHitTesting(false)
            Spacer(minLength: 8)
            Button("Edit") { model.edit([item]) }
                .buttonStyle(ThemeButtonStyle())
                // Whether a GIF has a project is read from the store only on a click, so one never greys it out.
                .disabled(!Gallery.canEdit([item]) { _ in true })
                .themeTip("Open in the editor", key: "↩")
            Button("Copy") { model.copy([item]) }
                .buttonStyle(ThemeButtonStyle(.main))
                .themeTip("Copy", key: "⌘C")
        }
        .padding(.leading, GlassWindow.trafficLightsWidth)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity)
        .frame(height: GlassWindow.titlebarHeight)
        .overlay(alignment: .bottom) {
            Theme.separator.frame(height: 1)
        }
    }
}

// MARK: Stage

/// The capture as large as fits, on the well colour, with the search's matches highlighted and the keys along the foot.
private struct GalleryPreviewStage: View {
    let item: GalleryItem
    let loader: GalleryPreviewLoader
    /// The grid's thumbnail, shown until the full image has decoded.
    let placeholder: NSImage?

    private static let padding: CGFloat = 24
    /// Room along the foot for the keys.
    private static let hintRoom: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .circular)
        GeometryReader { geometry in
            let room = CGSize(width: max(geometry.size.width, 1), height: max(geometry.size.height, 1))
            let size = fitted(in: room)
            media
                .frame(width: size.width, height: size.height)
                .overlay { highlights(in: size) }
                .clipShape(shape)
                .overlay { Color.clear.inkBorder(shape, width: 1, color: Theme.hairline) }
                .shadow(color: .black.opacity(0.16), radius: 16, y: 14)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(Self.padding)
        .padding(.bottom, Self.hintRoom)
        .overlay(alignment: .bottom) { hints }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.well, ignoresSafeAreaEdges: [])
    }

    /// The capture's shape scaled to fit `room`, and no larger than its pixels shown at 2x.
    private func fitted(in room: CGSize) -> CGSize {
        let pixels = loader.url == item.url ? loader.pixels : nil
        let aspect = pixels ?? placeholder?.size ?? CGSize(width: 4, height: 3)
        guard aspect.width > 0, aspect.height > 0 else {
            return room
        }
        var scale = min(room.width / aspect.width, room.height / aspect.height)
        if pixels != nil {
            scale = min(scale, 0.5)
        }
        return CGSize(width: (aspect.width * scale).rounded(), height: (aspect.height * scale).rounded())
    }

    @ViewBuilder
    private var media: some View {
        switch item.kind {
        case .video:
            GalleryVideoPlayer(url: item.url)
                .accessibilityLabel(Text("Recording \(item.name)"))
        case .gif:
            if let image = loader.url == item.url ? loader.image : nil {
                AnimatedImage(image: image)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Preview of \(item.name)"))
            } else {
                still(placeholder)
            }
        case .image:
            still(loader.url == item.url ? loader.image ?? placeholder : placeholder)
        }
    }

    @ViewBuilder
    private func still(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .accessibilityLabel(Text("Preview of \(item.name)"))
        } else {
            ZStack {
                Theme.group
                ProgressView().controlSize(.small)
            }
        }
    }

    /// A selection-blue wash over each place the search matches, as the board marks "Discount SPRING20".
    @ViewBuilder
    private func highlights(in size: CGSize) -> some View {
        if loader.url == item.url, let space = loader.matchSpace, space.width > 0, !loader.matches.isEmpty {
            let scale = size.width / space.width
            ZStack(alignment: .topLeading) {
                ForEach(Array(loader.matches.enumerated()), id: \.offset) { _, box in
                    RoundedRectangle(cornerRadius: 2, style: .circular)
                        .fill(Theme.selection.opacity(0.22))
                        .frame(width: box.width * scale + 4, height: box.height * scale + 2)
                        .offset(x: box.minX * scale - 2, y: box.minY * scale - 1)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// "← → next · Space close" on keycaps along the foot.
    private var hints: some View {
        HStack(spacing: 6) {
            Keycap("←")
            Keycap("→")
            Text("next")
            Text(verbatim: "·")
            Keycap("Space")
            Text("close")
        }
        .font(.scaled(11.5))
        .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
        .padding(.bottom, 14)
        .accessibilityHidden(true)
    }
}

/// A GIF, playing.
private struct AnimatedImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = image
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image {
            view.image = image
        }
    }
}

/// A recording with the system's playback controls, in AppKit's `AVPlayerView`: SwiftUI's `VideoPlayer` crashes in
/// AVKit's SwiftUI overlay on macOS 27. It stops when the preview moves on or closes.
private struct GalleryVideoPlayer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard (view.player?.currentItem?.asset as? AVURLAsset)?.url != url else {
            return
        }
        view.player?.pause()
        view.player = AVPlayer(url: url)
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

// MARK: Details

/// When it was taken, its size, folder and versions; its tags; the text search read in it; and two ways to hand the file on.
private struct GalleryPreviewDetails: View {
    let model: GalleryModel
    let item: GalleryItem
    let loader: GalleryPreviewLoader
    let query: String
    @State private var tagging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    facts
                    tagSection
                    if item.kind == .image {
                        textSection
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 6) {
                Button {
                    Clipboard.copy(string: item.url.path)
                    Toast.done("Copied path")
                } label: {
                    actionLabel("Copy path for an AI assistant", symbol: "sparkles")
                }
                .themeTip("Copy where the file is, for an assistant that can open files")
                Button {
                    model.reveal([item])
                } label: {
                    actionLabel("Show in Finder", symbol: "folder")
                }
                .themeTip("Show in Finder", key: "⌘R")
            }
            .buttonStyle(ThemeButtonStyle())
            .padding([.horizontal, .bottom], 16)
            .padding(.top, 8)
        }
        .font(.scaled(12.5))
        .foregroundStyle(Theme.ink)
    }

    private func actionLabel(_ title: LocalizedStringResource, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.scaled(12, weight: .medium))
                .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
                .accessibilityHidden(true)
            // Wraps rather than shrinking or truncating, so a larger text size or a long translation still reads in full.
            Text(title)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Facts

    private var facts: some View {
        VStack(alignment: .leading, spacing: 6) {
            fact("Taken", Gallery.takenLabel(item.date))
            fact("Size", Gallery.sizeLabel(pixels: loader.url == item.url ? loader.pixels : nil, bytes: item.bytes))
            fact("Folder", Gallery.folderLabel(item.folder, rootName: model.rootName))
            if let versions = Gallery.versions(of: item, in: model.items) {
                fact("Versions", versions.label)
            }
            if let count = matchCount {
                fact("Search", count == 1 ? String(localized: "“\(query)” · 1 match") : String(localized: "“\(query)” · \(count) matches"))
            }
        }
    }

    /// How many times the search appears in the screenshot's text, while there's a search and it does.
    private var matchCount: Int? {
        guard loader.url == item.url, case let .read(text) = loader.text else {
            return nil
        }
        let count = TextSearch.ranges(of: query, in: text).count
        return count > 0 ? count : nil
    }

    private func fact(_ name: LocalizedStringResource, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                .fixedSize()
            Spacer(minLength: 0)
            Text(verbatim: value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Tags

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags").panelHeading()
            FlowLayout(spacing: 6) {
                ForEach(model.tags[item.url] ?? [], id: \.self) { tag in
                    HStack(spacing: 5) {
                        TagDot(tag: tag, size: 8)
                        Text(verbatim: tag)
                            .lineLimit(1)
                    }
                    .font(.scaled(11.5))
                    .padding(.leading, 7)
                    .padding(.trailing, 9)
                    .padding(.vertical, 2)
                    .background(Theme.group, in: Capsule())
                    .inkBorder(Capsule(), width: 1, color: Theme.controlEdge)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Tag \(tag)"))
                }
                Button {
                    tagging = true
                } label: {
                    Text("+ Add tag")
                        .font(.scaled(11.5))
                        .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 2)
                        .inkBorder(Capsule(), width: 1, color: Theme.controlEdge)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .themeTip("Add or remove tags, which show in Finder too")
                .accessibilityLabel(Text("Add tag"))
                .popover(isPresented: $tagging, arrowEdge: .bottom) {
                    GalleryTagPopover(model: model, targets: [item.url])
                }
                .onChange(of: tagging) {
                    // The popover's field stays in the window after it closes and keeps the keyboard, so Space and the
                    // arrows would type into it. The search field is hidden under the preview, so no other field can
                    // have the keyboard here.
                    if !tagging, let window = NSApp.keyWindow, window.firstResponder is NSText {
                        window.makeFirstResponder(nil)
                    }
                }
            }
        }
    }

    // MARK: Text

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text in this screenshot").panelHeading()
            switch loader.url == item.url ? loader.text : .loading {
            case .loading:
                ProgressView().controlSize(.small)
            case .unread:
                note("Shot reads the text in your screenshots the first time you search the gallery.")
            case .empty:
                note("Shot found no text in this screenshot.")
            case let .read(text):
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .circular)
                Text(highlighted(text))
                    .lineSpacing(3)
                    .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.group, in: shape)
                    .inkBorder(shape, width: 1, color: Theme.hairline)
            }
        }
    }

    private func note(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.scaled(11.5))
            .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The text's lines joined with dots, as the board shows them, with each match on a selection-blue wash.
    private func highlighted(_ text: String) -> AttributedString {
        let joined = text.split(separator: "\n").joined(separator: " · ")
        var attributed = AttributedString(joined)
        for range in TextSearch.ranges(of: query, in: joined) {
            if let lower = AttributedString.Index(range.lowerBound, within: attributed),
               let upper = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[lower..<upper].backgroundColor = Theme.selection.opacity(0.22)
                attributed[lower..<upper].foregroundColor = Theme.ink
            }
        }
        return attributed
    }
}

/// Lays its views out in rows, starting a new row when the next won't fit, as tag chips wrap.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let width = min(size.width, bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(width: width, height: size.height))
                x += width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let itemWidth = min(size.width, width)
            if !row.indices.isEmpty, row.width + spacing + itemWidth > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + itemWidth
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty {
            rows.append(row)
        }
        return rows
    }
}
