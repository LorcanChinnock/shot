import ShotCore
import SwiftUI

@main
struct ShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var menuBarSymbol: String {
        if appDelegate.state.isPaused {
            return "pause.circle.fill"
        }
        return appDelegate.state.isRecording ? "stop.circle.fill" : "camera.viewfinder"
    }

    var body: some Scene {
        MenuBarExtra("Shot", systemImage: menuBarSymbol) {
            ShotMenu(state: appDelegate.state, coordinator: appDelegate.coordinator)
        }
    }
}

private struct ShotMenu: View {
    let state: AppState
    let coordinator: CaptureCoordinator
    @AppStorage(PreferenceKey.recordCamera) private var cameraBubble = false

    var body: some View {
        if state.isRecording {
            ActionButton(action: .record, title: "Stop Recording", coordinator: coordinator)
            Button(state.isPaused ? "Resume Recording" : "Pause Recording") { coordinator.togglePause() }
            Divider()
        }
        Section("Capture") {
            ForEach(ShotAction.allCases.filter { !$0.isRecording }, id: \.self) { action in
                ActionButton(action: action, title: action.title, coordinator: coordinator)
            }
        }
        if !state.isRecording {
            Section("Record") {
                ForEach(ShotAction.allCases.filter(\.isRecording), id: \.self) { action in
                    ActionButton(action: action, title: action.title, coordinator: coordinator)
                }
            }
        }
        Toggle("Camera Bubble", isOn: $cameraBubble)
        Divider()
        Button("Open Capture Folder") {
            let folder = Preferences().saveFolder
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
        Button("Settings…") { SettingsWindowController.show() }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Shot") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct ActionButton: View {
    let action: ShotAction
    let title: String
    let coordinator: CaptureCoordinator
    @AppStorage private var encodedCombo: String

    init(action: ShotAction, title: String, coordinator: CaptureCoordinator) {
        self.action = action
        self.title = title
        self.coordinator = coordinator
        _encodedCombo = AppStorage(wrappedValue: action.defaultCombo.encoded, PreferenceKey.hotkey(action))
    }

    var body: some View {
        Button(title) { coordinator.perform(action) }
            .keyboardShortcut(KeyCombo(encoded: encodedCombo).flatMap(\.swiftUIShortcut))
    }
}

extension KeyCombo {
    var swiftUIShortcut: KeyboardShortcut? {
        let key: KeyEquivalent
        if keyLabel == "Space" {
            key = .space
        } else if keyLabel.count == 1, let character = keyLabel.lowercased().first {
            key = KeyEquivalent(character)
        } else {
            return nil
        }
        var mods: EventModifiers = []
        if modifiers & KeyCombo.command != 0 { mods.insert(.command) }
        if modifiers & KeyCombo.shift != 0 { mods.insert(.shift) }
        if modifiers & KeyCombo.option != 0 { mods.insert(.option) }
        if modifiers & KeyCombo.control != 0 { mods.insert(.control) }
        return KeyboardShortcut(key, modifiers: mods)
    }
}
