import AVFoundation
import ServiceManagement
import ShotCore
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, capture, quickAccess, recording, shortcuts, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .capture: String(localized: "Capture")
        case .quickAccess: String(localized: "Quick Access")
        case .recording: String(localized: "Recording")
        case .shortcuts: String(localized: "Shortcuts")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .capture: "viewfinder"
        case .quickAccess: "rectangle.stack"
        case .recording: "record.circle"
        case .shortcuts: "command"
        case .about: "info.circle"
        }
    }

    /// The tile and glyph behind the section's icon in the sidebar.
    var tint: Theme.SidebarTint {
        switch self {
        case .general: .general
        case .capture: .capture
        case .quickAccess: .quickAccess
        case .recording: .recording
        case .shortcuts: .shortcuts
        case .about: .about
        }
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var section: SettingsSection = .general
    /// What's typed in the sidebar's search. While it holds a word, the content lists matching rows from every section.
    var query = ""
    /// Set while a shortcut recorder is listening, so the arrow keys reach it rather than moving between sections.
    var recordingShortcut = false
    /// Bumped by ⌘F to put the keyboard in the search field.
    var searchFocusRequest = 0
    /// Bumped to take the keyboard out of the search field, so the arrow keys move between sections. The window opens this
    /// way too, since SwiftUI would otherwise give its first text field the keyboard.
    var searchBlurRequest = 0

    var isSearching: Bool { !SettingsSearch.terms(query).isEmpty }

    /// Shows a section, ending any search.
    func open(_ section: SettingsSection) {
        query = ""
        self.section = section
        searchBlurRequest += 1
    }

    /// The section above or below the one shown, for the arrow keys.
    func step(by offset: Int) {
        let sections = SettingsSection.allCases
        let index = sections.firstIndex(of: section) ?? 0
        open(sections[SettingsSearch.step(from: index, by: offset, count: sections.count)])
    }
}

struct SettingsView: View {
    static let sidebarWidths = 180.0...300.0
    static let defaultSidebarWidth = 228.0

    @Setting(PreferenceKey.appSidebarWidth) private var sidebarWidth: Double
    @Bindable private var navigation = SettingsNavigation.shared
    @FocusState private var searchFocused: Bool
    /// The sections with a row that matches the search, which the sidebar keeps at full strength.
    @State private var matchingSections: Set<SettingsSection> = []

    var body: some View {
        HStack(spacing: 0) {
            // The see-through sidebar runs the window's full height, under the traffic lights.
            SettingsSidebar(navigation: navigation, searchFocused: $searchFocused, matching: navigation.isSearching ? matchingSections : nil)
                .padding(.top, GlassWindow.titlebarHeight - 6)
                .frame(width: shownSidebarWidth)
                .frame(maxHeight: .infinity)
                .background { SidebarMaterial() }
                .overlay(alignment: .trailing) {
                    Theme.separator.frame(width: 1)
                }
                .overlay(alignment: .trailing) {
                    PanelResizeHandle(width: $sidebarWidth, range: Self.sidebarWidths, defaultWidth: Self.defaultSidebarWidth)
                        .offset(x: 7)
                }
                .zIndex(1)
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if navigation.isSearching {
                            SettingsSearchResults(navigation: navigation)
                        } else {
                            SettingsSectionContent(section: navigation.section)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                    .padding(.trailing, SystemScroller.shared.overlayRoom)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(navigation.isSearching ? "search" : navigation.section.rawValue)
                .environment(\.settingsQuery, navigation.query)
            }
        }
        .frame(minWidth: SettingsWindowController.minSize.width, maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(MatchingSections.self) { matchingSections = $0 }
        .onChange(of: navigation.searchFocusRequest) {
            searchFocused = true
        }
        .onChange(of: navigation.searchBlurRequest) {
            blurSearch()
        }
        .onAppear {
            // A turn later, once SwiftUI has handed the search field the keyboard.
            DispatchQueue.main.async(execute: blurSearch)
        }
        .background {
            // ⌘F, as in other Mac apps' sidebars with a search field.
            Button("Search") { navigation.searchFocusRequest += 1 }
                .keyboardShortcut("f")
                .hidden()
                .accessibilityHidden(true)
        }
    }

    private func blurSearch() {
        searchFocused = false
        if let window = NSApp.windows.first(where: { $0.firstResponder is NSText && $0.title == String(localized: "Settings") }) {
            window.makeFirstResponder(nil)
        }
    }

    private var shownSidebarWidth: CGFloat {
        min(max(sidebarWidth, Self.sidebarWidths.lowerBound), Self.sidebarWidths.upperBound)
    }

    /// The section's name in the title bar beside the sidebar, over a separator, with Shortcuts' Restore Defaults on the right.
    private var header: some View {
        HStack(spacing: 12) {
            Group {
                if navigation.isSearching {
                    Text("Results for “\(navigation.query.trimmingCharacters(in: .whitespacesAndNewlines))”")
                } else {
                    Text(navigation.section.title)
                }
            }
            .font(Theme.section)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .truncationMode(.middle)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if !navigation.isSearching && navigation.section == .shortcuts {
                RestoreShortcutsButton()
                    .padding(.trailing, -8)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: GlassWindow.titlebarHeight)
        .overlay(alignment: .bottom) {
            Theme.separator.frame(height: 1)
        }
    }
}

/// One section's groups of rows.
private struct SettingsSectionContent: View {
    let section: SettingsSection

    var body: some View {
        switch section {
        case .general: GeneralSettings()
        case .capture: CaptureSettings()
        case .quickAccess: QuickAccessSettings()
        case .recording: RecordingSettings()
        case .shortcuts: ShortcutSettings()
        case .about: AboutSettings()
        }
    }
}

/// The sections with a row matching the search, gathered from each section's results.
private struct MatchingSections: SwiftUI.PreferenceKey {
    static let defaultValue: Set<SettingsSection> = []

    static func reduce(value: inout Set<SettingsSection>, nextValue: () -> Set<SettingsSection>) {
        value.formUnion(nextValue())
    }
}

/// Every row that matches the search, under the name of its section, or a note when nothing does.
private struct SettingsSearchResults: View {
    let navigation: SettingsNavigation
    @State private var matching: Set<SettingsSection>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SettingsSection.allCases) { section in
                SectionResults(section: section) { navigation.open(section) }
            }
            if matching?.isEmpty == true {
                EmptyState(symbol: "magnifyingglass", title: "No settings match", message: "Try another word, or clear the search to see every section.")
                    .frame(maxWidth: .infinity)
                    // Centred in what the scroll view shows, less the content's 18 pt padding above and below.
                    .containerRelativeFrame(.vertical, alignment: .center) { height, _ in max(height - 36, 0) }
            }
        }
        .onPreferenceChange(MatchingSections.self) { matching = $0 }
    }
}

private struct SectionResults: View {
    let section: SettingsSection
    let open: () -> Void

    var body: some View {
        // The section's groups hide when none of their rows match, so no groups left means the section has no results.
        Group(subviews: SettingsSectionContent(section: section)) { groups in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: 0, height: 0)
                    .preference(key: MatchingSections.self, value: groups.isEmpty ? [] : [section])
                if !groups.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        heading
                        ForEach(groups) { $0 }
                    }
                    .padding(.bottom, 28)
                }
            }
        }
        .environment(\.settingsContext, [section.title])
    }

    private var heading: some View {
        HStack(spacing: 10) {
            SettingsSectionTile(section: section, selected: false)
            Text(section.title)
                .font(Theme.section)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button("Show All", action: open)
                .buttonStyle(PanelLinkStyle())
                .accessibilityLabel(Text("Show all of \(section.title)"))
        }
    }
}

