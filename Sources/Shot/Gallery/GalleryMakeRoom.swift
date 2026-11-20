import ShotCore
import SwiftUI

/// Make room, from the foot of the gallery's sidebar: the captures over 25 MB and the extra copies of identical files,
/// each with how much room they take and a button that moves them to the Trash, through the usual dialog.
struct MakeRoomSheet: View {
    let model: GalleryModel
    @Environment(\.textSize) private var textSize

    var body: some View {
        if let request = model.trashRequest {
            TrashConfirmation(model: model, request: request)
        } else {
            groups
        }
    }

    private var groups: some View {
        let large = model.largeCaptures
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make room")
                    .font(.scaled(15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Clear what takes the most space. Anything you move to the Trash can be put back from Finder.")
                    .font(.scaled(12.5))
                    .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
                    .fixedSize(horizontal: false, vertical: true)
            }
            MakeRoomGroup(
                model: model, title: "Duplicates", symbol: "square.on.square",
                detail: String(localized: "Exact copies. Shot keeps the oldest of each."), items: model.duplicateCopies,
                empty: String(localized: "No copies of the same capture.")
            )
            MakeRoomGroup(
                model: model, title: "Large captures", symbol: "externaldrive",
                detail: String(localized: "Over \(Self.size(MakeRoom.largeBytes))"), items: large,
                empty: String(localized: "Nothing over \(Self.size(MakeRoom.largeBytes)).")
            )
            HStack {
                Button("Show all, largest first") { model.showLargestFirst() }
                    .buttonStyle(PanelLinkStyle())
                Spacer()
                Button("Done") { model.showsMakeRoom = false }
                    .buttonStyle(ThemeButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: (440 * CGFloat(textSize.scale)).rounded())
        .background(Theme.group)
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// One kind of capture Make room can clear: its name, how many and how much room, the captures themselves, and Move to
/// Trash. `items` is `nil` while Shot is still looking.
private struct MakeRoomGroup: View {
    let model: GalleryModel
    let title: LocalizedStringResource
    let symbol: String
    let detail: String
    let items: [GalleryItem]?
    let empty: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol)
                    .font(.scaled(12, weight: .semibold))
                    .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.scaled(13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: detail)
                        .font(.scaled(11.5))
                        .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                }
                Spacer(minLength: 8)
                if let items, !items.isEmpty {
                    Text(verbatim: summary(items))
                        .font(.scaled(12, tabular: true))
                        .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
                }
            }
            if let items {
                if items.isEmpty {
                    Text(verbatim: empty)
                        .font(.scaled(12))
                        .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(items, id: \.url) { item in
                                MakeRoomRow(model: model, item: item)
                            }
                        }
                    }
                    .frame(maxHeight: 132)
                    .fixedSize(horizontal: false, vertical: true)
                    Button {
                        model.trashFromMakeRoom(items)
                    } label: {
                        Text("Move \(items.count) to Trash")
                    }
                    .buttonStyle(ThemeButtonStyle(destructive: true))
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for copies…")
                        .font(.scaled(12))
                        .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.window, in: shape)
        .inkBorder(shape, width: 1, color: Theme.hairline)
        .accessibilityElement(children: .contain)
    }

    /// How many and how much room, such as "4 · 1.2 GB".
    private func summary(_ items: [GalleryItem]) -> String {
        String(localized: "\(items.count) · \(MakeRoomSheet.size(MakeRoom.bytes(items)))")
    }
}

/// A capture in Make room: a small thumbnail, its name and its size.
private struct MakeRoomRow: View {
    let model: GalleryModel
    let item: GalleryItem

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tiny, style: .circular)
        HStack(spacing: 8) {
            Theme.badgeFill
                .frame(width: 32, height: 24)
                .overlay {
                    if let thumbnail = model.thumbnails.slot(for: item).thumbnail {
                        Image(nsImage: thumbnail.image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    }
                }
                .clipShape(shape)
                .accessibilityHidden(true)
            Text(verbatim: item.name)
                .font(.scaled(12))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(verbatim: MakeRoomSheet.size(item.bytes))
                .font(.scaled(11.5, tabular: true))
                .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
        }
        .task(id: item) {
            await model.thumbnails.load(item)
        }
        .accessibilityElement(children: .combine)
    }
}
