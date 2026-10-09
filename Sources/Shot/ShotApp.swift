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
    /// Keys whose label isn't the character they type.
    private static let specialKeys: [UInt32: KeyEquivalent] = [
        49: .space, 36: .return, 48: .tab, 53: .escape, 51: .delete, 117: .deleteForward,
        123: .leftArrow, 124: .rightArrow, 125: .downArrow, 126: .upArrow, 115: .home, 119: .end, 116: .pageUp, 121: .pageDown,
    ]

    var swiftUIShortcut: KeyboardShortcut? {
        let key: KeyEquivalent
        if let special = Self.specialKeys[keyCode] {
            key = special
        } else if keyLabel.count == 1, let character = keyLabel.lowercased().first {
            key = KeyEquivalent(character)
        } else {
            return nil
        }
        let flags = eventFlags
        var mods: EventModifiers = []
        if flags.contains(.maskCommand) { mods.insert(.command) }
        if flags.contains(.maskShift) { mods.insert(.shift) }
        if flags.contains(.maskAlternate) { mods.insert(.option) }
        if flags.contains(.maskControl) { mods.insert(.control) }
        return KeyboardShortcut(key, modifiers: mods)
    }
}
