import ServiceManagement
import ShotCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            RecordingSettings()
                .tabItem { Label("Recording", systemImage: "record.circle") }
        }
        .frame(width: 480)
        .padding(20)
    }
}

private struct GeneralSettings: View {
    @AppStorage(PreferenceKey.saveFolder) private var saveFolder = Preferences.defaultSaveFolder
    @AppStorage(PreferenceKey.saveAfterCapture) private var save = true
    @AppStorage(PreferenceKey.copyAfterCapture) private var copy = true
    @AppStorage(PreferenceKey.quickAccessAfterCapture) private var quickAccess = true
    @AppStorage(PreferenceKey.quickAccessDuration) private var quickAccessDuration = 8.0
    @AppStorage(PreferenceKey.windowShadow) private var windowShadow = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            LabeledContent("Save folder") {
                HStack {
                    Text((saveFolder as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…", action: chooseFolder)
                }
            }
            Section("After capture") {
                Toggle("Save to folder", isOn: $save)
                Toggle("Copy to clipboard", isOn: $copy)
                Toggle("Show Quick Access", isOn: $quickAccess)
                Picker("Close Quick Access after", selection: $quickAccessDuration) {
                    Text("4 seconds").tag(4.0)
                    Text("8 seconds").tag(8.0)
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                    Text("Never").tag(0.0)
                }
            }
            Toggle("Include window shadow", isOn: $windowShadow)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
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
            Toast.show("Launch at login failed: \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        Form {
            ForEach(ShotAction.allCases, id: \.self) { action in
                LabeledContent(action.title) {
                    ShortcutRecorderView(action: action)
                }
            }
            Text("Click a shortcut, then type a new one. Esc cancels. Delete clears.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RecordingSettings: View {
    @AppStorage(PreferenceKey.recordingFPS) private var fps = 60
    @AppStorage(PreferenceKey.recordMicrophone) private var microphone = false
    @AppStorage(PreferenceKey.recordShowsCursor) private var showsCursor = true

    var body: some View {
        Form {
            Picker("Frame rate", selection: $fps) {
                Text("30 fps").tag(30)
                Text("60 fps").tag(60)
            }
            Toggle("Record microphone", isOn: $microphone)
            Toggle("Show cursor", isOn: $showsCursor)
        }
    }
}
