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
    #expect(ShotAction.screenshot.defaultCombo?.displayString == "⌃⇧4")
    #expect(ShotAction.record.defaultCombo?.displayString == "⌃⇧5")
    let defaults = ShotAction.allCases.compactMap(\.defaultCombo)
    #expect(Set(defaults).count == defaults.count)
    // Two modifiers at most, and never ⌘, so no default can hit the macOS screenshot keys.
    for combo in defaults {
        #expect(combo.modifiers.nonzeroBitCount <= 2, "\(combo.displayString)")
        #expect(combo.modifiers & KeyCombo.command == 0, "\(combo.displayString)")
    }
    #expect(ShotAction.allCases.filter(\.isRecording) == [.record])
}

@Test func replacementHotkeysTakeTheMacOSKeys() {
    let replaced = ShotAction.allCases.map { $0.defaultCombo(replacingSystemScreenshots: true)?.displayString }
    #expect(replaced == ["⇧⌘4", "⇧⌘5", nil, nil, nil, nil])
    #expect(ShotAction.allCases.allSatisfy { $0.defaultCombo(replacingSystemScreenshots: false) == $0.defaultCombo })
}

@Test func theToolsHaveNoShortcutAndAreNotRecordings() {
    for action in [ShotAction.pickColor, .copyPath, .copyText] {
        #expect(action.defaultCombo == nil)
        #expect(action.defaultCombo(replacingSystemScreenshots: true) == nil)
        #expect(!action.isRecording)
    }
    #expect(ShotAction.pickColor.rawValue == "pick-color")
    #expect(ShotAction.copyPath.rawValue == "copy-path")
    #expect(ShotAction.copyText.rawValue == "copy-text")
    // HotkeyCenter numbers hotkeys by position, so a new action goes last and existing ones keep their ids.
    #expect(ShotAction.allCases.firstIndex(of: .pickColor) == 2)
    #expect(ShotAction.allCases.firstIndex(of: .copyPath) == 3)
    #expect(ShotAction.allCases.firstIndex(of: .copyText) == 4)
}

@Test func tabStepsThroughTheTargetsAndWraps() {
    #expect(CaptureTarget.area.next() == .window)
    #expect(CaptureTarget.window.next() == .screen)
    #expect(CaptureTarget.screen.next() == .area)
    #expect(CaptureTarget.area.next(backward: true) == .screen)
    #expect(CaptureTarget.screen.next(backward: true) == .window)
}

@Test func theDelayStepsFromOffThroughTheChoicesAndBackToOff() {
    #expect(CaptureDelay.choices == [0, 3, 5, 10])
    #expect(CaptureDelay.next(after: 0) == 3)
    #expect(CaptureDelay.next(after: 10) == 0)
    #expect(CaptureDelay.next(after: 7) == 3)
}
