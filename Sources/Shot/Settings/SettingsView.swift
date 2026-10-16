import AVFoundation
import ServiceManagement
import ShotCore
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case gallery, general, capture, quickAccess, recording, agents, shortcuts, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gallery: String(localized: "Gallery")
        case .general: String(localized: "General")
        case .capture: String(localized: "Capture")
        case .quickAccess: String(localized: "Quick Access")
        case .recording: String(localized: "Recording")
        case .agents: String(localized: "Agents")
        case .shortcuts: String(localized: "Shortcuts")
        case .about: String(localized: "About")
        }
    }

    var subtitle: String {
        switch self {
        case .gallery: String(localized: "Every capture in your folder.")
        case .general: String(localized: "Behaviour, files and formats.")
        case .capture: String(localized: "What happens when you take a shot.")
        case .quickAccess: String(localized: "The floating card after each capture.")
        case .recording: String(localized: "Screen recording video and audio.")
        case .agents: String(localized: "Hand captures to AI assistants and coding tools.")
        case .shortcuts: String(localized: "Global hotkeys for every action.")
        case .about: String(localized: "Version, updates, permissions and reset.")
        }
    }

    var symbol: String {
        switch self {
        case .gallery: "photo.on.rectangle"
        case .general: "gearshape"
        case .capture: "viewfinder"
        case .quickAccess: "rectangle.stack"
        case .recording: "record.circle"
        case .agents: "terminal"
        case .shortcuts: "command"
        case .about: "info.circle"
        }
    }

    /// Each section has its own colour. A new section needs a new `Brutal` token, not a repeat.
    var color: Color {
        switch self {
        case .gallery: Brutal.violet
        case .general: Brutal.yellow
        case .capture: Brutal.pink
        case .quickAccess: Brutal.sky
        case .recording: Brutal.red
        case .agents: Brutal.mint
        case .shortcuts: Brutal.orange
        case .about: Brutal.lime
        }
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var section: SettingsSection = .gallery
}

struct SettingsView: View {
    private static let bottomInset = Brutal.windowInset - 6

    @Bindable private var navigation = SettingsNavigation.shared
    @State private var scrolledPast = ScrollFade.Edges()
    @Environment(\.colorScheme) private var colorScheme
    private var section: SettingsSection { navigation.section }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            Sidebar(selection: $navigation.section)
                .frame(width: 196)
            VStack(alignment: .leading, spacing: 16) {
                header
                if section == .gallery {
                    let model = GalleryController.shared.model
                    GalleryRootView(model: model)
                        .onAppear { model.start() }
                        .onDisappear { model.stop() }
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            content
                        }
                        .padding(.trailing, Brutal.groupInset + SystemScroller.shared.overlayRoom)
                        .padding(.bottom, Brutal.sectionGap)
                        .padding([.leading, .top], 3)
                        .tracklessScroller()
                    }
                    .onScrollGeometryChange(for: ScrollFade.Edges.self) { geometry in
                        ScrollFade.Edges(
                            top: geometry.contentOffset.y > -geometry.contentInsets.top,
                            bottom: geometry.visibleRect.maxY < geometry.contentSize.height
                        )
                    } action: { _, edges in
                        scrolledPast = edges
                    }
                    .mask(ScrollFade(edges: scrolledPast))
                    // The scroll view reaches into the window margin, so the scroller sits there, beside the cards.
                    .padding(.trailing, -SystemScroller.shared.width)
                    .id(section)
                }
            }
        }
        .padding(.top, GlassWindow.titlebarHeight + 8)
        .padding(.horizontal, Brutal.windowInset)
        .padding(.bottom, Self.bottomInset)
        .frame(minWidth: MainWindowController.minSize.width, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
                .font(Brutal.title(30))
                .foregroundStyle(Brutal.ink)
                .padding(.horizontal, 4)
                .background(alignment: .bottom) {
                    // On dark, an underline below the letters: off-white text over the marker would lose its contrast.
                    if colorScheme == .dark {
                        section.color.frame(height: 5)
                    } else {
                        section.color.frame(height: 12).offset(y: -4)
                    }
                }
            Text(section.subtitle)
                .font(.scaled(13, weight: .medium))
                .foregroundStyle(Brutal.faded(0.65))
        }
        .animation(.easeOut(duration: 0.15), value: section)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .gallery: EmptyView()
        case .general: GeneralSettings()
        case .capture: CaptureSettings()
        case .quickAccess: QuickAccessSettings()
        case .recording: RecordingSettings()
        case .agents: AgentSettings()
        case .shortcuts: ShortcutSettings()
        case .about: AboutSettings()
        }
    }
}

