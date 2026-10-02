import Foundation

public enum ShotAction: String, CaseIterable, Sendable {
    case captureArea = "capture-area"
    case captureFullscreen = "capture-fullscreen"
    case captureWindow = "capture-window"
    case captureText = "capture-text"
    case record

    public var title: String {
        switch self {
        case .captureArea: "Capture Area"
        case .captureFullscreen: "Capture Fullscreen"
        case .captureWindow: "Capture Window"
        case .captureText: "Capture Text"
        case .record: "Record Screen"
        }
    }

    public var defaultCombo: KeyCombo {
        switch self {
        case .captureArea: KeyCombo(keyCode: 21, modifiers: KeyCombo.control | KeyCombo.shift)
        case .captureFullscreen: KeyCombo(keyCode: 20, modifiers: KeyCombo.control | KeyCombo.shift)
        case .captureWindow: KeyCombo(keyCode: 13, modifiers: KeyCombo.control | KeyCombo.shift)
        case .captureText: KeyCombo(keyCode: 19, modifiers: KeyCombo.control | KeyCombo.shift)
        case .record: KeyCombo(keyCode: 23, modifiers: KeyCombo.control | KeyCombo.shift)
        }
    }
}

/// A key code plus Carbon modifier mask, as used by `RegisterEventHotKey`.
public struct KeyCombo: Equatable, Hashable, Sendable {
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var encoded: String { "\(keyCode):\(modifiers)" }

    public init?(encoded: String) {
        let parts = encoded.split(separator: ":")
        guard parts.count == 2, let code = UInt32(parts[0]), let mods = UInt32(parts[1]) else {
            return nil
        }
        self.init(keyCode: code, modifiers: mods)
    }

    public var keyLabel: String { Self.keyLabels[keyCode] ?? "#\(keyCode)" }

    public var displayString: String {
        var result = ""
        if modifiers & Self.control != 0 { result += "⌃" }
        if modifiers & Self.option != 0 { result += "⌥" }
        if modifiers & Self.shift != 0 { result += "⇧" }
        if modifiers & Self.command != 0 { result += "⌘" }
        return result + keyLabel
    }

    // ANSI virtual key codes (kVK_*).
    static let keyLabels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        49: "Space", 50: "`", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
