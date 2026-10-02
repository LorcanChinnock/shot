import AVFoundation
import ServiceManagement
import ShotCore
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, capture, quickAccess, recording, shortcuts, about

    var id: String { rawValue }

    var title: String {
        switch self {
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
        case .general: "Startup, files and formats."
        case .capture: "What happens when you take a shot."
        case .quickAccess: "The floating card after each capture."
        case .recording: "Screen recording video and audio."
        case .shortcuts: "Global hotkeys for every action."
        case .about: "Version, permissions and reset."
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .capture: "viewfinder"
        case .quickAccess: "rectangle.stack.fill"
        case .recording: "record.circle.fill"
        case .shortcuts: "command"
        case .about: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
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
    var section: SettingsSection = .general
}

struct SettingsView: View {
    @Bindable private var navigation = SettingsNavigation.shared
    private var section: SettingsSection { navigation.section }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            Sidebar(selection: $navigation.section)
                .frame(width: 196)
            VStack(alignment: .leading, spacing: 16) {
                header
                ScrollView {
                    VStack(spacing: 18) {
                        content
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 24)
                    .padding([.leading, .top], 2)
                }
                .scrollIndicators(.never)
                .id(section)
            }
        }
        .padding(.top, 44)
        .padding(.horizontal, 22)
        .padding(.bottom, 4)
        .frame(width: SettingsWindowController.size.width, height: SettingsWindowController.size.height)
        .background(GlassBackdrop())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Brutal.ink, lineWidth: 3))
        .environment(\.colorScheme, .light)
        .ignoresSafeArea()
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
        case .general: GeneralSettings()
        case .capture: CaptureSettings()
        case .quickAccess: QuickAccessSettings()
        case .recording: RecordingSettings()
        case .shortcuts: ShortcutSettings()
        case .about: AboutSettings()
        }
    }
}

// MARK: Sidebar

private struct Sidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(Brutal.ink)
                    .frame(width: 36, height: 36)
                    .brutalSurface(Brutal.yellow, radius: 9, shadow: 3)
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
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Brutal.ink)
                    .frame(width: 26, height: 26)
                    .brutalSurface(section.color, radius: 7, shadow: selected ? 2 : 0)
                Text(section.title)
                    .font(.system(size: 13.5, weight: selected ? .heavy : .semibold))
                    .foregroundStyle(Brutal.ink)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if selected {
                    Color.clear.brutalSurface(Color.white.opacity(0.6), glass: true, radius: 10, shadow: 3)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brutal.ink.opacity(0.06))
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
    @AppStorage(PreferenceKey.playSound) private var playSound = true
    @AppStorage(PreferenceKey.saveFolder) private var saveFolder = Preferences.defaultSaveFolder
    @AppStorage(PreferenceKey.filePrefix) private var filePrefix = Preferences.defaultFilePrefix
    @AppStorage(PreferenceKey.imageFormat) private var imageFormat = ImageFormat.png.rawValue
    @AppStorage(PreferenceKey.downscaleRetina) private var downscaleRetina = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let color = SettingsSection.general.color

    var body: some View {
        SettingsCard(title: "Startup", symbol: "power") {
            ToggleRow(title: "Launch at login", subtitle: "Start Shot when you log in to your Mac.", isOn: $launchAtLogin, color: color)
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            ToggleRow(title: "Play capture sound", isOn: $playSound, color: color, divider: false)
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
            SettingRow(title: "File name", subtitle: "\(previewName).\(ImageFormat(rawValue: imageFormat)?.fileExtension ?? "png")") {
                TextField("Shot", text: $filePrefix)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(width: 150, height: 30)
                    .brutalSurface(Color.white.opacity(0.85), radius: 8, shadow: 2)
            }
            SettingRow(title: "Image format", subtitle: "Clipboard copies always use PNG.") {
                BrutalSegmented(selection: $imageFormat, options: [(ImageFormat.png.rawValue, "PNG"), (ImageFormat.jpeg.rawValue, "JPEG")], color: color)
            }
            ToggleRow(title: "Scale Retina captures to 1×", subtitle: "Halves pixel size on 2× displays. Smaller files, less detail.", isOn: $downscaleRetina, color: color, divider: false)
        }
    }

    private var previewName: String {
        let trimmed = filePrefix.trimmingCharacters(in: .whitespaces)
        return FileNaming.baseName(for: Date(), prefix: trimmed.isEmpty ? Preferences.defaultFilePrefix : trimmed.replacingOccurrences(of: "/", with: "-"))
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
            Toast.show("Launch at login failed: \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: Capture

private struct CaptureSettings: View {
    @AppStorage(PreferenceKey.saveAfterCapture) private var save = true
    @AppStorage(PreferenceKey.copyAfterCapture) private var copy = true
    @AppStorage(PreferenceKey.quickAccessAfterCapture) private var quickAccess = true
    @AppStorage(PreferenceKey.openEditorAfterCapture) private var openEditor = false
    @AppStorage(PreferenceKey.showMagnifier) private var magnifier = true
    @AppStorage(PreferenceKey.showCrosshair) private var crosshair = true
    @AppStorage(PreferenceKey.captureShowsCursor) private var showsCursor = false
    @AppStorage(PreferenceKey.windowShadow) private var windowShadow = true
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
    @AppStorage(PreferenceKey.quickAccessPosition) private var position = QuickAccessPosition.left.rawValue
    @AppStorage(PreferenceKey.quickAccessDuration) private var duration = 8.0
    private let color = SettingsSection.quickAccess.color

    var body: some View {
        SettingsCard(title: "Placement", symbol: "rectangle.bottomhalf.inset.filled") {
            SettingRow(title: "Screen corner") {
                BrutalSegmented(selection: $position, options: [(QuickAccessPosition.left.rawValue, "Bottom left"), (QuickAccessPosition.right.rawValue, "Bottom right")], color: color)
            }
            SettingRow(title: "Auto-close", subtitle: "Hovering a card pauses the timer.", divider: false) {
                BrutalSegmented(selection: $duration, options: [(4.0, "4s"), (8.0, "8s"), (15.0, "15s"), (30.0, "30s"), (0.0, "Never")], color: color)
            }
        }
        ScreenPreview(position: QuickAccessPosition(rawValue: position) ?? .left, color: color)
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
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(index == 1 ? color : Color.white)
                        .frame(width: 72, height: 42)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Brutal.ink, lineWidth: 2))
                }
            }
            .padding(12)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: Brutal.radius, style: .continuous))
        .brutalSurface(Color.clear)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: position)
    }
}

