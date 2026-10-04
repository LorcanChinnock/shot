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