/// The bundle's app icon, which already carries its own soft shadow.
struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityLabel("Shot")
    }
}

// MARK: General

private struct GeneralSettings: View {
    @Setting(PreferenceKey.playSound) private var playSound: Bool
    @Setting(PreferenceKey.excludesMenuBar) private var excludesMenuBar: Bool
    @Setting(PreferenceKey.saveFolder) private var saveFolder: String
    @Setting(PreferenceKey.filePrefix) private var filePrefix: String
    @FocusState private var prefixFocused: Bool
    @Setting(PreferenceKey.imageFormat) private var imageFormat: ImageFormat
    @Setting(PreferenceKey.downscaleRetina) private var downscaleRetina: Bool
    @Setting(PreferenceKey.editorSavesOverOriginal) private var savesOverOriginal: Bool
    @Setting(PreferenceKey.textSize) private var textSize: TextSize
    @Setting(PreferenceKey.appearance) private var appearance: AppearanceMode
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        SettingsCard(title: "Behaviour") {
            ToggleRow(title: "Open Shot at login", subtitle: "Start Shot when you log in to your Mac.", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            ToggleRow(title: "Play capture sound", isOn: $playSound)
            ToggleRow(title: "Exclude menu bar", subtitle: "Crop the menu bar and notch off full-screen captures.", isOn: $excludesMenuBar)
            SettingRow(title: "Appearance", subtitle: "Captures look the same either way.") {
                ThemeSegmented(selection: $appearance, options: AppearanceMode.allCases.map { ($0, Self.title(of: $0)) })
            }
            SettingRow(title: "Text size", subtitle: "Shot’s windows, panels and toasts.") {
                ThemePopUp(title: "Text size", entries: TextSize.allCases.map { size in
                    .item(Self.title(of: size), selected: size == textSize) { textSize = size }
                }, value: Self.title(of: textSize))
            }
        }
        SettingsCard(title: "Files") {
            SettingRow(title: String(localized: "Save folder"), subtitle: (saveFolder as NSString).abbreviatingWithTildeInPath) {
                HStack(spacing: 8) {
                    Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: saveFolder)) }
                        .buttonStyle(ThemeButtonStyle())
                    Button("Choose…", action: chooseFolder)
                        .buttonStyle(ThemeButtonStyle())
                }
            }
            SettingRow(title: "File name", subtitle: "\(previewName).\(imageFormat.fileExtension)") {
                TextField("Shot", text: $filePrefix)
                    .font(Theme.body)
                    .focused($prefixFocused)
                    .themeField(focused: prefixFocused)
                    .frame(width: 180)
                    .accessibilityLabel(Text("File name"))
            }
            SettingRow(title: "Image format", subtitle: "Clipboard copies always use PNG.") {
                ThemeSegmented(selection: $imageFormat, options: [(ImageFormat.png, "PNG"), (.jpeg, "JPEG")])
            }
            ToggleRow(title: "Scale Retina captures to 1×", subtitle: "Halves pixel size on 2× displays.", isOn: $downscaleRetina)
            ToggleRow(title: "Save edits over the original", subtitle: "Off keeps the original and saves a copy.", isOn: $savesOverOriginal)
        }
    }

    private var previewName: String {
        FileNaming.baseName(for: Date(), prefix: Preferences.sanitizedPrefix(filePrefix))
    }

    private static func title(of mode: AppearanceMode) -> String {
        switch mode {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    private static func title(of size: TextSize) -> String {
        switch size {
        case .standard: String(localized: "Default")
        case .large: String(localized: "Large")
        case .larger: String(localized: "Larger")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: saveFolder)
        let picked: (NSApplication.ModalResponse) -> Void = { [weak panel] response in
            if response == .OK, let url = panel?.url {
                saveFolder = url.path
            }
        }
        // A sheet on the Settings window, as the gallery's chooser opens, so the window stays put while you pick.
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: picked)
        } else {
            picked(panel.runModal())
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Toast.error("Couldn't change whether Shot opens at login: \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: Capture

private struct CaptureSettings: View {
    @Setting(PreferenceKey.saveAfterCapture) private var save: Bool
    @Setting(PreferenceKey.copyAfterCapture) private var copy: Bool
    @Setting(PreferenceKey.quickAccessAfterCapture) private var quickAccess: Bool
    @Setting(PreferenceKey.openEditorAfterCapture) private var openEditor: Bool
    @Setting(PreferenceKey.showMagnifier) private var magnifier: Bool
    @Setting(PreferenceKey.showCrosshair) private var crosshair: Bool
    @Setting(PreferenceKey.showSizeLabel) private var sizeLabel: Bool
    @Setting(PreferenceKey.captureShowsCursor) private var showsCursor: Bool
    @Setting(PreferenceKey.windowShadow) private var windowShadow: Bool
    @Setting(PreferenceKey.browserPageOnly) private var browserPageOnly: Bool
    @Environment(\.settingsQuery) private var query
    /// Two columns, as on the board, while the content is wide enough for them, and one in a narrow window.
    @State private var twoColumns = true

    var body: some View {
        if SettingsSearch.terms(query).isEmpty {
            columns
        } else {
            // Search results list each section's groups one under another, so they hide one by one when nothing matches.
            afterCapture
            capturedImage
            whileSelecting
        }
    }

    private var columns: some View {
        let spacing: CGFloat = twoColumns ? 16 : 18
        let layout = twoColumns ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        return layout {
            VStack(alignment: .leading, spacing: spacing) {
                afterCapture
                capturedImage
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: spacing) {
                whileSelecting
                SelectionAidsPreview(magnifier: magnifier, crosshair: crosshair, sizeLabel: sizeLabel)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: Bool.self) { $0.size.width >= 600 } action: { twoColumns = $0 }
    }

    private var afterCapture: some View {
        SettingsCard(title: "After a capture", note: "The quick path saves and copies each capture and shows it in Quick Access, without opening a window.") {
            ToggleRow(title: "Save to folder", isOn: $save)
            ToggleRow(title: "Copy to clipboard", isOn: $copy)
            ToggleRow(title: "Show Quick Access", isOn: $quickAccess)
            ToggleRow(title: "Open in editor", subtitle: "Opens the editor instead of Quick Access.", isOn: $openEditor)
        }
    }

    private var capturedImage: some View {
        SettingsCard(title: "Captured image") {
            ToggleRow(title: "Show cursor", subtitle: "Include the pointer in area and full-screen captures.", isOn: $showsCursor)
            ToggleRow(title: "Window shadow", subtitle: "Keep the macOS drop shadow in window captures.", isOn: $windowShadow)
            ToggleRow(
                title: "Capture only the page in browser windows",
                subtitle: "Window captures of a browser leave out its toolbar and tabs. It needs Accessibility access, and B on the capture bar switches it for one capture.",
                isOn: Binding(
                    get: { browserPageOnly },
                    set: { on in
                        browserPageOnly = on
                        if on, !Permissions.hasAccessibility {
                            Permissions.requestAccessibility()
                        }
                    }
                )
            )
        }
    }

    private var whileSelecting: some View {
        SettingsCard(title: "While selecting", note: "Each one also has a key on the capture bar: M, C and I.") {
            ToggleRow(title: "Magnifier", subtitle: "An 8× loupe beside the pointer, for exact edges.", isOn: $magnifier)
            ToggleRow(title: "Crosshair", subtitle: "Guide lines through the pointer across the screen.", isOn: $crosshair)
            ToggleRow(title: "Size label", subtitle: "Width and height in pixels while you drag.", isOn: $sizeLabel)
        }
    }
}

/// A miniature of picking an area over a sample window (Library & Settings › Settings · Capture): the area with its
/// handles, and the magnifier, crosshair and size label that are switched on, drawn as the overlay draws them. Moving the
/// mouse over it drags the area, so you can try the aids before a capture. It hides while searching, and VoiceOver skips
/// it, since the rows above say the same.
private struct SelectionAidsPreview: View {
    let magnifier: Bool
    let crosshair: Bool
    let sizeLabel: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the mouse is over the preview, or nil while it's elsewhere and the pointer rests.
    @State private var hover: CGPoint?
    @State private var cursorPushed = false

    private static let height: CGFloat = 150
    private static let ink = Color(hex: 0x16161A)
    private static let chip = Color(hex: 0x1A1A1E).opacity(0.88)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsGroupHeading("Preview")
            GeometryReader { proxy in
                let layout = SelectionAidsPreviewLayout(size: proxy.size, pointer: hover)
                ZStack(alignment: .topLeading) {
                    PreviewScene()
                    areaDim(layout)
                    handles(layout)
                    if crosshair {
                        guides(layout).transition(.opacity)
                    }
                    if sizeLabel {
                        sizeChips(layout).transition(.opacity)
                    }
                    if hover == nil {
                        pointer(at: layout.pointer)
                    }
                    if magnifier {
                        loupe(layout).transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        if !cursorPushed {
                            SelectionOverlayView.cursor.push()
                            cursorPushed = true
                        }
                        hover = point
                    case .ended:
                        popCursor()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) { hover = nil }
                    }
                }
            }
            .frame(height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular))
            .overlay {
                Color.clear.inkBorder(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular), width: 1, color: Self.ink.opacity(0.08))
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: [magnifier, crosshair, sizeLabel])
            Text("Move the pointer over the preview to drag the area.")
                .font(Theme.caption)
                .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.top, 2)
        }
        .onDisappear(perform: popCursor)
        .accessibilityHidden(true)
        .hiddenWhileSearching()
    }

    private func popCursor() {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }

    /// Outside the area dimmed, and the overlay's 1 pt white line and dark ring around it.
    private func areaDim(_ layout: SelectionAidsPreviewLayout) -> some View {
        Canvas { context, size in
            var dim = Path(CGRect(origin: .zero, size: size))
            dim.addRect(layout.area)
            context.fill(dim, with: .color(Color(red: 12 / 255, green: 12 / 255, blue: 16 / 255).opacity(0.35)), style: FillStyle(eoFill: true))
            context.stroke(Path(layout.area.insetBy(dx: -1.5, dy: -1.5)), with: .color(.black.opacity(0.35)), lineWidth: 1)
            context.stroke(Path(layout.area.insetBy(dx: -0.5, dy: -0.5)), with: .color(.white.opacity(0.95)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    /// The overlay's round white handles with ink edges, at the corners and the middle of each long side, at a smaller size.
    private func handles(_ layout: SelectionAidsPreviewLayout) -> some View {
        Canvas { context, _ in
            let radius: CGFloat = 3.5
            for point in AreaHandles.points(around: layout.area) {
                let handle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                context.fill(handle, with: .color(.white))
                context.stroke(handle, with: .color(Self.ink), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    /// The overlay's guides: a 1 pt white line over a 3 pt shadow, across the whole preview, with a gap at the pointer.
    private func guides(_ layout: SelectionAidsPreviewLayout) -> some View {
        Canvas { context, size in
            let x = layout.pointer.x.rounded(.down) + 0.5
            let y = layout.pointer.y.rounded(.down) + 0.5
            let gap: CGFloat = 8
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: x - gap, y: y))
            path.move(to: CGPoint(x: x + gap, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: y - gap))
            path.move(to: CGPoint(x: x, y: y + gap))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 3)
            context.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    /// The overlay's crosshair cursor while the mouse is elsewhere: white 3 pt lines under ink ones, open in the middle.
    private func pointer(at point: CGPoint) -> some View {
        Canvas { context, _ in
            let x = point.x.rounded(.down) + 0.5
            let y = point.y.rounded(.down) + 0.5
            let arm: CGFloat = 7
            var path = Path()
            for (from, to) in [(-arm, -2.0), (2.0, arm)] {
                path.move(to: CGPoint(x: x + from, y: y))
                path.addLine(to: CGPoint(x: x + to, y: y))
                path.move(to: CGPoint(x: x, y: y + from))
                path.addLine(to: CGPoint(x: x, y: y + to))
            }
            context.stroke(path, with: .color(.white), lineWidth: 3)
            context.stroke(path, with: .color(Self.ink), lineWidth: 1.2)
        }
        .allowsHitTesting(false)
    }

    /// The size in pixels and the ratio, above the area's top left corner, as the overlay's chips.
    private func sizeChips(_ layout: SelectionAidsPreviewLayout) -> some View {
        let size = layout.pixelSize
        return HStack(spacing: 4) {
            Text(verbatim: "\(size.width) × \(size.height)")
                .font(.scaled(10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Self.chip, in: RoundedRectangle(cornerRadius: 6, style: .circular))
            Text("Free ratio")
                .font(.scaled(10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Self.chip, in: RoundedRectangle(cornerRadius: 6, style: .circular))
        }
        .fixedSize()
        .alignmentGuide(.top) { $0[.bottom] - layout.area.minY + 5 }
        .offset(x: layout.area.minX)
        .allowsHitTesting(false)
    }

    /// The overlay's loupe: the sample window magnified six times, 11 points across, ruled per point, with the pointer's row
    /// and column lit yellow, its own point outlined in ink, and its position in pixels underneath, in a white ring and an
    /// ink one with a soft shadow.
    private func loupe(_ layout: SelectionAidsPreviewLayout) -> some View {
        let side = SelectionAidsPreviewLayout.loupeSide
        let zoom = SelectionAidsPreviewLayout.magnification
        let centre = layout.loupeCentre
        let pixel = layout.pixel
        return ZStack {
            PreviewScene()
                .frame(width: layout.size.width, height: layout.size.height)
                .scaleEffect(zoom, anchor: .topLeading)
                .offset(x: side / 2 - centre.x * zoom, y: side / 2 - centre.y * zoom)
                .frame(width: side, height: side, alignment: .topLeading)
            Canvas { context, size in
                let cells = SelectionAidsPreviewLayout.cells
                let cell = size.width / CGFloat(cells)
                let middle = CGFloat(cells / 2) * cell
                var grid = Path()
                for step in 1..<cells {
                    let offset = CGFloat(step) * cell
                    grid.move(to: CGPoint(x: offset, y: 0))
                    grid.addLine(to: CGPoint(x: offset, y: size.height))
                    grid.move(to: CGPoint(x: 0, y: offset))
                    grid.addLine(to: CGPoint(x: size.width, y: offset))
                }
                context.stroke(grid, with: .color(Color(white: 0.5).opacity(0.3)), lineWidth: 0.5)
                let lit = Color(hex: 0xFFD43B).opacity(0.35)
                context.fill(Path(CGRect(x: middle, y: 0, width: cell, height: middle)), with: .color(lit))
                context.fill(Path(CGRect(x: middle, y: middle + cell, width: cell, height: size.height - middle - cell)), with: .color(lit))
                context.fill(Path(CGRect(x: 0, y: middle, width: middle, height: cell)), with: .color(lit))
                context.fill(Path(CGRect(x: middle + cell, y: middle, width: size.width - middle - cell, height: cell)), with: .color(lit))
                let own = CGRect(x: middle, y: middle, width: cell, height: cell)
                context.stroke(Path(own.insetBy(dx: -0.25, dy: -0.25)), with: .color(.white), lineWidth: 0.5)
                context.stroke(Path(own.insetBy(dx: 0.5, dy: 0.5)), with: .color(Self.ink), lineWidth: 1)
            }
            Text(verbatim: "\(pixel.x), \(pixel.y)")
                .font(.scaled(8, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Self.chip, in: RoundedRectangle(cornerRadius: 4, style: .circular))
                .fixedSize()
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 6)
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .padding(2)
        .background(Circle().fill(.white))
        .padding(1)
        .background(Circle().fill(Self.ink).shadow(color: .black.opacity(0.4), radius: 7, y: 6))
        .offset(x: layout.loupe.minX - 3, y: layout.loupe.minY - 3)
        .allowsHitTesting(false)
    }
}

/// The desktop the Capture preview pictures: warm wallpaper and the sample window, so the area, guides and loupe have
/// something to land on. A Quick Access card in the Quick Access preview shows it too, as its capture. It stays light in
/// dark mode, as a screenshot of another app would.
private struct PreviewScene: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: 0x9A8F84), Color(hex: 0x6F675F)], startPoint: .topLeading, endPoint: .bottomTrailing)
            PreviewSampleWindow()
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .offset(x: 18, y: 14)
        }
        .allowsHitTesting(false)
    }
}

/// A light sample window with a sidebar, a heading, lines of text and a yellow tag, 270 × 170 pt.
private struct PreviewSampleWindow: View {
    static let size = CGSize(width: 270, height: 170)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { hex in
                    Circle().fill(Color(hex: UInt32(hex))).frame(width: 6, height: 6)
                }
                Spacer()
            }
            .padding(.horizontal, 7)
            .frame(height: 16)
            .background(Color(hex: 0xEEECE7))
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    bar(30, 0xC9C5BD)
                    bar(38, 0xD8D4CC)
                    bar(26, 0xD8D4CC)
                    bar(34, 0xD8D4CC)
                }
                .padding(8)
                .frame(width: 58, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Color(hex: 0xF5F3EF))
                VStack(alignment: .leading, spacing: 7) {
                    bar(92, 0x3A3A40, height: 6)
                    bar(150, 0xCFCBC4)
                    bar(132, 0xCFCBC4)
                    HStack(spacing: 6) {
                        bar(60, 0xCFCBC4)
                        Capsule().fill(Color(hex: 0xFFD43B)).frame(width: 34, height: 9)
                            .overlay { Capsule().stroke(Color(hex: 0x16161A), lineWidth: 1) }
                    }
                    bar(118, 0xCFCBC4)
                    bar(140, 0xCFCBC4)
                    bar(96, 0xCFCBC4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                Spacer(minLength: 0)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .circular))
    }

    private func bar(_ width: CGFloat, _ hex: UInt32, height: CGFloat = 4) -> some View {
        Capsule().fill(Color(hex: hex)).frame(width: width, height: height)
    }
}

