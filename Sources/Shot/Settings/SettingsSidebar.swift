import ShotCore
import SwiftUI

/// The Settings window's see-through sidebar: a search field, the six sections with their tinted icons, Open Gallery, and
/// Shot's icon with whether it's up to date.
struct SettingsSidebar: View {
    let navigation: SettingsNavigation
    var searchFocused: FocusState<Bool>.Binding
    /// While searching, the sections with a matching row. The others fade.
    let matching: Set<SettingsSection>?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ThemeSearchField(prompt: "Search", text: Bindable(navigation).query, focus: searchFocused)
                .onExitCommand {
                    // Esc clears the search and gives the keyboard back to the window, so the arrow keys move between sections.
                    navigation.query = ""
                    navigation.searchBlurRequest += 1
                }
                .themeTip("Search every setting by name or description (⌘F)")
                .padding(.horizontal, 4)
                .padding(.bottom, 12)
            ForEach(SettingsSection.allCases) { section in
                SettingsSidebarRow(
                    section: section,
                    selected: !navigation.isSearching && section == navigation.section,
                    faded: matching.map { !$0.contains(section) } ?? false
                ) {
                    navigation.open(section)
                }
            }
            Spacer(minLength: 12)
            OpenGalleryRow()
            SettingsSidebarFooter { navigation.open(.about) }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        // With keyboard navigation on, Tab goes down the whole sidebar before the pane. Without a focus section, SwiftUI
        // orders Tab stops across the window row by row, so it zig-zags between section rows and the pane's controls.
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Settings sections"))
    }
}

/// A section's icon on its tinted tile, or on white with an ink glyph when it's the selected row.
struct SettingsSectionTile: View {
    let section: SettingsSection
    let selected: Bool

    var body: some View {
        let tint = selected ? Theme.SidebarTint.selected : section.tint
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .circular)
        Image(systemName: section.symbol)
            .font(.scaled(12, weight: .semibold))
            .foregroundStyle(tint.icon)
            .frame(width: 22, height: 22)
            .background(tint.tile, in: shape)
            .overlay {
                if selected {
                    Color.clear.inkBorder(shape, width: 1, color: Color(hex: 0x16161A).opacity(0.2))
                }
            }
            .accessibilityHidden(true)
    }
}

private struct SettingsSidebarRow: View {
    let section: SettingsSection
    let selected: Bool
    let faded: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SettingsSectionTile(section: section, selected: selected)
                Text(section.title)
                    .font(.scaled(13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .modifier(SidebarRowBackground(selected: selected, hovering: hovering))
        }
        .buttonStyle(.halo)
        .opacity(faded ? (contrast == .increased ? 0.75 : 0.4) : 1)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(section.title))
        .accessibilityValue(faded ? Text("No matches") : Text(verbatim: ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Opens the gallery's own window, with an arrow that says it opens somewhere else.
private struct OpenGalleryRow: View {
    @State private var hovering = false

    private var label: some View {
        Text("Open Gallery")
            .font(.scaled(13))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
    }

    var body: some View {
        Button {
            GalleryController.shared.show()
        } label: {
            HStack(spacing: 10) {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .circular)
                Image(systemName: "square.grid.2x2")
                    .font(.scaled(12, weight: .semibold))
                    .foregroundStyle(Theme.SidebarTint.gallery.icon)
                    .frame(width: 22, height: 22)
                    .background(Theme.SidebarTint.gallery.tile, in: shape)
                    .inkBorder(shape, width: 1, color: Theme.controlEdge)
                // At larger text sizes, or in a long translation, the arrow gives way so the label stays on one line.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        label
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.scaled(10, weight: .semibold))
                            .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                            .accessibilityHidden(true)
                    }
                    label.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .modifier(SidebarRowBackground(selected: false, hovering: hovering))
        }
        .buttonStyle(.halo)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text("Open Gallery"))
    }
}

/// Shot's icon and name over whether it's up to date, under a hairline. It opens About, where updates are.
private struct SettingsSidebarFooter: View {
    let action: () -> Void
    @Bindable private var updater = Updater.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AppIconView(size: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Shot")
                        .font(.scaled(12, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(status)
                        .font(.scaled(11))
                        .foregroundStyle(updater.status.availableVersion == nil
                            ? ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink)
                            : ContrastAware(standard: Theme.accentText, increased: Theme.ink))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.halo)
        .overlay(alignment: .top) {
            Theme.hairline.frame(height: 1)
        }
        .padding(.top, 6)
        .themeTip("Updates and more in About")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "Shot"))
        .accessibilityValue(Text(status))
        .accessibilityHint(Text("Opens About"))
    }

    /// "Up to date" only when a check in this session found nothing; otherwise the version, since Shot can't say.
    private var status: String {
        switch updater.status {
        case .available(let version):
            return String(localized: "Shot \(version) is available")
        case .upToDate:
            return String(localized: "Up to date")
        case .off, .lastChecked, .notChecked:
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            return String(localized: "Version \(version)")
        }
    }
}
