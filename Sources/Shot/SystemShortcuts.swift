import AppKit
import os
import ShotCore

private let log = Logger.shot("system-shortcuts")

/// Hands ⌘⇧3 to ⌘⇧5 between macOS and Shot.
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

    /// Turns ⌘⇧6 back on for people whose takeover included it for text capture. Only once, and
    /// only when Shot turned it off, so a choice made in System Settings sticks.
    static func giveBackTextCaptureKeyIfNeeded() {
        let store = UserDefaults.standard
        Preferences.removeTextCapture(in: store)
        let prefs = Preferences()
        guard !prefs.gaveBackTextCaptureKey else {
            return
        }
        if prefs.disabledSystemScreenshots, let updated = SystemScreenshotShortcut.givingBackTextCaptureKey(in: hotkeys) {
            apply(updated)
            guard SystemScreenshotShortcut.givingBackTextCaptureKey(in: hotkeys) == nil else {
                log.error("macOS did not turn ⌘⇧6 back on")
                return
            }
        }
        store.set(true, forKey: PreferenceKey.gaveBackTextCaptureKey)
    }

    /// Returns true when macOS reports the new state after the change.
    private static func setMacOSShortcuts(enabled: Bool) -> Bool {
        guard apply(SystemScreenshotShortcut.setting(enabled: enabled, in: hotkeys)) else {
            return false
        }
        let applied = macOSOwnsKeys == enabled
        if !applied {
            log.error("macOS screenshot shortcuts did not turn \(enabled ? "on" : "off", privacy: .public)")
            Toast.show("Couldn't change the macOS screenshot shortcuts. Change them in Keyboard Shortcuts.", duration: .seconds(4))
        }
        return applied
    }

    /// Saves `hotkeys` and has macOS pick them up now. Returns false when the domain can't be opened.
    @discardableResult
    private static func apply(_ hotkeys: [String: Any]) -> Bool {
        guard let domain = UserDefaults(suiteName: SystemScreenshotShortcut.domain) else {
            return false
        }
        domain.set(hotkeys, forKey: SystemScreenshotShortcut.key)
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
        return true
    }
}