// MARK: Quick Access

private struct QuickAccessSettings: View {
    @Setting(PreferenceKey.quickAccessPosition) private var position: QuickAccessPosition
    @Setting(PreferenceKey.quickAccessDuration) private var duration: Double

    var body: some View {
        SettingsCard(title: "Placement") {
            SettingRow(title: "Screen corner") {
                ThemeSegmented(selection: $position, options: [(QuickAccessPosition.left, "Bottom left"), (.right, "Bottom right")])
            }
            SettingRow(title: "Auto-close", subtitle: "Hovering a card pauses the timer.") {
                ThemeSegmented(selection: $duration, options: [(4.0, "4s"), (8.0, "8s"), (15.0, "15s"), (30.0, "30s"), (0.0, "Never")])
            }
        }
        QuickAccessPreview(position: position, duration: duration)
    }
}

/// A desktop with a Quick Access card in the chosen corner, drawn as the real card is (Library & Settings › Settings ·
/// Quick Access). The card slides in from its edge, the caption under the panel counts down the auto-close time, and the
/// card slides out when it runs out and comes back after a moment. Hovering the card holds it under the real card's
/// hover buttons, and the timer starts again when the pointer leaves, as it does after a capture. It hides while
/// searching, and VoiceOver skips it, since the rows above say the same.
private struct QuickAccessPreview: View {
    let position: QuickAccessPosition
    let duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    @State private var shown = false
    /// Set when the timer closed the card, until the next one arrives.
    @State private var closed = false
    @State private var hovering = false
    @State private var secondsLeft = 0
    /// The corner the card last arrived in, so changing corners brings it in from the new edge.
    @State private var shownIn: QuickAccessPosition?

