import ShotCore
import SwiftUI

/// The one Shot window's search results: the settings that match, with their controls right there, then the first few
/// captures whose name or text matches, with "Show all in library" (#1460). The library shows them only when a setting
/// matches. The settings pages show them for any search.
struct MainWindowResults: View {
    private let navigation = MainWindowNavigation.shared
    @State private var matchingSections: Set<SettingsSection> = []

    var body: some View {
        let model = GalleryController.shared.model
        let matches = model.visible
        let captures = Array(matches.prefix(MainWindowSearch.shownCaptures(of: matches.count)))
        VStack(alignment: .leading, spacing: 0) {
            if !matchingSections.isEmpty {
                heading(Text("Settings"))
                    .padding(.bottom, 14)
            }
            ForEach(SettingsSection.allCases) { section in
                SectionResults(section: section) { navigation.openSettings(section) }
            }
            if !captures.isEmpty {
                heading(Text("Captures"), count: matches.count) {
                    Button("Show all in library") { navigation.showAllInLibrary() }
                        .buttonStyle(PanelLinkStyle())
                }
                .padding(.bottom, 12)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(captures, id: \.url) { item in
                        SearchResultTile(item: item, model: model)
                    }
                }
            } else if matchingSections.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "Nothing matches", message: "Try another word, or clear the search.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            }
        }
        .environment(\.settingsQuery, navigation.query)
        .onPreferenceChange(MatchingSections.self) { matchingSections = $0 }
    }

    private func heading(_ title: Text, count: Int? = nil, @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            title
                .font(.scaled(13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if let count {
                Text(count, format: .number)
                    .font(.scaled(12, tabular: true))
                    .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// A capture in the search results: its thumbnail, name, and the words around the match in its text. Clicking it previews
/// it in the library, with every match behind it.
private struct SearchResultTile: View {
    let item: GalleryItem
    let model: GalleryModel
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular)
        let detail = model.searchSnippet(for: item) ?? Gallery.tileDetail(for: item, sort: model.sort)
        Button {
            MainWindowNavigation.shared.preview(item)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Theme.badgeFill
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        if let thumbnail = model.thumbnails.slot(for: item).thumbnail {
                            Image(nsImage: thumbnail.image)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFill()
                        }
                    }
                    .clipShape(shape)
                    .overlay {
                        Color.clear.inkBorder(shape, width: 1, color: hovering ? Theme.line : Theme.hairline)
                    }
                Text(verbatim: item.name)
                    .font(.scaled(12))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: detail)
                    .font(.scaled(11))
                    .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.halo(radius: Theme.Radius.group))
        .onHover { hovering = $0 }
        .task(id: item) {
            await model.thumbnails.load(item)
        }
        .accessibilityLabel(Text(item.name))
        .accessibilityValue(Text(verbatim: detail))
        .accessibilityHint(Text("Shows it in the library"))
    }
}