// MARK: Recording

private struct RecordingSettings: View {
    @AppStorage(PreferenceKey.recordingFPS) private var fps = 60
    @AppStorage(PreferenceKey.recordShowsCursor) private var showsCursor = true
    @AppStorage(PreferenceKey.showRecordingBorder) private var border = true
    @AppStorage(PreferenceKey.recordMicrophone) private var microphone = false
    @AppStorage(PreferenceKey.recordSystemAudio) private var systemAudio = false
    private let color = SettingsSection.recording.color

    var body: some View {
        SettingsCard(title: "Video", symbol: "film.fill") {
            SettingRow(title: "Frame rate", subtitle: "H.264 MP4.") {
                BrutalSegmented(selection: $fps, options: [(30, "30 fps"), (60, "60 fps")], color: color)
            }
            ToggleRow(title: "Show cursor", isOn: $showsCursor, color: color)
            ToggleRow(title: "Region border", subtitle: "Red outline around the recorded area. It never appears in the video.", isOn: $border, color: color, divider: false)
        }
        SettingsCard(title: "Audio", symbol: "waveform") {
            ToggleRow(title: "Microphone", subtitle: "macOS asks for permission on first use.", isOn: $microphone, color: color)
            ToggleRow(title: "System audio", subtitle: "Sound from other apps. Shot's own sounds are excluded.", isOn: $systemAudio, color: color, divider: false)
        }
        CameraSettings(color: color)
        SettingsCard(title: "GIF export", symbol: "photo.stack.fill") {
            SettingRow(title: "From the Quick Access card", subtitle: "12 fps, up to 720 px wide, first 60 seconds.", divider: false) {
                BrutalChip(text: "GIF", color: color)
            }
        }
    }
}

private struct CameraSettings: View {
    let color: Color
    @AppStorage(PreferenceKey.recordCamera) private var camera = false
    @AppStorage(PreferenceKey.cameraDeviceID) private var deviceID = ""
    @AppStorage(PreferenceKey.cameraSize) private var size = CameraBubbleSize.medium.rawValue
    @State private var devices: [(id: String, name: String)] = []

    var body: some View {
        SettingsCard(title: "Camera", symbol: "web.camera.fill") {
            ToggleRow(title: "Camera bubble", subtitle: "Round webcam overlay recorded with your screen. Drag to move, double-click to resize.", isOn: $camera, color: color)
            SettingRow(title: "Camera") {
                Menu {
                    Button("System default") { deviceID = "" }
                    Divider()
                    ForEach(devices, id: \.id) { device in
                        Button(device.name) { deviceID = device.id }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedName).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .black))
                    }
                    .frame(maxWidth: 190)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(BrutalButtonStyle(compact: true))
                .fixedSize()
            }
            SettingRow(title: "Bubble size", divider: false) {
                BrutalSegmented(selection: $size, options: CameraBubbleSize.allCases.map { ($0.rawValue, $0.rawValue.capitalized) }, color: color)
            }
        }
        .onAppear {
            devices = CameraBubble.cameras().map { ($0.uniqueID, $0.localizedName) }
        }
    }

    private var selectedName: String {
        devices.first { $0.id == deviceID }?.name ?? "System default"
    }
}

// MARK: Shortcuts

private struct ShortcutSettings: View {
    private let color = SettingsSection.shortcuts.color

    var body: some View {
        SettingsCard(title: "Global hotkeys", symbol: "keyboard.fill") {
            ForEach(Array(ShotAction.allCases.enumerated()), id: \.element) { index, action in
                SettingRow(title: action.title, divider: index < ShotAction.allCases.count - 1) {
                    ShortcutRecorderView(action: action, color: color)
                }
            }
        }
        HStack(alignment: .top, spacing: 14) {
            Text("Click a shortcut, then press the new keys. Esc cancels, Delete clears. macOS keeps ⌘⇧3, ⌘⇧4 and ⌘⇧5 for its own screenshot tool.")
                .font(Brutal.caption)
                .foregroundStyle(Brutal.ink.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Restore defaults") { Preferences.resetHotkeys() }
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
    private let color = SettingsSection.about.color

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(Brutal.ink)
                .frame(width: 64, height: 64)
                .brutalSurface(Brutal.yellow, radius: 14, shadow: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text("Shot").font(Brutal.title(26)).foregroundStyle(Brutal.ink)
                Text("Screenshots and screen recordings for macOS.")
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Brutal.ink.opacity(0.65))
            }
            Spacer()
            BrutalChip(text: "v\(version)", color: color)
        }
        .padding(16)
        .glassCard()

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
                        confirmingReset = false
                        Toast.show("Settings reset")
                    } else {
                        confirmingReset = true
                    }
                }
                .buttonStyle(BrutalButtonStyle(color: confirmingReset ? Brutal.red : .white, compact: true))
            }
        }
    }

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