    private static let ink = Color(hex: 0x16161A)

    private struct TimerKey: Equatable {
        let position: QuickAccessPosition
        let duration: Double
        let hovering: Bool
    }

    var body: some View {
        let height = QuickAccessPreviewLayout.height(forWidth: width)
        let layout = QuickAccessPreviewLayout(size: CGSize(width: width, height: height), position: position)
        VStack(alignment: .leading, spacing: 6) {
            SettingsGroupHeading("Preview")
            ZStack(alignment: .topLeading) {
                QuickAccessDesktop(layout: layout)
                card(layout)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular))
            .overlay {
                Color.clear.inkBorder(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular), width: 1, color: Self.ink.opacity(0.08))
            }
            caption
                .font(Theme.caption)
                .monospacedDigit()
                .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.top, 2)
        }
        .task(id: TimerKey(position: position, duration: duration, hovering: hovering)) { await run() }
        .accessibilityHidden(true)
        .hiddenWhileSearching()
    }

    private var caption: Text {
        if duration <= 0 {
            return Text("Cards stay until you close them.")
        }
        if hovering {
            return Text("The timer waits while the pointer is on the card, and starts again when it leaves.")
        }
        if closed {
            return Text("Closed after \(Int(duration))s. The next capture brings a new card.")
        }
        return Text("Closes in \(secondsLeft)s. Hover over the card to keep it open.")
    }

    /// The real card at the preview's scale: a capture filling a white card with a hairline edge and a window shadow,
    /// sliding in from its edge as the real one does, or fading under Reduce Motion.
    private func card(_ layout: QuickAccessPreviewLayout) -> some View {
        let shape = RoundedRectangle(cornerRadius: layout.cardRadius, style: .circular)
        let away = !shown && !reduceMotion
        return ZStack {
            PreviewScene()
                .frame(width: QuickAccessLayout.cardWidth, height: layout.card.height / max(layout.scale, 0.01))
                .scaleEffect(layout.scale, anchor: .topLeading)
                .frame(width: layout.card.width, height: layout.card.height, alignment: .topLeading)
            if hovering {
                QuickAccessPreviewHover(scale: layout.scale)
                    .transition(.opacity)
            }
        }
        .frame(width: layout.card.width, height: layout.card.height)
        .background(Color.white)
        .clipShape(shape)
        .inkBorder(shape, width: 0.5, color: .black.opacity(0.3))
        .background(shape.fill(.white).shadow(color: .black.opacity(0.3), radius: 18 * layout.scale, y: 8 * layout.scale))
        .contentShape(shape)
        .onHover { inside in
            withAnimation(reduceMotion ? nil : Motion.fade) { hovering = inside && shown }
        }
        .scaleEffect(away ? 0.88 : 1, anchor: position == .left ? .leading : .trailing)
        .offset(x: layout.card.minX + (away ? layout.slide : 0), y: layout.card.minY)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
    }

    private var arrive: Animation { reduceMotion ? Motion.fade : .spring(response: 0.45, dampingFraction: 0.82) }
    private var leave: Animation { reduceMotion ? Motion.fade : .easeIn(duration: 0.3) }

    /// Brings the card in, counts down while the pointer is off it, sends it out when the time runs out and brings it
    /// back, until the corner, the duration or the hover changes and this starts again.
    private func run() async {
        if shownIn != position {
            // The first showing, or a new corner: the card comes in from that corner's edge.
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { shown = false }
            shownIn = position
            guard await pause(.milliseconds(350)) else { return }
            arriveNow()
        } else if !shown {
            arriveNow()
        }
        secondsLeft = QuickAccessPreviewLayout.secondsLeft(duration: duration, elapsed: 0)
        guard duration > 0, !hovering else { return }
        while true {
            let start = ContinuousClock.now
            while secondsLeft > 0 {
                guard await pause(.milliseconds(200)) else { return }
                let elapsed = (ContinuousClock.now - start).components
                secondsLeft = QuickAccessPreviewLayout.secondsLeft(duration: duration, elapsed: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
            }
            closed = true
            withAnimation(leave) { shown = false }
            guard await pause(.seconds(1.6)) else { return }
            arriveNow()
            secondsLeft = QuickAccessPreviewLayout.secondsLeft(duration: duration, elapsed: 0)
        }
    }

    private func arriveNow() {
        closed = false
        withAnimation(arrive) { shown = true }
    }

    private func pause(_ duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return true
        } catch {
            return false
        }
    }
}

