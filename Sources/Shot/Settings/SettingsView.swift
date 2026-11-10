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
    var tint: Brutal.SidebarTint {
        switch self {
        case .general: .general
        case .capture: .capture
        case .quickAccess: .quickAccess
        case .recording: .recording
        case .shortcuts: .shortcuts
        case .about: .about
        }
    }

    /// The old fill colour, which the panes still use until #1112–#1117 rebuild them.
    var color: Color {
        switch self {
        case .general: Brutal.yellow
        case .capture: Brutal.pink
        case .quickAccess: Brutal.sky
        case .recording: Brutal.red
        case .shortcuts: Brutal.orange
        case .about: Brutal.lime
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
                    Brutal.separator.frame(width: 1)
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

    /// The section's name in the title bar beside the sidebar, over a separator.
    private var header: some View {
        Group {
            if navigation.isSearching {
                Text("Results for “\(navigation.query.trimmingCharacters(in: .whitespacesAndNewlines))”")
            } else {
                Text(navigation.section.title)
            }
        }
        .font(Brutal.section)
        .foregroundStyle(Brutal.ink)
        .lineLimit(1)
        .truncationMode(.middle)
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: GlassWindow.titlebarHeight)
        .overlay(alignment: .bottom) {
            Brutal.separator.frame(height: 1)
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
                .font(Brutal.section)
                .foregroundStyle(Brutal.ink)
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
                BrutalSegmented(selection: $appearance, options: AppearanceMode.allCases.map { ($0, Self.title(of: $0)) })
            }
            SettingRow(title: "Text size", subtitle: "Shot’s windows, panels and toasts.") {
                BrutalPopUp(title: "Text size", entries: TextSize.allCases.map { size in
                    .item(Self.title(of: size), selected: size == textSize) { textSize = size }
                }, value: Self.title(of: textSize))
            }
        }
        SettingsCard(title: "Files") {
            SettingRow(title: String(localized: "Save folder"), subtitle: (saveFolder as NSString).abbreviatingWithTildeInPath) {
                HStack(spacing: 8) {
                    Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: saveFolder)) }
                        .buttonStyle(BrutalButtonStyle())
                    Button("Choose…", action: chooseFolder)
                        .buttonStyle(BrutalButtonStyle())
                }
            }
            SettingRow(title: "File name", subtitle: "\(previewName).\(imageFormat.fileExtension)") {
                TextField("Shot", text: $filePrefix)
                    .font(Brutal.body)
                    .focused($prefixFocused)
                    .brutalField(focused: prefixFocused)
                    .frame(width: 180)
                    .accessibilityLabel(Text("File name"))
            }
            SettingRow(title: "Image format", subtitle: "Clipboard copies always use PNG.") {
                BrutalSegmented(selection: $imageFormat, options: [(ImageFormat.png, "PNG"), (.jpeg, "JPEG")])
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
            .clipShape(RoundedRectangle(cornerRadius: Brutal.Radius.group, style: .circular))
            .overlay {
                Color.clear.inkBorder(RoundedRectangle(cornerRadius: Brutal.Radius.group, style: .circular), width: 1, color: Self.ink.opacity(0.08))
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: [magnifier, crosshair, sizeLabel])
            Text("Move the pointer over the preview to drag the area.")
                .font(Brutal.caption)
                .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
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

/// The desktop the preview pictures: warm wallpaper and a light sample window with a sidebar, a heading, lines of text and
/// a yellow tag, so the area, guides and loupe have something to land on. It stays light in dark mode, as a screenshot of
/// another app would.
private struct PreviewScene: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: 0x9A8F84), Color(hex: 0x6F675F)], startPoint: .topLeading, endPoint: .bottomTrailing)
            window
                .offset(x: 18, y: 14)
        }
        .allowsHitTesting(false)
    }

    private var window: some View {
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
        .frame(width: 270, height: 170, alignment: .topLeading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .circular))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    private func bar(_ width: CGFloat, _ hex: UInt32, height: CGFloat = 4) -> some View {
        Capsule().fill(Color(hex: hex)).frame(width: width, height: height)
    }
}

// MARK: Quick Access

