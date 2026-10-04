import Foundation

/// The macOS screenshot shortcuts Shot can take over, keyed by their ID in `com.apple.symbolichotkeys`.
public enum SystemScreenshotShortcut: Int, CaseIterable, Sendable {
    case saveScreen = 28
    case saveArea = 30
    case options = 184
    /// ⌘⇧6, which Shot uses for text capture.
    case saveTouchBar = 181

    public static let domain = "com.apple.symbolichotkeys"
    public static let key = "AppleSymbolicHotKeys"

    /// Character, virtual key code and Cocoa modifier flags (⌘⇧) of the macOS default.
    var defaultParameters: [Int] {
        let commandShift = 0x10_0000 | 0x2_0000
        switch self {
        case .saveScreen: return [51, 20, commandShift]
        case .saveArea: return [52, 21, commandShift]
        case .options: return [53, 23, commandShift]
        case .saveTouchBar: return [54, 22, commandShift]
        }
    }

    /// A missing entry means macOS uses its built-in default, which is on.
    public func isEnabled(in hotkeys: [String: Any]) -> Bool {
        guard let entry = hotkeys[String(rawValue)] as? [String: Any] else {
            return true
        }
        return entry["enabled"] as? Bool ?? true
    }

    /// True when any of the shortcuts still belongs to macOS.
    public static func anyEnabled(in hotkeys: [String: Any]) -> Bool {
        allCases.contains { $0.isEnabled(in: hotkeys) }
    }

    /// Returns `hotkeys` with every screenshot shortcut turned on or off. A key the user picked in
    /// System Settings is kept, so turning a shortcut back on restores it as it was.
    public static func setting(enabled: Bool, in hotkeys: [String: Any]) -> [String: Any] {
        var result = hotkeys
        for shortcut in allCases {
            let id = String(shortcut.rawValue)
            var entry = hotkeys[id] as? [String: Any] ?? [:]
            if entry["value"] == nil {
                entry["value"] = ["parameters": shortcut.defaultParameters, "type": "standard"] as [String: Any]
            }
            entry["enabled"] = enabled
            result[id] = entry
        }
        return result
    }
}