/// The real card's hover state at the preview's scale: the scrim, Copy and Save As… in the middle, Close and Annotate at
/// the top and Pin at the bottom right. The Copy button is ink, as on the real card.
private struct QuickAccessPreviewHover: View {
    let scale: CGFloat

    var body: some View {
        ZStack {
            FloatingPanel.scrim
            VStack(spacing: 8 * scale) {
                button("Copy", fill: Color(nsColor: FloatingPanel.accentNS), weight: .semibold, edge: .black, edgeWidth: 1.5)
                button("Save As…", fill: .white, weight: .medium, edge: .black.opacity(0.14), edgeWidth: 1)
            }
            VStack {
                HStack {
                    corner("xmark", iconSize: 10)
                    Spacer()
                    corner("pencil", iconSize: 12)
                }
                Spacer()
                HStack {
                    Spacer()
                    corner("pin", iconSize: 12)
                }
            }
            .padding(8 * scale)
        }
        .allowsHitTesting(false)
    }

    private func button(_ title: LocalizedStringResource, fill: Color, weight: Font.Weight, edge: Color, edgeWidth: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control * scale, style: .circular)
        return Text(title)
            .font(.system(size: 14 * scale, weight: weight))
            .foregroundStyle(Color(hex: 0x16161A))
            .lineLimit(1)
            .frame(width: 128 * scale, height: 32 * scale)
            .background(fill, in: shape)
            .overlay { shape.stroke(edge, lineWidth: edgeWidth * scale) }
    }

    private func corner(_ symbol: String, iconSize: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: iconSize * scale, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26 * scale, height: 26 * scale)
            .background(Color(hex: 0x1A1A1E).opacity(FloatingPanel.Opacity.cornerButton), in: Circle())
    }
}

/// The desktop behind the card, as wide as the pane: the Capture preview's warm wallpaper, a menu bar, and its sample
/// window in the middle at the pictured display's scale. It stays light in dark mode, as a screenshot would.
private struct QuickAccessDesktop: View {
    let layout: QuickAccessPreviewLayout

    var body: some View {
        let s = layout.scale
        let windowScale = layout.window.width / PreviewSampleWindow.size.width
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: 0x9A8F84), Color(hex: 0x6F675F)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 16 * s) {
                Circle().fill(Color(hex: 0x2A2A2E)).frame(width: 12 * s, height: 12 * s)
                bar(34 * s, s, strong: true)
                bar(28 * s, s)
                bar(30 * s, s)
                bar(40 * s, s)
                Spacer(minLength: 0)
                bar(22 * s, s)
                bar(18 * s, s)
                bar(64 * s, s, strong: true)
            }
            .padding(.horizontal, 18 * s)
            .frame(width: layout.menuBar.width, height: layout.menuBar.height)
            .background(Color(hex: 0xF4F1EC).opacity(0.82))
            PreviewSampleWindow()
                .scaleEffect(windowScale, anchor: .topLeading)
                .frame(width: layout.window.width, height: layout.window.height, alignment: .topLeading)
                .shadow(color: .black.opacity(0.25), radius: 8 * windowScale / 2, y: 4 * windowScale / 2)
                .offset(x: layout.window.minX, y: layout.window.minY)
        }
        .allowsHitTesting(false)
    }

    private func bar(_ width: CGFloat, _ scale: CGFloat, strong: Bool = false) -> some View {
        Capsule().fill(Color(hex: strong ? 0x3A3A40 : 0x8D8A86)).frame(width: width, height: 6 * scale)
    }
}

// MARK: Recording

private struct RecordingSettings: View {
    @Setting(PreferenceKey.recordingFPS) private var fps: Int
    @Setting(PreferenceKey.recordShowsCursor) private var showsCursor: Bool
    @Setting(PreferenceKey.recordShowsClicks) private var showsClicks: Bool
    @Setting(PreferenceKey.showRecordingBorder) private var border: Bool
    @Setting(PreferenceKey.copyAfterRecording) private var copy: Bool
    @Setting(PreferenceKey.adjustBeforeRecording) private var adjust: Bool
    // Read only so the GIF summary updates when the video editor changes them.
    @Setting(PreferenceKey.gifFrameRate) private var gifFrameRate: Int
    @Setting(PreferenceKey.gifWidth) private var gifWidth: Int
    @Environment(\.settingsQuery) private var query
    /// Two columns, as on the board, while the content is wide enough for them, and one in a narrow window.
    @State private var twoColumns = true

    /// 120 fps shows only with a display that fast, or when it's already chosen so the selection never disappears.
    private var frameRates: [Int] {
        RecordingFrameRate.selectable(maximumDisplayRate: NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 0, current: fps)
    }

    private var frameRateSubtitle: LocalizedStringResource {
        frameRates.contains(where: RecordingFrameRate.usesHEVC) ? "MP4. 120 records HEVC on ProMotion displays." : "Recordings save as MP4."
    }

    var body: some View {
        if SettingsSearch.terms(query).isEmpty {
            columns
        } else {
            // Search results list each section's groups one under another, so they hide one by one when nothing matches.
            SoundSettings()
            pointer
            afterRecording
            CameraSettings()
            quality
        }
    }