private struct QuickAccessSettings: View {
    @Setting(PreferenceKey.quickAccessPosition) private var position: QuickAccessPosition
    @Setting(PreferenceKey.quickAccessDuration) private var duration: Double
    private let color = SettingsSection.quickAccess.color

    var body: some View {
        SettingsCard(title: "Placement") {
            SettingRow(title: "Screen corner") {
                BrutalSegmented(selection: $position, options: [(QuickAccessPosition.left, "Bottom left"), (.right, "Bottom right")])
            }
            SettingRow(title: "Auto-close", subtitle: "Hovering a card pauses the timer.") {
                BrutalSegmented(selection: $duration, options: [(4.0, "4s"), (8.0, "8s"), (15.0, "15s"), (30.0, "30s"), (0.0, "Never")])
            }
        }
        ScreenPreview(position: position, color: color)
            .hiddenWhileSearching()
    }
}

/// A miniature screen showing where cards appear.
private struct ScreenPreview: View {
    let position: QuickAccessPosition
    let color: Color

    var body: some View {
        ZStack(alignment: position == .left ? .bottomLeading : .bottomTrailing) {
            LinearGradient(colors: [Brutal.violet.opacity(0.55), Brutal.sky.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                Rectangle().fill(Brutal.paper.opacity(0.7)).frame(height: 14)
                    .overlay(alignment: .bottom) { Rectangle().fill(Brutal.line).frame(height: 2) }
                HStack {
                    BrutalBadge(text: "PREVIEW", style: .strong)
                    Spacer()
                }
                .padding(12)
                Spacer()
            }
            VStack(spacing: 6) {
                ForEach(0..<2) { index in
                    RoundedRectangle(cornerRadius: 5, style: .circular)
                        .fill(index == 1 ? color : Brutal.paper)
                        .frame(width: 72, height: 42)
                        .inkBorder(RoundedRectangle(cornerRadius: 5, style: .circular), width: 2)
                }
            }
            .padding(12)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: Brutal.radius, style: .circular).inset(by: Brutal.underInk(Brutal.border)))
        .brutalSurface(Color.clear)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: position)
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
    private let color = SettingsSection.recording.color

    /// 120 fps shows only with a display that fast, or when it's already chosen so the selection never disappears.
    private var frameRates: [Int] {
        RecordingFrameRate.selectable(maximumDisplayRate: NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 0, current: fps)
    }

    private var frameRateSubtitle: LocalizedStringResource {
        RecordingFrameRate.usesHEVC(fps: fps) ? "HEVC MP4, on displays that refresh this fast." : "H.264 MP4."
    }

    var body: some View {
        SettingsCard(title: "Starting") {
            ToggleRow(title: "Adjust before recording", subtitle: "Shows the frame handles and options first. Hold ⌥ as you finish the selection to show them once.", isOn: $adjust)
        }
        SettingsCard(title: "Video") {
            SettingRow(title: "Frame rate", subtitle: frameRateSubtitle) {
                BrutalSegmented(selection: $fps, options: frameRates.map { ($0, "\($0) fps") })
            }
            ToggleRow(title: "Show cursor", isOn: $showsCursor)
            ToggleRow(title: "Show clicks", subtitle: "Draws a circle where you click.", isOn: $showsClicks)
            ToggleRow(title: "Region border", subtitle: "A red border around the recorded area. It never appears in the video.", isOn: $border)
            ToggleRow(title: "Copy to clipboard", subtitle: "Copies the finished recording, ready to paste as a file.", isOn: $copy)
        }
        AudioSettings()
        CameraSettings()
        SettingsCard(title: "GIF export") {
            SettingRow(title: "From the Quick Access card", subtitle: "Uses the video editor's last GIF settings: \(Preferences().videoExportOptions.gifSummary)") {
                BrutalBadge(text: "GIF")
            }
        }
    }
}

private struct AudioSettings: View {
    @Setting(PreferenceKey.recordMicrophone) private var microphone: Bool
    @Setting(PreferenceKey.microphoneDeviceID) private var deviceID: String
    @Setting(PreferenceKey.recordSystemAudio) private var systemAudio: Bool
    @State private var devices: [AVCaptureDevice] = []
    private let preview = DevicePreview.microphone

