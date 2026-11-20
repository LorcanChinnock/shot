import ShotCore
import SwiftUI

/// The settings pages' see-through sidebar: "‹ Library" back to the captures, then the sections, with About at the foot. The
/// search is in the title bar, where the library has it.
struct SettingsSidebar: View {
    let navigation: SettingsNavigation
    /// While searching, the sections with a matching row. The others fade.
    let matching: Set<SettingsSection>?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            BackToLibraryRow()
                .padding(.bottom, 6)
            Spacer().frame(height: 6)
            ForEach(SettingsSection.allCases.filter { $0 != .about }) { section in
                row(section)
            }
            Spacer(minLength: 12)
            row(.about)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        // With keyboard navigation on, Tab goes down the whole sidebar before the pane. Without a focus section, SwiftUI
        // orders Tab stops across the window row by row, so it zig-zags between section rows and the pane's controls.
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Settings sections"))
    }

    private func row(_ section: SettingsSection) -> some View {
        SettingsSidebarRow(
            section: section,
            selected: !navigation.isSearching && section == navigation.section,
            faded: matching.map { !$0.contains(section) } ?? false
        ) {
            navigation.open(section)
        }
    }
}

/// The search field for settings. Esc clears it and gives the keyboard back to the window, so the arrow keys move between
/// sections.
struct SettingsSearchField: View {
    let navigation: SettingsNavigation
    var focus: FocusState<Bool>.Binding
    let prompt: LocalizedStringResource
    var tip: LocalizedStringResource = "Search every setting by name or description (⌘F)"

    var body: some View {
        ThemeSearchField(prompt: prompt, text: Bindable(navigation).query, focus: focus, tip: tip)
            .onExitCommand {
                navigation.query = ""
                navigation.searchBlurRequest += 1
            }
    }
}

/// A section's icon: the glyph alone in one colour, ink when selected.
struct SettingsSectionTile: View {
    let section: SettingsSection
    let selected: Bool

    var body: some View {
        Image(systemName: section.symbol)
            .font(.scaled(13, weight: .medium))
            .foregroundStyle(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink)))
            .frame(width: 22, height: 22)
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

/// "‹ Library" at the top of the settings sidebar, back to the captures.
private struct BackToLibraryRow: View {
    @State private var hovering = false

    var body: some View {
        Button {
            MainWindowNavigation.shared.openLibrary()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.scaled(12, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Library")
                    .font(.scaled(13))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .modifier(SidebarRowBackground(selected: false, hovering: hovering))
        }
        .buttonStyle(.halo)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text("Back to Library"))
    }
}