    private var columns: some View {
        let spacing: CGFloat = twoColumns ? 16 : 18
        let layout = twoColumns ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        return layout {
            VStack(alignment: .leading, spacing: spacing) {
                SoundSettings()
                pointer
                afterRecording
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: spacing) {
                CameraPreviewCard()
                CameraSettings()
                quality
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: Bool.self) { $0.size.width >= 600 } action: { twoColumns = $0 }
    }

    private var pointer: some View {
        SettingsCard(title: "Pointer") {
            ToggleRow(title: "Show cursor", isOn: $showsCursor)
            ToggleRow(title: "Show clicks", subtitle: "A ring wherever you click.", isOn: $showsClicks)
            ToggleRow(title: "Region border", subtitle: "Outlines what’s recorded. It never appears in the video.", isOn: $border)
        }
    }

    private var afterRecording: some View {
        SettingsCard(title: "After recording") {
            ToggleRow(title: "Copy to clipboard", isOn: $copy)
            ToggleRow(title: "Adjust before recording", subtitle: "Check the frame and options before every recording. Hold ⌥ as you finish the selection to check once.", isOn: $adjust)
        }
    }

    private var quality: some View {
        SettingsCard(title: "Quality") {
            SettingRow(title: "Frame rate", subtitle: frameRateSubtitle) {
                ThemeSegmented(selection: $fps, options: frameRates.map { ($0, String($0)) })
            }
            SettingRow(title: String(localized: "GIF from Quick Access"), subtitle: String(localized: "Export GIF on the card uses the video editor’s last settings: \(Preferences().videoExportOptions.gifSummary)")) {
                EmptyView()
            }
        }
    }
}

private struct SoundSettings: View {
    @Setting(PreferenceKey.recordMicrophone) private var microphone: Bool
    @Setting(PreferenceKey.microphoneDeviceID) private var deviceID: String
    @Setting(PreferenceKey.recordSystemAudio) private var systemAudio: Bool
    @State private var devices: [AVCaptureDevice] = []
    private let preview = DevicePreview.microphone

    var body: some View {
        SettingsCard(title: "Sound") {
            ToggleRow(title: "Microphone", isOn: $microphone)
            SettingRow(title: "Input") {
                HStack(spacing: 8) {
                    LevelMeter(meter: preview.meter, muted: !preview.isRunning)
                    Button(preview.isRunning ? "Stop" : "Test") {
                        if preview.isRunning {
                            preview.stop()
                        } else {
                            Task { await preview.start(deviceID: deviceID) }
                        }
                    }
                    .buttonStyle(ThemeButtonStyle())
                    .fixedSize()
                    .accessibilityLabel(Text(preview.isRunning ? "Stop the microphone test" : "Test the microphone"))
                    DevicePicker(title: "Microphone", devices: devices, selection: $deviceID, maxWidth: 120)
                }
            }
            ToggleRow(title: "Mac sound", subtitle: "Sound from other apps. Shot’s own sounds are left out.", isOn: $systemAudio)
        }
        .onAppear {
            devices = CaptureDevices.microphones()
        }
        .onChange(of: deviceID) {
            restart(preview, deviceID: deviceID)
        }
        .onDisappear {
            preview.stop()
        }
    }
}

/// The dark card over the Camera group (Library & Settings › Settings · Recording): the camera in a circle with the camera
/// bubble's 3 pt white ring, live and mirrored while Preview runs, beside the camera's name and the Preview button. It
/// hides while searching, since it isn't a row.
private struct CameraPreviewCard: View {
    @Setting(PreferenceKey.cameraDeviceID) private var deviceID: String
    @State private var name = ""
    private let preview = DevicePreview.camera

    private static let fill = Color(hex: 0x2A2A2E)
    private static let diameter: CGFloat = 84

    private var subtitle: LocalizedStringResource {
        preview.isRunning ? "Live and mirrored, as the bubble shows it." : "Check your framing and lighting."
    }

