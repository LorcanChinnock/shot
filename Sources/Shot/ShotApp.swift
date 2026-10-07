import ShotCore
import SwiftUI

@main
struct ShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var menuBarState: BrandMark.State {
        if appDelegate.state.isPaused {
            return .paused
        }
        return appDelegate.state.isRecording ? .recording : .idle
    }

    var body: some Scene {
        MenuBarExtra {
            ShotMenu(state: appDelegate.state, coordinator: appDelegate.coordinator)
        } label: {
            Image(nsImage: BrandMark.menuBarImage(menuBarState))
        }
    }
}

private struct ShotMenu: View {
    let state: AppState
    let coordinator: CaptureCoordinator
    @Setting(PreferenceKey.recordCamera) private var cameraBubble = false

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
        Button("Open Gallery") { GalleryController.shared.show() }
        Button("Open Capture Folder") {
            let folder = Preferences().saveFolder
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
        UpdateButton(updater: Updater.shared)
        Button("Settings…") { MainWindowController.showSettings() }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Shot") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct UpdateButton: View {
    let updater: Updater

    var body: some View {
        if let version = updater.pendingVersion {
            Button("Update to Shot \(version)…") { updater.checkForUpdates() }
        } else {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}

private struct ActionButton: View {
    let action: ShotAction
    let title: String
    let coordinator: CaptureCoordinator
    @Setting private var encodedCombo: String

    init(action: ShotAction, title: String, coordinator: CaptureCoordinator) {
        self.action = action
        self.title = title
        self.coordinator = coordinator
        _encodedCombo = Setting(wrappedValue: action.defaultCombo(replacingSystemScreenshots: Preferences().replacesSystemScreenshots)?.encoded ?? "", PreferenceKey.hotkey(action))
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
