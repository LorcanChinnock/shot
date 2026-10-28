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
        #expect(combo.modifiers.nonzeroBitCount <= 2, "\(combo.displayString)")
        #expect(combo.modifiers & KeyCombo.command == 0, "\(combo.displayString)")
    }
    #expect(ShotAction.allCases.filter(\.isRecording) == [.record, .recordFullscreen, .recordWindow])
}

@Test func replacementHotkeysTakeTheMacOSKeys() {
    let replaced = ShotAction.allCases.map { $0.defaultCombo(replacingSystemScreenshots: true)?.displayString }
    #expect(replaced == ["⇧⌘4", "⇧⌘3", nil, "⇧⌘5", nil, nil, nil, nil, nil, nil, nil])
    #expect(ShotAction.allCases.allSatisfy { $0.defaultCombo(replacingSystemScreenshots: false) == $0.defaultCombo })
}

@Test func pickColourHasNoShortcutAndIsNeitherACaptureNorARecording() {
    #expect(ShotAction.pickColor.defaultCombo == nil)
    #expect(ShotAction.pickColor.defaultCombo(replacingSystemScreenshots: true) == nil)
    #expect(!ShotAction.pickColor.isCapture)
    #expect(!ShotAction.pickColor.isRecording)
    #expect(ShotAction.pickColor.rawValue == "pick-color")
    // HotkeyCenter numbers hotkeys by position, so a new action goes last and existing ones keep their ids.
    #expect(ShotAction.allCases.firstIndex(of: .pickColor) == 6)
    #expect(ShotAction.allCases.filter(\.isCapture) == [.captureArea, .captureFullscreen, .captureWindow, .capturePrevious, .captureScrolling])
}

@Test func copyPathHasNoShortcutAndComesLast() {
    #expect(ShotAction.copyPath.defaultCombo == nil)
    #expect(ShotAction.copyPath.defaultCombo(replacingSystemScreenshots: true) == nil)
    #expect(!ShotAction.copyPath.isCapture)
    #expect(!ShotAction.copyPath.isRecording)
    #expect(ShotAction.copyPath.rawValue == "copy-path")
    #expect(ShotAction.allCases.firstIndex(of: .copyPath) == 7)
}

@Test func capturePreviousAreaIsACaptureWithNoShortcut() {
    #expect(ShotAction.capturePrevious.defaultCombo == nil)
    #expect(ShotAction.capturePrevious.defaultCombo(replacingSystemScreenshots: true) == nil)
    #expect(ShotAction.capturePrevious.isCapture)
    #expect(!ShotAction.capturePrevious.isRecording)
    #expect(ShotAction.capturePrevious.rawValue == "capture-previous")
    #expect(ShotAction.allCases.firstIndex(of: .capturePrevious) == 8)
}

@Test func copyTextHasNoShortcut() {
    #expect(ShotAction.copyText.defaultCombo == nil)
    #expect(ShotAction.copyText.defaultCombo(replacingSystemScreenshots: true) == nil)
    // It saves no capture, so it stays out of the menu's Capture section and the capture path.
    #expect(!ShotAction.copyText.isCapture)
    #expect(!ShotAction.copyText.isRecording)
    #expect(ShotAction.copyText.rawValue == "copy-text")
    #expect(ShotAction.allCases.firstIndex(of: .copyText) == 9)
}

@Test func captureScrollingHasNoShortcutAndIsACapture() {
    #expect(ShotAction.captureScrolling.defaultCombo == nil)
    #expect(ShotAction.captureScrolling.defaultCombo(replacingSystemScreenshots: true) == nil)
    #expect(ShotAction.captureScrolling.hasShortcut)
    #expect(ShotAction.captureScrolling.isCapture)
    #expect(!ShotAction.captureScrolling.isRecording)
    #expect(ShotAction.captureScrolling.rawValue == "capture-scrolling")
    #expect(ShotAction.allCases.firstIndex(of: .captureScrolling) == 10)
}