/// Fades scrolled content out at an edge it runs past, instead of cutting it against a hard line. An edge with nothing
/// past it stays sharp, so the first and last cards aren't faded at rest.
private struct ScrollFade: View {
    struct Edges: Equatable {
        var top = false
        var bottom = false
    }

    let edges: Edges

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                LinearGradient(colors: [edges.top ? .clear : .black, .black], startPoint: .top, endPoint: .bottom).frame(height: 8)
                Color.black
                LinearGradient(colors: [.black, edges.bottom ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: 18)
            }
            // The scroller stays sharp.
            Color.black.frame(width: SystemScroller.shared.width)
        }
    }
}

/// The bundle's app icon, which already carries its own soft shadow.
private struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityLabel("Shot")
    }
}

// MARK: Sidebar

private struct Sidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AppIconView(size: 44)
                Text("Shot").font(Brutal.title(24)).foregroundStyle(Brutal.ink)
            }
            .padding(.bottom, 14)
            ForEach(SettingsSection.allCases) { item in
                SidebarItem(section: item, selected: item == selection) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        selection = item
                    }
                }
            }
            Spacer()
        }
    }
}

private struct SidebarItem: View {
    let section: SettingsSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.scaled(14, weight: .semibold))
                    .foregroundStyle(Brutal.ink)
                    .frame(width: 28, height: 28)
                    .brutalSurface(section.color, radius: Brutal.Radius.button, shadow: 0, border: 2)
                Text(section.title)
                    .font(.scaled(13.5, weight: selected ? .heavy : .semibold))
                    .foregroundStyle(Brutal.ink)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background {
                if selected {
                    Color.clear.brutalSurface(Brutal.paper.opacity(0.6), glass: true, radius: Brutal.Radius.panel, shadow: 3)
                } else if hovering {
                    RoundedRectangle(cornerRadius: Brutal.Radius.panel, style: .circular).fill(Brutal.ink.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: General

private struct GeneralSettings: View {
    @Setting(PreferenceKey.playSound) private var playSound: Bool
    @Setting(PreferenceKey.hidesShotUI) private var hidesShotUI: Bool
    @Setting(PreferenceKey.excludesMenuBar) private var excludesMenuBar: Bool
    @Setting(PreferenceKey.saveFolder) private var saveFolder: String
    @Setting(PreferenceKey.filePrefix) private var filePrefix: String
    @Setting(PreferenceKey.imageFormat) private var imageFormat: ImageFormat
    @Setting(PreferenceKey.downscaleRetina) private var downscaleRetina: Bool
    @Setting(PreferenceKey.textSize) private var textSize: TextSize
    @Setting(PreferenceKey.appearance) private var appearance: AppearanceMode
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let color = SettingsSection.general.color

    var body: some View {
        SettingsCard(title: "Behaviour", symbol: "slider.horizontal.3") {
            ToggleRow(title: "Open Shot at login", subtitle: "Start Shot when you log in to your Mac.", isOn: $launchAtLogin, color: color)
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            ToggleRow(title: "Play capture sound", isOn: $playSound, color: color)
            ToggleRow(title: "Hide Shot from captures", subtitle: "Keep Quick Access cards, toasts and other Shot windows out of screenshots and recordings. The camera bubble always shows.", isOn: $hidesShotUI, color: color)
            ToggleRow(title: "Exclude menu bar", subtitle: "Crop the menu bar and notch off screenshots and recordings of the full screen.", isOn: $excludesMenuBar, color: color)
            SettingRow(title: "Appearance", subtitle: "Shot's windows and panels. Captures look the same either way.") {
                BrutalSegmented(selection: $appearance, options: AppearanceMode.allCases.map { ($0, Self.title(of: $0)) }, color: color)
            }
            SettingRow(title: "Text size", subtitle: "Text in Shot's windows, panels and toasts. Captures keep their size.", divider: false) {
                BrutalSegmented(selection: $textSize, options: TextSize.allCases.map { ($0, Self.title(of: $0)) }, color: color)
            }
        }
        SettingsCard(title: "Files", symbol: "folder.fill") {
            SettingRow(title: String(localized: "Save folder"), subtitle: (saveFolder as NSString).abbreviatingWithTildeInPath) {
                HStack(spacing: 10) {
                    Button("Reveal") { NSWorkspace.shared.open(URL(fileURLWithPath: saveFolder)) }
                        .buttonStyle(BrutalButtonStyle(compact: true))
                    Button("Choose…", action: chooseFolder)
                        .buttonStyle(BrutalButtonStyle(color: color, compact: true))
                }
            }
            SettingRow(title: "File name", subtitle: "\(previewName).\(imageFormat.fileExtension)") {
                TextField("Shot", text: $filePrefix)
                    .textFieldStyle(.plain)
                    .font(.scaled(13, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(width: 150, height: 30)
                    .brutalSurface(Brutal.paper.opacity(0.85), radius: Brutal.Radius.button, shadow: 2)
            }
            SettingRow(title: "Image format", subtitle: "Clipboard copies always use PNG.") {
                BrutalSegmented(selection: $imageFormat, options: [(ImageFormat.png, "PNG"), (.jpeg, "JPEG")], color: color)
            }
            ToggleRow(title: "Scale Retina captures to 1×", subtitle: "Halves pixel size on 2× displays. Smaller files, less detail.", isOn: $downscaleRetina, color: color, divider: false)
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
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = url.path
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
    @Setting(PreferenceKey.captureShowsCursor) private var showsCursor: Bool
    @Setting(PreferenceKey.windowShadow) private var windowShadow: Bool
    private let color = SettingsSection.capture.color

    var body: some View {
        SettingsCard(title: "After capture", symbol: "bolt.fill") {
            ToggleRow(title: "Save to folder", isOn: $save, color: color)
            ToggleRow(title: "Copy to clipboard", isOn: $copy, color: color)
            ToggleRow(title: "Show Quick Access", isOn: $quickAccess, color: color)
            ToggleRow(title: "Open in editor", subtitle: "Opens the annotation editor instead of Quick Access.", isOn: $openEditor, color: color, divider: false)
        }
        SettingsCard(title: "Selection", symbol: "plus.viewfinder") {
            ToggleRow(title: "Magnifier", subtitle: "8× loupe next to the pointer for pixel-precise edges.", isOn: $magnifier, color: color)
            ToggleRow(title: "Crosshair", subtitle: "Full-screen guide lines through the pointer.", isOn: $crosshair, color: color)
            ToggleRow(title: "Show cursor", subtitle: "Show the pointer when you capture an area or the full screen.", isOn: $showsCursor, color: color)
            ToggleRow(title: "Window shadow", subtitle: "Keep the macOS drop shadow in window captures.", isOn: $windowShadow, color: color, divider: false)
        }
    }
}

// MARK: Quick Access

private struct QuickAccessSettings: View {
    @Setting(PreferenceKey.quickAccessPosition) private var position: QuickAccessPosition
    @Setting(PreferenceKey.quickAccessDuration) private var duration: Double
    private let color = SettingsSection.quickAccess.color

    var body: some View {
        SettingsCard(title: "Placement", symbol: "rectangle.bottomhalf.inset.filled") {
            SettingRow(title: "Screen corner") {
                BrutalSegmented(selection: $position, options: [(QuickAccessPosition.left, "Bottom left"), (.right, "Bottom right")], color: color)
            }
            SettingRow(title: "Auto-close", subtitle: "Hovering a card pauses the timer.", divider: false) {
                BrutalSegmented(selection: $duration, options: [(4.0, "4s"), (8.0, "8s"), (15.0, "15s"), (30.0, "30s"), (0.0, "Never")], color: color)
            }
        }
        ScreenPreview(position: position, color: color)
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
                    BrutalChip(text: "PREVIEW")
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
    @Setting(PreferenceKey.recordingCountdown) private var countdown: Int
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
        SettingsCard(title: "Starting", symbol: "record.circle") {
            ToggleRow(title: "Adjust before recording", subtitle: "Shows the frame handles and options first. Hold ⌥ as you finish the selection to show them once.", isOn: $adjust, color: color)
            SettingRow(title: "Countdown", subtitle: "Counts down before recording starts.", divider: false) {
                BrutalSegmented(selection: $countdown, options: RecordingStart.countdowns.map { ($0, $0 == 0 ? "Off" : "\($0) s") }, color: color)
            }
        }
        SettingsCard(title: "Video", symbol: "film.fill") {
            SettingRow(title: "Frame rate", subtitle: frameRateSubtitle) {
                BrutalSegmented(selection: $fps, options: frameRates.map { ($0, "\($0) fps") }, color: color)
            }
            ToggleRow(title: "Show cursor", isOn: $showsCursor, color: color)
            ToggleRow(title: "Show clicks", subtitle: "Draws a circle where you click.", isOn: $showsClicks, color: color)
            ToggleRow(title: "Region border", subtitle: "A red border around the recorded area. It never appears in the video.", isOn: $border, color: color)
            ToggleRow(title: "Copy to clipboard", subtitle: "Copies the finished recording, ready to paste as a file.", isOn: $copy, color: color, divider: false)
        }
        AudioSettings(color: color)
        CameraSettings(color: color)
        SettingsCard(title: "GIF export", symbol: "photo.stack.fill") {
            SettingRow(title: "From the Quick Access card", subtitle: "Uses the video editor's last GIF settings: \(Preferences().videoExportOptions.gifSummary)", divider: false) {
                BrutalChip(text: "GIF", color: color)
            }
        }
    }
}

private struct AudioSettings: View {
    let color: Color
    @Setting(PreferenceKey.recordMicrophone) private var microphone: Bool
    @Setting(PreferenceKey.microphoneDeviceID) private var deviceID: String
    @Setting(PreferenceKey.recordSystemAudio) private var systemAudio: Bool
    @State private var devices: [AVCaptureDevice] = []
    private let preview = DevicePreview.microphone

    private var testSubtitle: LocalizedStringResource {
        preview.isRunning ? "Speak to see the level." : "Shows the input level of the microphone above."
    }

    var body: some View {
        SettingsCard(title: "Audio", symbol: "waveform") {
            ToggleRow(title: "Microphone", subtitle: "macOS asks for permission on first use. Mute it from the recording controls.", isOn: $microphone, color: color)
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
                    .buttonStyle(BrutalButtonStyle(color: preview.isRunning ? color : Brutal.paper, compact: true))
                }
            }
            ToggleRow(title: "System audio", subtitle: "Sound from other apps. Shot's own sounds are excluded.", isOn: $systemAudio, color: color, divider: false)
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
    let color: Color
    @Setting(PreferenceKey.recordCamera) private var camera: Bool
    @Setting(PreferenceKey.cameraDeviceID) private var deviceID: String
    @Setting(PreferenceKey.cameraSize) private var size: CameraBubbleSize
    @State private var devices: [AVCaptureDevice] = []
    private let preview = DevicePreview.camera

    var body: some View {
        SettingsCard(title: "Camera", symbol: "web.camera.fill") {
            ToggleRow(title: "Camera bubble", subtitle: "Round webcam overlay recorded with your screen. Drag to move, double-click to resize.", isOn: $camera, color: color)
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
                    .buttonStyle(BrutalButtonStyle(color: preview.isRunning ? color : Brutal.paper, compact: true))
                }
            }
            SettingRow(title: "Bubble size", divider: false) {
                BrutalSegmented(selection: $size, options: CameraBubbleSize.allCases.map { ($0, Self.title(of: $0)) }, color: color)
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

    private static func title(of size: CameraBubbleSize) -> String {
        switch size {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
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
        BrutalDropdown(title: "Device", entries: [
            .item("System default", selected: !devices.contains { $0.uniqueID == selection }) { selection = "" },
            .divider,
        ] + devices.map { device in
            .item(device.localizedName, selected: device.uniqueID == selection) { selection = device.uniqueID }
        }) {
            HStack(spacing: 6) {
                Text(selectedName).lineLimit(1)
                Image(systemName: "chevron.down").font(.scaled(9, weight: .black))
            }
            .frame(maxWidth: 190)
        }
        .buttonStyle(BrutalButtonStyle(compact: true))
        .fixedSize()
    }

    private var selectedName: String {
        devices.first { $0.uniqueID == selection }?.localizedName ?? String(localized: "System default")
    }
}

// MARK: Agents

private struct AgentSettings: View {
    @Setting(PreferenceKey.agentHandoff) private var handoff: Bool
    @Setting(PreferenceKey.agentCapture) private var capture: Bool
    @State private var agents = AgentClient.shown(installed: AgentClient.installed(home: NSHomeDirectory()))
    @State private var statuses: [AgentClient: AgentClient.Status] = [:]
    @State private var installing: AgentClient?
    private let color = SettingsSection.agents.color

    /// The MCP server inside this app's bundle, so a dev build names its own.
    private static let server = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/shot-cli").path
    /// The name agents list the server under: `shot-dev` for a dev build, so installing one never replaces the release.
    private static let name = CommandLink.name(bundleID: Bundle.main.bundleIdentifier)

    var body: some View {
        SettingsCard(title: "Hand-off", symbol: "arrow.right.doc.on.clipboard") {
            ToggleRow(
                title: "Hand captures to agents",
                subtitle: "Saves the app, window and your marks in each screenshot, and saves copied ones as files too, so agents can read them.",
                isOn: $handoff, color: color, divider: false
            )
        }
        SettingsCard(title: "Capture", symbol: "macwindow") {
            ToggleRow(
                title: "Let agents capture and record",
                subtitle: "Lets agents screenshot or record a window by name. Shot shows a notice each time. Recordings skip the microphone and camera and stop after \(Int(AgentRequest.maximumDuration / 60)) minutes.",
                isOn: $capture, color: color, divider: false
            )
        }
        SettingsCard(title: "Command line", symbol: "apple.terminal") {
            CardNote(text: "For agents and scripts that run in a terminal. The MCP server works without it.")
            CommandLinkRow(cli: Self.server)
        }
        SettingsCard(title: "MCP server", symbol: "terminal.fill") {
            CardNote(text: "Lets agents read your captures and save edited copies beside them. Your originals never change. What an agent reads goes to its model provider, so blur private details first.")
            ForEach(agents, id: \.self) { agent in
                CommandRow(title: title(agent), command: agent.setup(server: Self.server, name: Self.name), divider: agent != agents.last) {
                    installButton(agent)
                }
            }
        }
        .task { await findAgents() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await findAgents() }
        }
    }

    private func title(_ agent: AgentClient) -> LocalizedStringResource {
        switch agent {
        case .claude: "Claude"
        case .lmStudio: "LM Studio"
        case .raycast: "Raycast"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .vsCode: "VS Code"
        case .gemini: "Gemini CLI"
        case .windsurf: "Windsurf"
        case .zed: "Zed"
        case .json: "Any other app"
        }
    }

    /// Install, or Update when the server points at another copy of Shot, or a chip once it's set up. Nothing for the
    /// setups Shot can only copy.
    @ViewBuilder
    private func installButton(_ agent: AgentClient) -> some View {
        if agent.install(server: Self.server, name: Self.name) != nil {
            switch statuses[agent] ?? .unknown {
            case .installed:
                BrutalChip(text: "INSTALLED", color: Brutal.mint)
            case let status:
                Button(status == .stale ? "Update" : "Install") {
                    installing = agent
                    Task {
                        await AgentInstaller.install(agent, title: String(localized: title(agent)), server: Self.server, name: Self.name, replacing: status == .stale)
                        installing = nil
                        await findAgents()
                    }
                }
                .buttonStyle(BrutalButtonStyle(compact: true))
                .disabled(installing != nil)
            }
        }
    }

    /// Checks again each time Shot comes forward, so an agent installed, or set up, while Settings is open shows up.
    /// Reads the configs off the main thread, since Claude Code's can run to megabytes.
    private func findAgents() async {
        let (found, statuses) = await Task.detached {
            let home = NSHomeDirectory()
            let found = AgentClient.shown(installed: AgentClient.installed(home: home))
            return (found, Dictionary(uniqueKeysWithValues: found.map { ($0, $0.status(server: Self.server, name: Self.name, home: home)) }))
        }.value
        agents = found
        self.statuses = statuses
    }
}

/// A short note at the top of a card, above its rows.
private struct CardNote: View {
    let text: LocalizedStringResource

    var body: some View {
        Text(text)
            .font(Brutal.caption)
            .foregroundStyle(Brutal.faded(0.65))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
    }
}

/// Installs or removes the `shot` command, a link in `/usr/local/bin` to this app's `shot-cli`, with an administrator's
/// password.
private struct CommandLinkRow: View {
    let cli: String
    @State private var status = CommandLink.Status.missing
    @State private var working = false
    private let name = CommandLink.name(bundleID: Bundle.main.bundleIdentifier)
    private var link: String { (CommandLink.folder as NSString).appendingPathComponent(name) }

    var body: some View {
        SettingRow(title: String(localized: "\(name) command"), subtitle: subtitle, divider: false) {
            switch status {
            case .missing:
                button("Install", CommandLink.installScript(name: name, cli: cli))
            case .linked:
                button("Uninstall", CommandLink.uninstallScript(name: name))
            case .stale:
                button("Reinstall", CommandLink.installScript(name: name, cli: cli))
            case .homebrew:
                BrutalChip(text: "INSTALLED", color: Brutal.mint)
            case .taken:
                EmptyView()
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private var subtitle: String {
        switch status {
        case .missing: String(localized: "Installing asks for your password once.")
        case .linked: String(localized: "Installed at \(link). Updates with Shot.")
        case .homebrew: String(localized: "Installed by Homebrew. Updates with Shot.")
        case .stale: String(localized: "Points to a copy of Shot that has moved. Reinstall to fix it.")
        case .taken: String(localized: "Another program uses \(link). Run \(cli) instead.")
        }
    }

    private func button(_ title: LocalizedStringResource, _ script: String) -> some View {
        Button(String(localized: title)) { run(script) }
            .buttonStyle(BrutalButtonStyle(compact: true))
            .disabled(working)
    }

    private func refresh() {
        status = CommandLink.status(name: name, cli: cli)
    }

    /// Runs `script` through `osascript`, whose password prompt would stall the main thread if run in process.
    private func run(_ script: String) {
        working = true
        Task {
            let failure = await Task.detached { () -> String? in
                let process = Process()
                let errors = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                process.standardError = errors
                do {
                    try process.run()
                } catch {
                    return error.localizedDescription
                }
                let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                // -128 is the user cancelling the password prompt, which needs no message.
                guard process.terminationStatus != 0, !message.contains("(-128)") else {
                    return nil
                }
                return message.trimmingCharacters(in: .whitespacesAndNewlines)
            }.value
            working = false
            refresh()
            if let failure {
                Toast.error("Couldn't change the \(name) command: \(failure)")
            }
        }
    }
}

/// A command to paste into a terminal or a config file, with a button that copies it, and `accessory` before that.
private struct CommandRow<Accessory: View>: View {
    let title: LocalizedStringResource
    let command: String
    var divider = true
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(title).font(Brutal.label).foregroundStyle(Brutal.ink)
                Spacer(minLength: 8)
                accessory
                Button("Copy") {
                    Clipboard.copy(string: command)
                    Toast.show("Copied")
                }
                .buttonStyle(BrutalButtonStyle(compact: true))
            }
            Text(command)
                .font(Brutal.mono)
                .foregroundStyle(Brutal.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .brutalSurface(Brutal.paper.opacity(0.85), radius: Brutal.Radius.button, shadow: 2)
        }
        .padding(.vertical, 9)
        if divider {
            Rectangle().fill(Brutal.faint(0.12)).frame(height: 1.5)
        }
    }
}

// MARK: Shortcuts

private struct ShortcutSettings: View {
    private let color = SettingsSection.shortcuts.color
    @Setting(PreferenceKey.replacesSystemScreenshots) private var replacesSystemScreenshots: Bool
    @State private var macOSOwnsKeys = SystemShortcuts.macOSOwnsKeys

    private var useShot: Binding<Bool> {
        Binding(get: { replacesSystemScreenshots }, set: { on in
            SystemShortcuts.useShot(on)
            macOSOwnsKeys = SystemShortcuts.macOSOwnsKeys
        })
    }

    var body: some View {
        SettingsCard(title: "macOS screenshot keys", symbol: "command") {
            ToggleRow(title: "Use Shot for ⌘⇧3 to ⌘⇧5", subtitle: "Turns off the matching macOS shortcuts, so these keys and a keyboard's screenshot key open Shot. macOS gets them back while Shot isn't running, or when you turn this off.", isOn: useShot, color: color, divider: replacesSystemScreenshots && macOSOwnsKeys)
            if replacesSystemScreenshots && macOSOwnsKeys {
                SettingRow(title: "macOS still uses these keys", subtitle: "Turn off the Screenshots shortcuts under Keyboard Shortcuts.", divider: false) {
                    Button("Open") { SystemShortcuts.openKeyboardSettings() }
                        .buttonStyle(BrutalButtonStyle(compact: true))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            macOSOwnsKeys = SystemShortcuts.macOSOwnsKeys
        }

        SettingsCard(title: "Global hotkeys", symbol: "keyboard.fill") {
            ForEach(Array(ShotAction.allCases.enumerated()), id: \.element) { index, action in
                SettingRow(title: action.title, divider: index < ShotAction.allCases.count - 1) {
                    ShortcutRecorderView(action: action, color: color)
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
                .buttonStyle(BrutalButtonStyle(color: color, compact: true))
        }
        .padding(.horizontal, 4)
    }
}

// MARK: About

private struct AboutSettings: View {
    @State private var screenGranted = Permissions.hasScreenCapture
    @State private var screenRequested = Permissions.requestedScreenCapture
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var confirmingReset = false
    @State private var iconClicks = 0
    @Setting(PreferenceKey.partyModeUnlocked) private var partyUnlocked: Bool
    @Setting(PreferenceKey.partyMode) private var party: Bool
    @Bindable private var updater = Updater.shared
    private let color = SettingsSection.about.color

    private func refreshPermissions() {
        screenGranted = Permissions.hasScreenCapture
        screenRequested = Permissions.requestedScreenCapture
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
                .onTapGesture {
                    iconClicks += 1
                    if iconClicks >= PartyMode.clicksToUnlock {
                        partyUnlocked = true
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Shot").font(Brutal.title(26)).foregroundStyle(Brutal.ink)
                    BrutalChip(text: "BETA", color: Brutal.yellow)
                }
                Text("Screenshots and screen recordings for macOS.")
                    .font(.scaled(12.5, weight: .medium)).foregroundStyle(Brutal.faded(0.65))
            }
            Spacer()
            BrutalChip(text: "v\(version)", color: color)
        }
        .padding(16)
        .glassCard()

        if partyUnlocked {
            SettingsCard(title: "You found it", symbol: "party.popper.fill") {
                ToggleRow(title: "Party mode", subtitle: "Confetti on every capture and recording, and a rainbow through the editors. Reduce Motion keeps the colours still and skips the confetti.", isOn: $party, color: color, divider: false)
            }
        }

        SettingsCard(title: "Updates", symbol: "arrow.down.circle.fill") {
            ToggleRow(title: "Check for updates automatically", subtitle: "Shot asks GitHub once a day whether a new version is out, and installs it when you agree. Nothing else is sent.", isOn: $updater.automaticallyChecks, color: color)
            SettingRow(title: "Check now", subtitle: "Looks for a new version once, even when automatic checks are off.", divider: false) {
                Button("Check") { updater.checkForUpdates() }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                    .disabled(!updater.canCheckForUpdates)
            }
        }

        SettingsCard(title: "Permissions", symbol: "lock.fill") {
            SettingRow(title: "Screen & System Audio Recording", subtitle: "Required for every capture.") {
                HStack(spacing: 10) {
                    BrutalChip(text: screenGranted ? "GRANTED" : "MISSING", color: screenGranted ? Brutal.mint : Brutal.red)
                    if !screenGranted, !screenRequested {
                        Button("Grant") {
                            Permissions.requestScreenCapture()
                            screenRequested = true
                        }
                        .buttonStyle(BrutalButtonStyle(compact: true))
                    } else {
                        Button("Open") { Permissions.openSettings() }
                            .buttonStyle(BrutalButtonStyle(compact: true))
                    }
                }
            }
            PermissionRow(title: "Microphone", subtitle: "Only needed to record your voice.", mediaType: .audio, status: $microphoneStatus, pane: "Privacy_Microphone")
            PermissionRow(title: "Camera", subtitle: "Only needed for the camera bubble.", mediaType: .video, status: $cameraStatus, pane: "Privacy_Camera", divider: false)
        }
        // A menu bar app may not become active when Settings opens or regains focus, so also re-read when the window
        // appears and when it becomes key.
        .onAppear(perform: refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refreshPermissions() }

        SettingsCard(title: "Data", symbol: "externaldrive.fill") {
            SettingRow(title: String(localized: "Save folder"), subtitle: (Preferences().saveFolder.path as NSString).abbreviatingWithTildeInPath) {
                Button("Open") {
                    let folder = Preferences().saveFolder
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }
                .buttonStyle(BrutalButtonStyle(compact: true))
            }
            SettingRow(title: "Reset all settings", subtitle: "Restores every setting and shortcut. Your captures stay.", divider: false) {
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
                .buttonStyle(BrutalButtonStyle(color: confirmingReset ? Brutal.red : Brutal.paper, compact: true))
            }
        }

        SettingsCard(title: "Project", symbol: "chevron.left.forwardslash.chevron.right") {
            SettingRow(title: "Source code", subtitle: "Free and open source under the GPL-3.0 license.") {
                Button("GitHub") { NSWorkspace.shared.open(Self.repository) }
                    .buttonStyle(BrutalButtonStyle(compact: true))
            }
            SettingRow(title: "User Guide", subtitle: "How to use every part of Shot.") {
                Button("Open") { NSWorkspace.shared.open(Self.guide) }
                    .buttonStyle(BrutalButtonStyle(compact: true))
            }
            SettingRow(title: "Acknowledgements", subtitle: "Shot comes with no warranty. It updates itself with Sparkle, under the MIT license.") {
                Button("View") {
                    if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(BrutalButtonStyle(compact: true))
            }
            SettingRow(title: "Support Shot", subtitle: "Shot is free, with no ads or account. Sponsoring keeps it that way.") {
                Button("Sponsor") { NSWorkspace.shared.open(Self.sponsors) }
                    .buttonStyle(BrutalButtonStyle(compact: true))
            }
            SettingRow(title: "Report a problem", subtitle: "Bug reports and ideas are welcome.", divider: false) {
                Button("New Issue") { NSWorkspace.shared.open(Self.repository.appending(path: "issues/new/choose")) }
                    .buttonStyle(BrutalButtonStyle(compact: true))
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
    var divider = true

    var body: some View {
        SettingRow(title: title, subtitle: subtitle, divider: divider) {
            HStack(spacing: 10) {
                BrutalChip(text: label, color: status == .authorized ? Brutal.mint : status == .notDetermined ? Brutal.paper : Brutal.red)
                // macOS asks only while the status is not determined; after a denial only System Settings can change it.
                if status == .notDetermined {
                    Button("Grant") {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: mediaType)
                            status = AVCaptureDevice.authorizationStatus(for: mediaType)
                        }
                    }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                } else {
                    Button("Open") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                    }
                    .buttonStyle(BrutalButtonStyle(compact: true))
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
