import Testing
@testable import ShotCore

@Test func missingEntriesCountAsEnabled() {
    #expect(SystemScreenshotShortcut.anyEnabled(in: [:]))
    #expect(SystemScreenshotShortcut.saveArea.isEnabled(in: ["30": ["enabled": true]]))
}

@Test func disablingWritesEveryShortcutWithMacOSDefaults() {
    let other: [String: Any] = ["enabled": true, "value": ["parameters": [65535, 49, 262_144], "type": "standard"]]
    let hotkeys = SystemScreenshotShortcut.setting(enabled: false, in: ["60": other])
    #expect(!SystemScreenshotShortcut.anyEnabled(in: hotkeys))
    #expect((hotkeys["60"] as? [String: Any])?["enabled"] as? Bool == true)
    let area = hotkeys["30"] as? [String: Any]
    let value = area?["value"] as? [String: Any]
    #expect(value?["parameters"] as? [Int] == [52, 21, 1_179_648])
    #expect(value?["type"] as? String == "standard")
}

@Test func reenablingKeepsAKeyTheUserPicked() {
    let custom: [String: Any] = ["enabled": false, "value": ["parameters": [56, 28, 1_179_648], "type": "standard"]]
    let hotkeys = SystemScreenshotShortcut.setting(enabled: true, in: ["30": custom])
    let area = hotkeys["30"] as? [String: Any]
    #expect(area?["enabled"] as? Bool == true)
    #expect((area?["value"] as? [String: Any])?["parameters"] as? [Int] == [56, 28, 1_179_648])
    #expect(SystemScreenshotShortcut.allCases.allSatisfy { $0.isEnabled(in: hotkeys) })
}

@Test func takeoverLeavesCommandShift6WithMacOS() {
    #expect(SystemScreenshotShortcut.allCases.map(\.rawValue) == [28, 30, 184])
    let hotkeys = SystemScreenshotShortcut.setting(enabled: false, in: [:])
    #expect(hotkeys["181"] == nil)
}

@Test func givingBackCommandShift6TurnsItOnAndKeepsItsKey() {
    let taken: [String: Any] = ["enabled": false, "value": ["parameters": [54, 22, 1_179_648], "type": "standard"]]
    let other: [String: Any] = ["enabled": false]
    let hotkeys = SystemScreenshotShortcut.givingBackTextCaptureKey(in: ["181": taken, "30": other])
    let entry = hotkeys?["181"] as? [String: Any]
    #expect(entry?["enabled"] as? Bool == true)
    #expect((entry?["value"] as? [String: Any])?["parameters"] as? [Int] == [54, 22, 1_179_648])
    #expect((hotkeys?["30"] as? [String: Any])?["enabled"] as? Bool == false)
    // Nothing to give back when macOS already has it.
    #expect(SystemScreenshotShortcut.givingBackTextCaptureKey(in: [:]) == nil)
    #expect(SystemScreenshotShortcut.givingBackTextCaptureKey(in: ["181": ["enabled": true]]) == nil)
}
