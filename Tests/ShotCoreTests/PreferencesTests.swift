import Foundation
import Testing
@testable import ShotCore

@Test func hotkeyEncodeDecodeRoundTrip() {
    for action in ShotAction.allCases {
        let combo = action.defaultCombo
        #expect(KeyCombo(encoded: combo.encoded) == combo)
    }
    let custom = KeyCombo(keyCode: 122, modifiers: KeyCombo.control | KeyCombo.option)
    #expect(KeyCombo(encoded: custom.encoded) == custom)
    #expect(custom.displayString == "⌃⌥F1")
    #expect(KeyCombo(encoded: "") == nil)
    #expect(KeyCombo(encoded: "x:1") == nil)
}

@Test func defaultHotkeysMatchPlan() {
    #expect(ShotAction.captureArea.defaultCombo.displayString == "⌃⇧4")
    #expect(ShotAction.captureFullscreen.defaultCombo.displayString == "⌃⇧3")
    #expect(ShotAction.captureWindow.defaultCombo.displayString == "⌃⇧W")
    #expect(ShotAction.captureText.defaultCombo.displayString == "⌃⇧2")
    #expect(ShotAction.record.defaultCombo.displayString == "⌃⌥⇧4")
    #expect(ShotAction.recordFullscreen.defaultCombo.displayString == "⌃⌥⇧3")
    #expect(ShotAction.recordWindow.defaultCombo.displayString == "⌃⌥⇧W")
    #expect(Set(ShotAction.allCases.map(\.defaultCombo)).count == ShotAction.allCases.count)
    #expect(ShotAction.allCases.filter(\.isRecording) == [.record, .recordFullscreen, .recordWindow])
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
    #expect(prefs.hotkey(for: .captureArea) == ShotAction.captureArea.defaultCombo)
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
    #expect(prefs.hotkey(for: .captureArea) == ShotAction.captureArea.defaultCombo)
    #expect(!prefs.playSound)
    Preferences.resetAll(in: store)
    #expect(prefs.playSound)
    #expect(prefs.filePrefix == "Shot")
}
