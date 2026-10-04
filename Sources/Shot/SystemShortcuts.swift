import AppKit
import os
import ShotCore

private let log = Logger.shot("system-shortcuts")

/// Hands ⌘⇧3 to ⌘⇧6 between macOS and Shot.
@MainActor
enum SystemShortcuts {
    private static var hotkeys: [String: Any] {
        UserDefaults(suiteName: SystemScreenshotShortcut.domain)?.dictionary(forKey: SystemScreenshotShortcut.key) ?? [:]
    }

    /// True while macOS still answers any of its screenshot shortcuts.
    static var macOSOwnsKeys: Bool { SystemScreenshotShortcut.anyEnabled(in: hotkeys) }

    /// Moves the screenshot keys to Shot, or gives them back to macOS.
    static func useShot(_ on: Bool) {
        let store = UserDefaults.standard
        store.set(on, forKey: PreferenceKey.replacesSystemScreenshots)
        Preferences.registerDefaults()
        HotkeyCenter.shared.reloadFromPreferences(force: true)
        if on, macOSOwnsKeys {
            store.set(setMacOSShortcuts(enabled: false), forKey: PreferenceKey.disabledSystemScreenshots)
        } else if !on, Preferences().disabledSystemScreenshots {
            // Only undo what Shot did; shortcuts the user turned off themselves stay off.
            if setMacOSShortcuts(enabled: true) {
                store.set(false, forKey: PreferenceKey.disabledSystemScreenshots)
            }
        }
    }

    static func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }

    /// Takes the keys once Screen Recording access is in place. Only once, so turning the macOS
    /// shortcuts back on in System Settings sticks.
    static func takeKeysIfNeeded() {
        let prefs = Preferences()
        guard !prefs.tookSystemScreenshots, prefs.replacesSystemScreenshots else {
            return
        }
        UserDefaults.standard.set(true, forKey: PreferenceKey.tookSystemScreenshots)
        useShot(true)
    }

    /// Returns true when macOS reports the new state after the change.
    private static func setMacOSShortcuts(enabled: Bool) -> Bool {
        guard let domain = UserDefaults(suiteName: SystemScreenshotShortcut.domain) else {
            return false
        }
        domain.set(SystemScreenshotShortcut.setting(enabled: enabled, in: hotkeys), forKey: SystemScreenshotShortcut.key)
        // Without this, macOS only picks up the change at the next login.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        process.arguments = ["-u"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.error("activateSettings failed: \(error.localizedDescription, privacy: .public)")
        }
        let applied = macOSOwnsKeys == enabled
        if !applied {
            log.error("macOS screenshot shortcuts did not turn \(enabled ? "on" : "off", privacy: .public)")
            Toast.show("Couldn't change the macOS screenshot shortcuts. Change them in Keyboard Shortcuts.", duration: .seconds(4))
        }
        return applied
    }
}