    private var testSubtitle: LocalizedStringResource {
        preview.isRunning ? "Speak to see the level." : "Shows the input level of the microphone above."
    }

    var body: some View {
        SettingsCard(title: "Audio") {
            ToggleRow(title: "Microphone", subtitle: "macOS asks for permission on first use. Mute it from the recording controls.", isOn: $microphone)
            SettingRow(title: "Microphone input") {
                DevicePicker(devices: devices, selection: $deviceID)
            }
            SettingRow(title: "Test microphone", subtitle: testSubtitle) {
                HStack(spacing: 10) {
                    LevelMeter(meter: preview.meter, muted: !preview.isRunning)
                    Button(preview.isRunning ? "Stop" : "Test") {
                        if preview.isRunning {
                            preview.stop()
                        } else {
                            Task { await preview.start(deviceID: deviceID) }
                        }
                    }
                    .buttonStyle(BrutalButtonStyle())
                }
            }
            ToggleRow(title: "System audio", subtitle: "Sound from other apps. Shot's own sounds are excluded.", isOn: $systemAudio)
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

private struct CameraSettings: View {
    @Setting(PreferenceKey.recordCamera) private var camera: Bool
    @Setting(PreferenceKey.cameraDeviceID) private var deviceID: String
    @Setting(PreferenceKey.cameraSize) private var size: CameraBubbleSize
    @State private var devices: [AVCaptureDevice] = []
    private let preview = DevicePreview.camera

    var body: some View {
        SettingsCard(title: "Camera") {
            ToggleRow(title: "Camera bubble", subtitle: "Round webcam overlay recorded with your screen. Drag to move, double-click to resize.", isOn: $camera)
            SettingRow(title: "Camera") {
                DevicePicker(devices: devices, selection: $deviceID)
            }
            SettingRow(title: "Preview", subtitle: "Check your framing and lighting.") {
                HStack(spacing: 12) {
                    if let session = preview.session {
                        CameraPreviewView(session: session)
                            .id(ObjectIdentifier(session))
                            .frame(width: 120, height: 120)
                            .clipShape(Circle().inset(by: Brutal.underInk(Brutal.border)))
                            .brutalCircle(Color.black, shadow: 3)
                    }
                    Button(preview.isRunning ? "Stop" : "Preview") {
                        if preview.isRunning {
                            preview.stop()
                        } else {
                            Task { await preview.start(deviceID: deviceID) }
                        }
                    }
                    .buttonStyle(BrutalButtonStyle())
                }
            }
            SettingRow(title: "Bubble size") {
                BrutalSegmented(selection: $size, options: CameraBubbleSize.allCases.map { ($0, $0.title) })
            }
        }
        .onAppear {
            devices = CaptureDevices.cameras()
        }
        .onChange(of: deviceID) {
            restart(preview, deviceID: deviceID)
        }
        .onDisappear {
            preview.stop()
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
    let devices: [AVCaptureDevice]
    @Binding var selection: String

    var body: some View {
        BrutalPopUp(title: "Device", entries: [
            .item("System default", selected: !devices.contains { $0.uniqueID == selection }) { selection = "" },
            .divider,
        ] + devices.map { device in
            .item(device.localizedName, selected: device.uniqueID == selection) { selection = device.uniqueID }
        }, value: selectedName, maxWidth: 190)
    }

    private var selectedName: String {
        devices.first { $0.uniqueID == selection }?.localizedName ?? String(localized: "System default")
    }
}

// MARK: Shortcuts

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
        SettingsCard(title: "macOS screenshot keys") {
            ToggleRow(title: "Use Shot for ⌘⇧4 and ⌘⇧5", subtitle: "Turns off the matching macOS shortcuts, so these keys and a keyboard's screenshot key open Shot. macOS gets them back while Shot isn't running, or when you turn this off.", isOn: useShot)
            if replacesSystemScreenshots && macOSOwnsKeys {
                SettingRow(title: "macOS still uses these keys", subtitle: "Turn off the Screenshots shortcuts under Keyboard Shortcuts.") {
                    Button("Open") { SystemShortcuts.openKeyboardSettings() }
                        .buttonStyle(BrutalButtonStyle())
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            macOSOwnsKeys = SystemShortcuts.macOSOwnsKeys
        }

        SettingsCard(title: "Global hotkeys") {
            let actions = ShotAction.allCases.filter(\.hasShortcut)
            ForEach(actions, id: \.self) { action in
                SettingRow(title: action.title) {
                    ShortcutRecorderView(action: action)
                }
            }
        }
        HStack(alignment: .top, spacing: 14) {
            Text("Click a shortcut, then press the new keys. Esc cancels, Delete clears.")
                .font(Brutal.caption)
                .foregroundStyle(Brutal.faded(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Restore Defaults") {
                Preferences.resetHotkeys()
                SystemShortcuts.useShot(true)
                macOSOwnsKeys = SystemShortcuts.macOSOwnsKeys
            }
                .buttonStyle(BrutalButtonStyle())
        }
        .padding(.horizontal, 4)
        .hiddenWhileSearching()
    }
}

// MARK: About

private struct AboutSettings: View {
    @State private var screenGranted = Permissions.hasScreenCapture
    @State private var screenRequested = Permissions.requestedScreenCapture
    @State private var accessibilityGranted = Permissions.hasAccessibility
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var confirmingReset = false
    @State private var confirmingClear = false
    @State private var keptSize = AboutSettings.sizeText(ProjectStore.app.keptOriginalsSize())
    @Bindable private var updater = Updater.shared
    private let color = SettingsSection.about.color

    private static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func refreshPermissions() {
        screenGranted = Permissions.hasScreenCapture
        screenRequested = Permissions.requestedScreenCapture
        accessibilityGranted = Permissions.hasAccessibility
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        HStack(spacing: 16) {
            AppIconView(size: 76)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Shot").font(Brutal.title(26)).foregroundStyle(Brutal.ink)
                    BrutalBadge(text: "BETA")
                }
                Text("Screenshots and screen recordings for macOS.")
                    .font(.scaled(12.5, weight: .medium)).foregroundStyle(Brutal.faded(0.65))
            }
            Spacer()
            BrutalBadge(text: "v\(version)")
        }
        .padding(16)
        .glassCard()
        .hiddenWhileSearching()

        SettingsCard(title: "Updates") {
            ToggleRow(title: "Check for updates automatically", subtitle: "Shot asks GitHub once a day whether a new version is out, and installs it when you agree. Nothing else is sent.", isOn: $updater.automaticallyChecks)
            SettingRow(title: "Check now", subtitle: "Looks for a new version once, even when automatic checks are off.") {
                Button("Check") { updater.checkForUpdates() }
                    .buttonStyle(BrutalButtonStyle())
                    .disabled(!updater.canCheckForUpdates)
            }
        }

        SettingsCard(title: "Permissions") {
            SettingRow(title: "Screen & System Audio Recording", subtitle: "Required for every capture.") {
                HStack(spacing: 10) {
                    BrutalBadge(text: screenGranted ? "GRANTED" : "MISSING", dot: screenGranted ? Brutal.success : nil)
                    if !screenGranted, !screenRequested {
                        Button("Grant") {
                            Permissions.requestScreenCapture()
                            screenRequested = true
                        }
                        .buttonStyle(BrutalButtonStyle())
                    } else {
                        Button("Open") { Permissions.openSettings() }
                            .buttonStyle(BrutalButtonStyle())
                    }
                }
            }
            SettingRow(title: "Accessibility", subtitle: "Only needed to capture just the page in browser windows.") {
                HStack(spacing: 10) {
                    BrutalBadge(text: accessibilityGranted ? "GRANTED" : "MISSING", dot: accessibilityGranted ? Brutal.success : nil)
                    if accessibilityGranted {
                        Button("Open") { Permissions.openAccessibilitySettings() }
                            .buttonStyle(BrutalButtonStyle())
                    } else {
                        Button("Grant") { Permissions.requestAccessibility() }
                            .buttonStyle(BrutalButtonStyle())
                    }
                }
            }
            PermissionRow(title: "Microphone", subtitle: "Only needed to record your voice.", mediaType: .audio, status: $microphoneStatus, pane: "Privacy_Microphone")
            PermissionRow(title: "Camera", subtitle: "Only needed for the camera bubble.", mediaType: .video, status: $cameraStatus, pane: "Privacy_Camera")
        }
        // A menu bar app may not become active when Settings opens or regains focus, so also re-read when the window
        // appears and when it becomes key.
        .onAppear(perform: refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refreshPermissions() }

        SettingsCard(title: "Data") {
            SettingRow(title: String(localized: "Save folder"), subtitle: (Preferences().saveFolder.path as NSString).abbreviatingWithTildeInPath) {
                Button("Open") {
                    let folder = Preferences().saveFolder
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }
                .buttonStyle(BrutalButtonStyle())
            }
            SettingRow(title: "Kept originals", subtitle: "\(keptSize) of screenshots as they were before Save went over them. They let you undo those edits, and stay on this Mac.") {
                Button(confirmingClear ? "Click to confirm" : "Delete") {
                    if confirmingClear {
                        ProjectStore.app.removeKeptOriginals()
                        keptSize = Self.sizeText(ProjectStore.app.keptOriginalsSize())
                        confirmingClear = false
                    } else {
                        confirmingClear = true
                    }
                }
                .buttonStyle(BrutalButtonStyle(confirmingClear ? .main : .secondary, destructive: confirmingClear))
            }
            SettingRow(title: "Reset all settings", subtitle: "Restores every setting and shortcut. Your captures stay.") {
                Button(confirmingReset ? "Click to confirm" : "Reset") {
                    if confirmingReset {
                        Preferences.resetAll()
                        SystemShortcuts.useShot(Preferences().replacesSystemScreenshots)
                        confirmingReset = false
                        Toast.show("Settings reset")
                    } else {
                        confirmingReset = true
                    }
                }
                .buttonStyle(BrutalButtonStyle(confirmingReset ? .main : .secondary, destructive: true))
            }
        }

        SettingsCard(title: "Project") {
            SettingRow(title: "Source code", subtitle: "Free and open source under the GPL-3.0 license.") {
                Button("GitHub") { NSWorkspace.shared.open(Self.repository) }
                    .buttonStyle(BrutalButtonStyle())
            }
            SettingRow(title: "User Guide", subtitle: "How to use every part of Shot.") {
                Button("Open") { NSWorkspace.shared.open(Self.guide) }
                    .buttonStyle(BrutalButtonStyle())
            }
            SettingRow(title: "Acknowledgements", subtitle: "Shot comes with no warranty. It updates itself with Sparkle, under the MIT license.") {
                Button("View") {
                    if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(BrutalButtonStyle())
            }
            SettingRow(title: "Support Shot", subtitle: "Shot is free, with no ads or account. Sponsoring keeps it that way.") {
                Button("Sponsor") { NSWorkspace.shared.open(Self.sponsors) }
                    .buttonStyle(BrutalButtonStyle())
            }
            SettingRow(title: "Report a problem", subtitle: "Bug reports and ideas are welcome.") {
                Button("New Issue") { NSWorkspace.shared.open(Self.repository.appending(path: "issues/new/choose")) }
                    .buttonStyle(BrutalButtonStyle())
            }
        }
    }

    private static let repository = URL(string: "https://github.com/LorcanChinnock/shot")!
    private static let guide = URL(string: "https://shot.lorcanchinnock.com/docs/")!
    private static let sponsors = URL(string: "https://github.com/sponsors/LorcanChinnock")!
}

private struct PermissionRow: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let mediaType: AVMediaType
    @Binding var status: AVAuthorizationStatus
    let pane: String

    var body: some View {
        SettingRow(title: title, subtitle: subtitle) {
            HStack(spacing: 10) {
                BrutalBadge(text: label, dot: status == .authorized ? Brutal.success : nil)
                // macOS asks only while the status is not determined; after a denial only System Settings can change it.
                if status == .notDetermined {
                    Button("Grant") {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: mediaType)
                            status = AVCaptureDevice.authorizationStatus(for: mediaType)
                        }
                    }
                    .buttonStyle(BrutalButtonStyle())
                } else {
                    Button("Open") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                    }
                    .buttonStyle(BrutalButtonStyle())
                }
            }
        }
    }

    private var label: LocalizedStringResource {
        switch status {
        case .authorized: "GRANTED"
        case .notDetermined: "NOT ASKED"
        default: "DENIED"
        }
    }
}