    var body: some View {
        HStack(spacing: 14) {
            bubble
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.scaled(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(subtitle)
                    .font(Theme.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(preview.isRunning ? "Stop" : "Preview") {
                if preview.isRunning {
                    preview.stop()
                } else {
                    Task { await preview.start(deviceID: deviceID) }
                }
            }
            .buttonStyle(ThemeButtonStyle())
            .fixedSize()
            .accessibilityLabel(Text(preview.isRunning ? "Stop the camera preview" : "Preview the camera"))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.fill, in: RoundedRectangle(cornerRadius: 12, style: .circular))
        .overlay {
            Color.clear.inkBorder(RoundedRectangle(cornerRadius: 12, style: .circular), width: 1, color: .white.opacity(0.06))
        }
        .colorScheme(.dark)
        .onAppear(perform: updateName)
        .onChange(of: deviceID, updateName)
        .onDisappear {
            preview.stop()
        }
        .hiddenWhileSearching()
    }

    /// The camera in its ring: live while Preview runs, otherwise a quiet figure in its place.
    private var bubble: some View {
        ZStack {
            // Opaque, since the ring is a white disc behind the circle, as it is on the bubble.
            Circle().fill(Color(hex: 0x3A3A3F))
            Image(systemName: "person.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.45))
            if let session = preview.session {
                CameraPreviewView(session: session)
                    .id(ObjectIdentifier(session))
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .clipShape(Circle())
        .padding(CameraBubbleStyle.ringWidth)
        .background(Circle().fill(.white))
        .accessibilityHidden(true)
    }

    private func updateName() {
        name = CaptureDevices.device(id: deviceID, for: .video)?.localizedName ?? String(localized: "No camera found")
    }
}

private struct CameraSettings: View {
    @Setting(PreferenceKey.recordCamera) private var camera: Bool
    @Setting(PreferenceKey.cameraDeviceID) private var deviceID: String
    @Setting(PreferenceKey.cameraSize) private var size: CameraBubbleSize
    @State private var devices: [AVCaptureDevice] = []
    private let preview = DevicePreview.camera

    var body: some View {
        SettingsCard(title: "Camera") {
            ToggleRow(title: "Camera bubble", isOn: $camera)
            SettingRow(title: "Camera") {
                DevicePicker(title: "Camera", devices: devices, selection: $deviceID)
            }
            SettingRow(title: "Size") {
                ThemeSegmented(selection: $size, options: CameraBubbleSize.allCases.map { ($0, $0.title) })
            }
        }
        .onAppear {
            devices = CaptureDevices.cameras()
        }
        .onChange(of: deviceID) {
            restart(preview, deviceID: deviceID)
        }
    }
}

/// A running preview follows the device picked in Settings.
@MainActor
private func restart(_ preview: DevicePreview, deviceID: String) {
    if preview.isRunning {
        Task { await preview.start(deviceID: deviceID) }
    }
}

private struct DevicePicker: View {
    /// The kind of device, which VoiceOver reads as the pop-up's name.
    let title: LocalizedStringResource
    let devices: [AVCaptureDevice]
    @Binding var selection: String
    var maxWidth: CGFloat = 150

    var body: some View {
        ThemePopUp(title: title, entries: [
            .item("System default", selected: !devices.contains { $0.uniqueID == selection }) { selection = "" },
            .divider,
        ] + devices.map { device in
            .item(device.localizedName, selected: device.uniqueID == selection) { selection = device.uniqueID }
        }, value: selectedName, maxWidth: maxWidth)
    }

    private var selectedName: String {
        devices.first { $0.uniqueID == selection }?.localizedName ?? String(localized: "System default")
    }
}

// MARK: Shortcuts

/// Settings › Shortcuts (Library & Settings › Settings · Shortcuts): the switch that takes ⌘⇧4 and ⌘⇧5 from macOS, each
/// action's global shortcut with its icon, and a reference of the keys that work while picking what to capture. Restore
/// Defaults sits in the title bar (`RestoreShortcutsButton`).
private struct ShortcutSettings: View {
    @Setting(PreferenceKey.replacesSystemScreenshots) private var replacesSystemScreenshots: Bool
    @State private var macOSOwnsKeys = SystemShortcuts.macOSOwnsKeys

    private var useShot: Binding<Bool> {
        Binding(get: { replacesSystemScreenshots }, set: { on in
            SystemShortcuts.useShot(on)
            macOSOwnsKeys = SystemShortcuts.macOSOwnsKeys
        })
    }

    var body: some View {
        SettingsCard {
            ToggleRow(title: "Use Shot for ⌘⇧4 and ⌘⇧5", subtitle: "Off gives macOS its screenshot keys back, and Shot’s default shortcuts become ⌃⇧4 and ⌃⇧5.", isOn: useShot)
            if replacesSystemScreenshots && macOSOwnsKeys {
                SettingRow(title: "macOS still uses these keys", subtitle: "Turn off the Screenshots shortcuts under Keyboard Shortcuts.") {
                    Button("Open") { SystemShortcuts.openKeyboardSettings() }
                        .buttonStyle(ThemeButtonStyle())
                        .fixedSize()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            macOSOwnsKeys = SystemShortcuts.macOSOwnsKeys
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutsRestored)) { _ in
            macOSOwnsKeys = SystemShortcuts.macOSOwnsKeys
        }

        SettingsCard(title: "Global", note: "Click a shortcut to change it. It needs ⌘, ⌥ or ⌃, and can’t be one that macOS or another action already uses.") {
            ForEach(ShotAction.allCases.filter(\.hasShortcut), id: \.self) { action in
                SettingRow(title: action.title, icon: icon(for: action)) {
                    ShortcutRecorderView(action: action)
                }
            }
        }

        PickingKeysCard()
    }

    /// The menu bar menu's icon for the action, with Record in record red as it is there.
    private func icon(for action: ShotAction) -> SettingRow<ShortcutRecorderView>.Icon {
        action.isRecording ? .init(symbol: action.symbol, tint: Theme.record) : .init(symbol: action.symbol)
    }
}

extension Notification.Name {
    /// Posted after Restore Defaults puts the shortcuts back, so the pane checks again whether macOS still owns the keys.
    fileprivate static let shortcutsRestored = Notification.Name("ShotShortcutsRestored")
}

/// Restore Defaults in the title bar while Shortcuts shows: it puts every shortcut back and gives the ⌘⇧4 and ⌘⇧5 keys
/// to Shot again, as the button under the shortcuts did before.
private struct RestoreShortcutsButton: View {
    var body: some View {
        Button("Restore Defaults") {
            Preferences.resetHotkeys()
            SystemShortcuts.useShot(true)
            NotificationCenter.default.post(name: .shortcutsRestored, object: nil)
        }
        .buttonStyle(ThemeButtonStyle())
        .fixedSize()
        .accessibilityLabel(Text("Restore the default shortcuts"))
    }
}

/// "While picking what to capture": the overlay's keys from `PickingKey.all` as keycaps, three to a row (two in a narrow
/// window), on a group panel. It isn't a row, so it hides while searching.
private struct PickingKeysCard: View {
    @State private var columns = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsGroupHeading("While picking what to capture")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .leading), count: columns), alignment: .leading, spacing: 10) {
                ForEach(PickingKey.all, id: \.key) { item in
                    HStack(spacing: 8) {
                        Keycap(item.key)
                        Text(item.label)
                            .font(.scaled(12.5))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .depth(.group, fill: Theme.group, radius: Theme.Radius.group)
            .onGeometryChange(for: Int.self) { $0.size.width >= 480 ? 3 : 2 } action: { columns = $0 }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hiddenWhileSearching()
    }
}

// MARK: About

private struct AboutSettings: View {
    @Environment(\.settingsQuery) private var query
    /// Two columns, as on the board, while the content is wide enough for them, and one in a narrow window.
    @State private var twoColumns = true

    var body: some View {
        if SettingsSearch.terms(query).isEmpty {
            columns
        } else {
            // Search results list each section's groups one under another, so they hide one by one when nothing matches.
            UpdatesCard()
            PermissionsCard()
            DataCard()
            ProjectCard()
        }
    }

    private var columns: some View {
        let spacing: CGFloat = twoColumns ? 16 : 18
        let layout = twoColumns ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        return layout {
            VStack(alignment: .leading, spacing: spacing) {
                AboutHeader()
                UpdatesCard()
                ProjectCard()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: spacing) {
                PermissionsCard()
                DataCard()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: Bool.self) { $0.size.width >= 600 } action: { twoColumns = $0 }
    }
}

/// Shot's icon, name and version over what the last update check found.
private struct AboutHeader: View {
    @Bindable private var updater = Updater.shared

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        HStack(spacing: 16) {
            AppIconView(size: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "Shot")
                    .font(.scaled(20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(verbatim: version)
                    .font(.scaled(12, design: .monospaced))
                    .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                    .textSelection(.enabled)
                    .accessibilityLabel(Text("Version \(version)"))
                UpdateStatusLine(status: updater.status)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .depth(.group, fill: Theme.group, radius: 12)
        .accessibilityElement(children: .combine)
        .hiddenWhileSearching()
    }
}

/// "Up to date" beside a success dot only after a check in this session found nothing, and otherwise what Shot does know.
private struct UpdateStatusLine: View {
    let status: UpdateStatus

    var body: some View {
        HStack(spacing: 6) {
            if status == .upToDate {
                Circle().fill(Theme.success).frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.scaled(12, weight: .semibold))
                .foregroundStyle(status.availableVersion == nil
                    ? ContrastAware(standard: Theme.secondaryText, increased: Theme.ink)
                    : ContrastAware(standard: Theme.accentText, increased: Theme.ink))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var text: String {
        switch status {
        case .off: String(localized: "This build doesn’t update itself")
        case .available(let version): String(localized: "Shot \(version) is available")
        case .upToDate: String(localized: "Up to date")
        case .lastChecked(let date): String(localized: "Last checked \(date.formatted(.relative(presentation: .named)))")
        case .notChecked: String(localized: "Not checked yet")
        }
    }
}

private struct UpdatesCard: View {
    @Bindable private var updater = Updater.shared

    var body: some View {
        SettingsCard(title: "Updates") {
            ToggleRow(title: "Check automatically", subtitle: "Shot looks for a new version once a day. It’s the only time Shot goes online.", isOn: $updater.automaticallyChecks)
            SettingRow(title: "Check now") {
                Button("Check for Updates") { updater.checkForUpdates() }
                    .buttonStyle(ThemeButtonStyle())
                    .fixedSize()
                    .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}

/// The links to the guide, the code, bug reports, the acknowledgements and sponsoring, each a whole row.
private struct ProjectCard: View {
    var body: some View {
        SettingsCard(title: "Project") {
            LinkRow(title: String(localized: "User guide"), words: String(localized: "help manual docs", comment: "Search words for the User guide row in Settings › About, separated by spaces"), symbol: "book") { NSWorkspace.shared.open(Self.guide) }
            LinkRow(title: String(localized: "Source code · GPL-3.0"), words: String(localized: "GitHub licence license open source", comment: "Search words for the Source code row in Settings › About, separated by spaces"), symbol: "chevron.left.forwardslash.chevron.right") { NSWorkspace.shared.open(Self.repository) }
            LinkRow(title: String(localized: "Report a problem"), words: String(localized: "bug issue feedback idea", comment: "Search words for the Report a problem row in Settings › About, separated by spaces"), symbol: "exclamationmark.triangle") {
                NSWorkspace.shared.open(Self.repository.appending(path: "issues/new/choose"))
            }
            LinkRow(title: String(localized: "Acknowledgements"), words: String(localized: "credits Sparkle warranty", comment: "Search words for the Acknowledgements row in Settings › About, separated by spaces"), symbol: "info.circle") {
                if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") {
                    NSWorkspace.shared.open(url)
                }
            }
            LinkRow(title: String(localized: "Support Shot"), words: String(localized: "sponsor donate", comment: "Search words for the Support Shot row in Settings › About, separated by spaces"), symbol: "heart") { NSWorkspace.shared.open(Self.sponsors) }
        }
    }

    private static let repository = URL(string: "https://github.com/LorcanChinnock/shot")!
    private static let guide = URL(string: "https://shot.lorcanchinnock.com/docs/")!
    private static let sponsors = URL(string: "https://github.com/sponsors/LorcanChinnock")!
}

/// A row that opens something outside Settings: its icon and name, with an arrow on the right. It has no description, so
/// `words` carries what a search might use instead, such as "sponsor" for Support Shot.
private struct LinkRow: View {
    let title: String
    let words: String
    let symbol: String
    let action: () -> Void
    @Environment(\.settingsQuery) private var query
    @Environment(\.settingsContext) private var context

    var body: some View {
        // Matched here as well as in the row, so a row that doesn't match leaves no button behind for the group to count.
        if SettingsSearch.matches(query, in: context + [title, words]) {
            Button(action: action) {
                SettingRow(title: title, icon: SettingRow.Icon(symbol: symbol)) {
                    Image(systemName: "arrow.up.right")
                        .font(.scaled(10, weight: .bold))
                        .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .environment(\.settingsContext, context + [words])
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .accessibilityLabel(Text(title))
            .accessibilityAddTraits(.isLink)
        }
    }
}

/// Each permission Shot uses, with Allowed or a button that asks for it. It re-reads them every two seconds while it shows,
/// since macOS doesn't say when one changes in System Settings.
private struct PermissionsCard: View {
    @State private var screenGranted = Permissions.hasScreenCapture
    @State private var screenRequested = Permissions.requestedScreenCapture
    @State private var accessibilityGranted = Permissions.hasAccessibility
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private func refresh() {
        screenGranted = Permissions.hasScreenCapture
        screenRequested = Permissions.requestedScreenCapture
        accessibilityGranted = Permissions.hasAccessibility
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// macOS applies a new Screen Recording grant only after a relaunch, so once Shot has asked, the row says so.
    private var screenSubtitle: String {
        screenGranted || !screenRequested
            ? String(localized: "Needed for every capture.")
            : String(localized: "Turn on Shot in System Settings, then relaunch Shot.")
    }

    var body: some View {
        SettingsCard(title: "Permissions") {
            SettingRow(title: String(localized: "Screen & System Audio Recording"), subtitle: screenSubtitle) {
                if screenGranted {
                    AllowedTag()
                } else {
                    HStack(spacing: 8) {
                        if screenRequested {
                            Button("Relaunch") { Permissions.relaunch() }
                                .buttonStyle(ThemeButtonStyle())
                                .fixedSize()
                        }
                        // Asking a second time would wipe a grant macOS hasn't applied yet, so after the first it opens System Settings.
                        AllowButton(opensSettings: screenRequested) {
                            if screenRequested {
                                Permissions.openSettings()
                            } else {
                                Permissions.requestScreenCapture()
                                screenRequested = true
                            }
                        }
                    }
                }
            }
            SettingRow(title: "Accessibility", subtitle: "Only to capture just the page in a browser.") {
                if accessibilityGranted {
                    AllowedTag()
                } else {
                    // macOS's own prompt has a button straight to System Settings.
                    AllowButton(opensSettings: false) { Permissions.requestAccessibility() }
                }
            }
            MediaPermissionRow(title: "Microphone", subtitle: "Only to record your voice.", mediaType: .audio, status: $microphoneStatus, pane: "Privacy_Microphone")
            MediaPermissionRow(title: "Camera", subtitle: "Only for the camera bubble.", mediaType: .video, status: $cameraStatus, pane: "Privacy_Camera")
        }
        // A menu bar app may not become active when Settings opens or regains focus, so also re-read when the window
        // appears and when it becomes key, and every two seconds for a change made in System Settings.
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                refresh()
            }
        }
    }
}

private struct MediaPermissionRow: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let mediaType: AVMediaType
    @Binding var status: AVAuthorizationStatus
    let pane: String

    var body: some View {
        SettingRow(title: title, subtitle: subtitle) {
            if status == .authorized {
                AllowedTag()
            } else {
                // macOS asks only while the status is not determined; after a denial only System Settings can change it.
                AllowButton(opensSettings: status != .notDetermined) {
                    if status == .notDetermined {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: mediaType)
                            status = AVCaptureDevice.authorizationStatus(for: mediaType)
                        }
                    } else {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                    }
                }
            }
        }
    }
}

/// A permission that's allowed: a check and "Allowed" in success green on a pale green pill.
private struct AllowedTag: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.scaled(9, weight: .heavy))
                .accessibilityHidden(true)
            Text("Allowed")
                .font(.scaled(11.5, weight: .bold))
        }
        .foregroundStyle(contrast == .increased ? Theme.ink : Theme.successText)
        .padding(.horizontal, 9)
        .padding(.vertical, 2)
        .background(Theme.successFill, in: Capsule())
        .fixedSize()
    }
}

/// Asks macOS for a permission, or opens its list in System Settings once macOS won't ask again.
private struct AllowButton: View {
    let opensSettings: Bool
    let action: () -> Void

    var body: some View {
        Button("Allow…", action: action)
            .buttonStyle(ThemeButtonStyle())
            .fixedSize()
            .accessibilityHint(opensSettings ? Text("Opens System Settings") : Text("Asks macOS for access"))
    }
}

/// The save folder, the originals kept for undo after Save, and resetting every setting. Clearing and resetting each take a
/// second click to confirm.
private struct DataCard: View {
    @State private var confirmingReset = false
    @State private var confirmingClear = false
    @State private var keptBytes = ProjectStore.app.keptOriginalsSize()

    private var keptSize: String {
        ByteCountFormatter.string(fromByteCount: keptBytes, countStyle: .file)
    }

    /// The board's shorter line, with the size, or what Shot keeps while there's nothing to clear.
    private var keptSubtitle: LocalizedStringResource {
        keptBytes == 0
            ? "None yet. Shot keeps a screenshot’s original when Save goes over it, so you can undo."
            : "\(keptSize) of screenshots from before Save went over them, for undo."
    }

    var body: some View {
        SettingsCard(title: "Data") {
            SettingRow(title: String(localized: "Save folder"), subtitle: (Preferences().saveFolder.path as NSString).abbreviatingWithTildeInPath) {
                Button("Show in Finder") {
                    let folder = Preferences().saveFolder
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }
                .buttonStyle(ThemeButtonStyle())
                .fixedSize()
            }
            SettingRow(title: "Kept originals", subtitle: keptSubtitle) {
                Button(confirmingClear ? "Click to confirm" : "Clear…") {
                    if confirmingClear {
                        ProjectStore.app.removeKeptOriginals()
                        keptBytes = ProjectStore.app.keptOriginalsSize()
                        confirmingClear = false
                    } else {
                        confirmingClear = true
                    }
                }
                .buttonStyle(ThemeButtonStyle(confirmingClear ? .main : .secondary, destructive: confirmingClear))
                .fixedSize()
                .disabled(keptBytes == 0 && !confirmingClear)
            }
            SettingRow(title: "Reset all settings", subtitle: "Restores every setting and shortcut. Your captures stay.") {
                Button(confirmingReset ? "Click to confirm" : "Reset…") {
                    if confirmingReset {
                        Preferences.resetAll()
                        SystemShortcuts.useShot(Preferences().replacesSystemScreenshots)
                        confirmingReset = false
                        Toast.show("Settings reset")
                    } else {
                        confirmingReset = true
                    }
                }
                .buttonStyle(ThemeButtonStyle(confirmingReset ? .main : .secondary, destructive: true))
                .fixedSize()
            }
        }
    }
}
