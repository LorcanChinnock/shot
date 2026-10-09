import AVFoundation
import ServiceManagement
import ShotCore
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case gallery, general, capture, quickAccess, recording, shortcuts, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gallery: "Gallery"
        case .general: "General"
        case .capture: "Capture"
        case .quickAccess: "Quick Access"
        case .recording: "Recording"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .gallery: "Every capture in your folder."
        case .general: "Behavior, files and formats."
        case .capture: "What happens when you take a shot."
        case .quickAccess: "The floating card after each capture."
        case .recording: "Screen recording video and audio."
        case .shortcuts: "Global hotkeys for every action."
        case .about: "Version, updates, permissions and reset."
        }
    }

    var symbol: String {
        switch self {
        case .gallery: "photo.on.rectangle"
        case .general: "gearshape"
        case .capture: "viewfinder"
        case .quickAccess: "rectangle.stack"
        case .recording: "record.circle"
        case .shortcuts: "command"
        case .about: "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .gallery: Brutal.violet
        case .general: Brutal.yellow
        case .capture: Brutal.pink
        case .quickAccess: Brutal.sky
        case .recording: Brutal.red
        case .shortcuts: Brutal.violet
        case .about: Brutal.mint
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
    @Bindable private var navigation = SettingsNavigation.shared
    @State private var scrolledPast = ScrollFade.Edges()
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
                        .padding(.trailing, Brutal.groupInset)
                        .padding(.bottom, Brutal.sectionGap)
                        .padding([.leading, .top], 3)
                    }
                    .scrollIndicators(.never)
                    .onScrollGeometryChange(for: ScrollFade.Edges.self) { geometry in
                        ScrollFade.Edges(
                            top: geometry.contentOffset.y > -geometry.contentInsets.top,
                            bottom: geometry.visibleRect.maxY < geometry.contentSize.height
                        )
                    } action: { _, edges in
                        scrolledPast = edges
                    }
                    .mask(ScrollFade(edges: scrolledPast))
                    .id(section)
                }
            }
        }
        .padding(.top, GlassWindow.titlebarHeight + 8)
        .padding(.horizontal, Brutal.windowInset)
        .padding(.bottom, Brutal.windowInset - 6)
        .frame(minWidth: MainWindowController.minSize.width, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
                .font(Brutal.title(30))
                .foregroundStyle(Brutal.ink)
                .padding(.horizontal, 4)
                .background(alignment: .bottom) {
                    section.color.frame(height: 12).offset(y: -4)
                }
            Text(section.subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Brutal.ink.opacity(0.65))
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
        VStack(spacing: 0) {
            LinearGradient(colors: [edges.top ? .clear : .black, .black], startPoint: .top, endPoint: .bottom).frame(height: 8)
            Color.black
            LinearGradient(colors: [.black, edges.bottom ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: 18)
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brutal.ink)
                    .frame(width: 28, height: 28)
                    .brutalSurface(section.color, radius: 8, shadow: 0, border: 2)
                Text(section.title)
                    .font(.system(size: 13.5, weight: selected ? .heavy : .semibold))
                    .foregroundStyle(Brutal.ink)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background {
                if selected {
                    Color.clear.brutalSurface(Color.white.opacity(0.6), glass: true, radius: 10, shadow: 3)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 10, style: .circular).fill(Brutal.ink.opacity(0.06))
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
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let color = SettingsSection.general.color

    var body: some View {
        SettingsCard(title: "Behavior", symbol: "slider.horizontal.3") {
            ToggleRow(title: "Launch at login", subtitle: "Start Shot when you log in to your Mac.", isOn: $launchAtLogin, color: color)
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            ToggleRow(title: "Play capture sound", isOn: $playSound, color: color)
            ToggleRow(title: "Hide Shot UI", subtitle: "Keep Quick Access cards, toasts and other Shot windows out of screenshots and recordings. The camera bubble always shows.", isOn: $hidesShotUI, color: color)
            ToggleRow(title: "Exclude menu bar", subtitle: "Crop the menu bar and notch off full-screen screenshots and recordings.", isOn: $excludesMenuBar, color: color, divider: false)
        }
        SettingsCard(title: "Files", symbol: "folder.fill") {
            SettingRow(title: "Save folder", subtitle: (saveFolder as NSString).abbreviatingWithTildeInPath) {
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
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(width: 150, height: 30)
                    .brutalSurface(Color.white.opacity(0.85), radius: 8, shadow: 2)
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
            Toast.error("Launch at login failed: \(error.localizedDescription)")
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
            ToggleRow(title: "Include cursor", subtitle: "Show the pointer in area and fullscreen captures.", isOn: $showsCursor, color: color)
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
                Rectangle().fill(Color.white.opacity(0.7)).frame(height: 14)
                    .overlay(alignment: .bottom) { Rectangle().fill(Brutal.ink).frame(height: 2) }
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
                        .fill(index == 1 ? color : Color.white)
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
    @Setting(PreferenceKey.showRecordingBorder) private var border: Bool
    @Setting(PreferenceKey.copyAfterRecording) private var copy: Bool
    @Setting(PreferenceKey.adjustBeforeRecording) private var adjust: Bool
    @Setting(PreferenceKey.recordingCountdown) private var countdown: Int
    // Read only so the GIF summary updates when the video editor changes them.
    @Setting(PreferenceKey.gifFrameRate) private var gifFrameRate: Int
    @Setting(PreferenceKey.gifWidth) private var gifWidth: Int
    private let color = SettingsSection.recording.color

    var body: some View {
        SettingsCard(title: "Starting", symbol: "record.circle") {
            ToggleRow(title: "Adjust before recording", subtitle: "Shows the frame handles and options first. Hold ⌥ as you finish the selection to show them once.", isOn: $adjust, color: color)
            SettingRow(title: "Countdown", subtitle: "Counts down before recording starts.", divider: false) {
                BrutalSegmented(selection: $countdown, options: RecordingStart.countdowns.map { ($0, $0 == 0 ? "Off" : "\($0) s") }, color: color)
            }
        }
        SettingsCard(title: "Video", symbol: "film.fill") {
            SettingRow(title: "Frame rate", subtitle: "H.264 MP4.") {
                BrutalSegmented(selection: $fps, options: [(30, "30 fps"), (60, "60 fps")], color: color)
            }
            ToggleRow(title: "Show cursor", isOn: $showsCursor, color: color)
            ToggleRow(title: "Region border", subtitle: "Red outline around the recorded area. It never appears in the video.", isOn: $border, color: color)
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

    var body: some View {
        SettingsCard(title: "Audio", symbol: "waveform") {
            ToggleRow(title: "Microphone", subtitle: "macOS asks for permission on first use. Mute it from the recording controls.", isOn: $microphone, color: color)
            SettingRow(title: "Microphone input") {
                DevicePicker(devices: devices, selection: $deviceID)
            }
            SettingRow(title: "Test microphone", subtitle: preview.isRunning ? "Speak to see the level." : "Shows the input level of the microphone above.") {
                HStack(spacing: 10) {
                    LevelMeter(meter: preview.meter, muted: !preview.isRunning)
                    Button(preview.isRunning ? "Stop" : "Test") {
                        if preview.isRunning {
                            preview.stop()
                        } else {
                            Task { await preview.start(deviceID: deviceID) }
                        }
                    }
                    .buttonStyle(BrutalButtonStyle(color: preview.isRunning ? color : .white, compact: true))
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
                    .buttonStyle(BrutalButtonStyle(color: preview.isRunning ? color : .white, compact: true))
                }
            }
            SettingRow(title: "Bubble size", divider: false) {
                BrutalSegmented(selection: $size, options: CameraBubbleSize.allCases.map { ($0, $0.rawValue.capitalized) }, color: color)
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
        BrutalDropdown(title: "Device", entries: [
            .item("System default", selected: !devices.contains { $0.uniqueID == selection }) { selection = "" },
            .divider,
        ] + devices.map { device in
            .item(device.localizedName, selected: device.uniqueID == selection) { selection = device.uniqueID }
        }) {
            HStack(spacing: 6) {
                Text(selectedName).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .black))
            }
            .frame(maxWidth: 190)
        }
        .buttonStyle(BrutalButtonStyle(compact: true))
        .fixedSize()
    }

    private var selectedName: String {
        devices.first { $0.uniqueID == selection }?.localizedName ?? "System default"
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
                .foregroundStyle(Brutal.ink.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Restore defaults") {
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
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var confirmingReset = false
    @State private var iconClicks = 0
    @Setting(PreferenceKey.partyModeUnlocked) private var partyUnlocked: Bool
    @Setting(PreferenceKey.partyMode) private var party: Bool
    @Bindable private var updater = Updater.shared
    private let color = SettingsSection.about.color

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
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Brutal.ink.opacity(0.65))
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
                    Button("Open") { Permissions.openSettings() }
                        .buttonStyle(BrutalButtonStyle(compact: true))
                }
            }
            PermissionRow(title: "Microphone", subtitle: "Only needed to record your voice.", status: microphoneStatus, pane: "Privacy_Microphone")
            PermissionRow(title: "Camera", subtitle: "Only needed for the camera bubble.", status: cameraStatus, pane: "Privacy_Camera", divider: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenGranted = Permissions.hasScreenCapture
            microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }

        SettingsCard(title: "Data", symbol: "externaldrive.fill") {
            SettingRow(title: "Capture folder", subtitle: (Preferences().saveFolder.path as NSString).abbreviatingWithTildeInPath) {
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
                .buttonStyle(BrutalButtonStyle(color: confirmingReset ? Brutal.red : .white, compact: true))
            }
        }

        SettingsCard(title: "Project", symbol: "chevron.left.forwardslash.chevron.right") {
            SettingRow(title: "Source code", subtitle: "Free and open source under the GPL-3.0 license.") {
                Button("GitHub") { NSWorkspace.shared.open(Self.repository) }
                    .buttonStyle(BrutalButtonStyle(compact: true))
            }
            SettingRow(title: "Report a problem", subtitle: "Bug reports and ideas are welcome.", divider: false) {
                Button("New issue") { NSWorkspace.shared.open(Self.repository.appending(path: "issues/new/choose")) }
                    .buttonStyle(BrutalButtonStyle(compact: true))
            }
        }
    }

    private static let repository = URL(string: "https://github.com/LorcanChinnock/shot")!
}

private struct PermissionRow: View {
    let title: String
    let subtitle: String
    let status: AVAuthorizationStatus
    let pane: String
    var divider = true

    var body: some View {
        SettingRow(title: title, subtitle: subtitle, divider: divider) {
            HStack(spacing: 10) {
                BrutalChip(text: label, color: status == .authorized ? Brutal.mint : status == .notDetermined ? Color.white : Brutal.red)
                Button("Open") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
                .buttonStyle(BrutalButtonStyle(compact: true))
            }
        }
    }

    private var label: String {
        switch status {
        case .authorized: "GRANTED"
        case .notDetermined: "NOT ASKED"
        default: "DENIED"
        }
    }
}
