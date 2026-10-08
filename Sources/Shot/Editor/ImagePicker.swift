import AppKit
import ShotCore
import SwiftUI

/// The newest captures in the save folder to place on the canvas with a click, and a way to choose any image file.
struct ImagePicker: View {
    private static let limit = 9
    private static let tile: CGFloat = 96

    /// The screenshot being edited, which isn't offered.
    let excluding: URL
    let pick: ([URL]) -> Void

    @State private var recent: [GalleryItem]?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT CAPTURES")
                .font(.system(size: 11, weight: .black))
                .tracking(1.2)
                .foregroundStyle(Brutal.ink.opacity(0.75))
            if let recent, !recent.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.tile), spacing: 8), count: 3), spacing: 8) {
                    ForEach(recent) { item in
                        Button { pick([item.url]) } label: {
                            CaptureThumbnail(item: item)
                                .frame(width: Self.tile, height: Self.tile * 0.7)
                                .inkBorder(RoundedRectangle(cornerRadius: 6, style: .circular), width: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(item.name))
                        .brutalTip(item.name)
                    }
                }
            } else {
                Text(recent == nil ? "Loading…" : "No screenshots in your save folder yet")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.ink.opacity(0.55))
                    .frame(width: Self.tile * 3 + 16, height: Self.tile * 0.7)
            }
            Button("Choose File…", action: chooseFiles)
                .buttonStyle(BrutalButtonStyle(compact: true))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .padding(.top, 6)
        .task {
            let folder = Preferences().saveFolder, excluding = excluding, limit = Self.limit
            recent = await Task.detached { Gallery.recentImages(Gallery.items(in: folder), excluding: excluding, limit: limit) }.value
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose images to place beside your screenshot"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            pick(panel.urls)
        }
    }
}

private struct CaptureThumbnail: View {
    let item: GalleryItem
    @State private var thumbnail: Thumbnail?

    var body: some View {
        ZStack {
            Color.white.opacity(0.6)
            if let thumbnail {
                Image(nsImage: thumbnail.image).resizable().scaledToFill()
            }
        }
        .clipped()
        .task(id: item) { thumbnail = await Thumbnails.make(item) }
    }
}
