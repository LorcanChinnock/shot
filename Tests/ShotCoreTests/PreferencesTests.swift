import Foundation
import Testing
@testable import ShotCore

@Test func hotkeyEncodeDecodeRoundTrip() {
    for combo in ShotAction.allCases.compactMap(\.defaultCombo) {
        #expect(KeyCombo(encoded: combo.encoded) == combo)
    }
    let custom = KeyCombo(keyCode: 122, modifiers: KeyCombo.control | KeyCombo.option)
    #expect(KeyCombo(encoded: custom.encoded) == custom)
    #expect(custom.displayString == "⌃⌥F1")
    #expect(KeyCombo(encoded: "") == nil)
    #expect(KeyCombo(encoded: "x:1") == nil)
}

@Test func defaultHotkeysMatchPlan() {
    #expect(ShotAction.captureArea.defaultCombo?.displayString == "⌃⇧4")
    #expect(ShotAction.captureFullscreen.defaultCombo?.displayString == "⌃⇧3")
    #expect(ShotAction.captureWindow.defaultCombo?.displayString == "⌃⇧W")
    #expect(ShotAction.record.defaultCombo?.displayString == "⌃⇧5")
    #expect(ShotAction.recordFullscreen.defaultCombo == nil)
    #expect(ShotAction.recordWindow.defaultCombo == nil)
    let defaults = ShotAction.allCases.compactMap(\.defaultCombo)
    #expect(Set(defaults).count == defaults.count)
    // Two modifiers at most, and never ⌘, so no default can hit the macOS screenshot keys.
    for combo in defaults {
        #expect(combo.modifiers == KeyCombo.control | KeyCombo.shift)
    }
    #expect(ShotAction.allCases.filter(\.isRecording) == [.record, .recordFullscreen, .recordWindow])
}

@Test func replacementHotkeysTakeTheMacOSKeys() {
    let replaced = ShotAction.allCases.map { $0.defaultCombo(replacingSystemScreenshots: true)?.displayString }
    #expect(replaced == ["⇧⌘4", "⇧⌘3", nil, "⇧⌘5", nil, nil])
    #expect(ShotAction.allCases.allSatisfy { $0.defaultCombo(replacingSystemScreenshots: false) == $0.defaultCombo })
}

/// Registered defaults are shared by the whole process, so tests that register them run one at a time.
@Suite(.serialized) struct RegisteredDefaultsTests {
    @Test func registeringDefaultsFollowsReplacementButKeepsCustomShortcuts() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        #expect(prefs.hotkey(for: .record)?.displayString == "⇧⌘5")
        let custom = KeyCombo(keyCode: 122, modifiers: KeyCombo.control | KeyCombo.option)
        store.set(custom.encoded, forKey: PreferenceKey.hotkey(.captureFullscreen))
        store.set(false, forKey: PreferenceKey.replacesSystemScreenshots)
        Preferences.registerDefaults(in: store)
        #expect(prefs.hotkey(for: .captureArea)?.displayString == "⌃⇧4")
        #expect(prefs.hotkey(for: .captureFullscreen) == custom)
        store.set(true, forKey: PreferenceKey.replacesSystemScreenshots)
        Preferences.registerDefaults(in: store)
        #expect(prefs.hotkey(for: .captureArea)?.displayString == "⇧⌘4")
        #expect(prefs.hotkey(for: .captureFullscreen) == custom)
    }

    @Test func preferenceDefaults() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        #expect(prefs.saveFolder.path.hasSuffix("/Pictures/Shot"))
        #expect(prefs.playSound)
        #expect(prefs.filePrefix == "Shot")
        #expect(prefs.imageFormat == .png)
        #expect(!prefs.downscaleRetina)
        #expect(!prefs.openEditorAfterCapture)
        #expect(!prefs.captureShowsCursor)
        #expect(prefs.hidesShotUI)
        #expect(prefs.showMagnifier)
        #expect(prefs.showCrosshair)
        #expect(prefs.quickAccessPosition == .left)
        #expect(!prefs.recordSystemAudio)
        #expect(prefs.showRecordingBorder)
        #expect(!prefs.recordCamera)
        #expect(prefs.cameraDeviceID.isEmpty)
        #expect(prefs.cameraSize == .medium)
        #expect(prefs.saveAfterCapture)
        #expect(prefs.copyAfterCapture)
        #expect(prefs.quickAccessAfterCapture)
        #expect(prefs.quickAccessDuration == 8)
        #expect(prefs.windowShadow)
        #expect(prefs.recordingFPS == 60)
        #expect(!prefs.recordMicrophone)
        #expect(prefs.recordShowsCursor)
        #expect(prefs.replacesSystemScreenshots)
        #expect(prefs.hotkey(for: .captureArea)?.displayString == "⇧⌘4")
        store.set("", forKey: PreferenceKey.hotkey(.record))
        #expect(prefs.hotkey(for: .record) == nil)
    }

    @Test func resetAndPrefixSanitizing() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        let prefs = Preferences(store: store)
        store.set("  ", forKey: PreferenceKey.filePrefix)
        #expect(prefs.filePrefix == "Shot")
        store.set("a/b", forKey: PreferenceKey.filePrefix)
        #expect(prefs.filePrefix == "a-b")
        store.set("", forKey: PreferenceKey.hotkey(.captureArea))
        store.set(false, forKey: PreferenceKey.playSound)
        Preferences.resetHotkeys(in: store)
        #expect(prefs.hotkey(for: .captureArea)?.displayString == "⇧⌘4")
        #expect(!prefs.playSound)
        store.set(true, forKey: PreferenceKey.disabledSystemScreenshots)
        Preferences.resetAll(in: store)
        #expect(prefs.playSound)
        #expect(prefs.disabledSystemScreenshots)
        #expect(prefs.filePrefix == "Shot")
    }

    @Test func removingTextCaptureDeletesItsShortcut() throws {
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        Preferences.registerDefaults(in: store)
        store.set("17:4608", forKey: "hotkey.capture-text")
        store.set("", forKey: PreferenceKey.hotkey(.record))
        Preferences.removeTextCapture(in: store)
        #expect(store.object(forKey: "hotkey.capture-text") == nil)
        #expect(store.string(forKey: PreferenceKey.hotkey(.record)) == "")
        #expect(ShotAction(rawValue: "capture-text") == nil)
    }
}
