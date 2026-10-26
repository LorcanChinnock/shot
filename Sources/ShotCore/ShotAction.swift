import CoreGraphics
import Foundation

public enum ShotAction: String, CaseIterable, Sendable {
    case captureArea = "capture-area"
    case captureFullscreen = "capture-fullscreen"
    case captureWindow = "capture-window"
    case record
    case recordFullscreen = "record-fullscreen"
    case recordWindow = "record-window"
    /// Samples a colour on screen and copies its hex.
    case pickColor = "pick-color"
    /// Copies the newest capture's path.
    case copyPath = "copy-path"
    /// Captures the area the last area screenshot took again, for before and after shots. New actions go last, since
    /// `HotkeyCenter` numbers hotkeys by position.
    case capturePrevious = "capture-previous"
    /// Reads the text in a dragged-out area and copies it, without saving a capture.
    case copyText = "copy-text"
    /// Hands the keyboard to the newest Quick Access card, without bringing Shot to the front.
    case focusQuickAccess = "focus-quick-access"

    public var isRecording: Bool {
        switch self {
        case .record, .recordFullscreen, .recordWindow: true
        case .captureArea, .captureFullscreen, .captureWindow, .capturePrevious, .pickColor, .copyPath, .copyText, .focusQuickAccess: false
        }
    }

    /// Takes a screenshot, as opposed to recording or a tool like Pick Colour.
    public var isCapture: Bool {
        switch self {
        case .captureArea, .captureFullscreen, .captureWindow, .capturePrevious: true
        case .record, .recordFullscreen, .recordWindow, .pickColor, .copyPath, .copyText, .focusQuickAccess: false
        }
    }

    /// Whether Settings offers a global shortcut for this action. The rest are menu items and `shot://` URLs
    /// only, since few people would bind them. They keep their place in `allCases`, which numbers hotkeys.
    public var hasShortcut: Bool {
        switch self {
        case .recordFullscreen, .recordWindow, .capturePrevious, .pickColor, .copyPath, .focusQuickAccess: false
        case .captureArea, .captureFullscreen, .captureWindow, .record, .copyText: true
        }
    }

    /// Mirrors the macOS screenshot keys with ⌃ in place of ⌘. Record fullscreen and window
    /// have no default: press Enter or Space in the record overlay instead. Pick Colour, Copy Path, Capture Previous
    /// Area, Copy Text and Focus Quick Access stay out of the way with none.
    public var defaultCombo: KeyCombo? {
        switch self {
        case .captureArea: KeyCombo(keyCode: 21, modifiers: KeyCombo.control | KeyCombo.shift)
        case .captureFullscreen: KeyCombo(keyCode: 20, modifiers: KeyCombo.control | KeyCombo.shift)
        case .captureWindow: KeyCombo(keyCode: 13, modifiers: KeyCombo.control | KeyCombo.shift)
        case .record: KeyCombo(keyCode: 23, modifiers: KeyCombo.control | KeyCombo.shift)
        case .recordFullscreen, .recordWindow, .pickColor, .copyPath, .capturePrevious, .copyText, .focusQuickAccess: nil
        }
    }

    /// The default once Shot takes over ⌘⇧3 to ⌘⇧5 from macOS. Window has none, as in macOS: press
    /// Space after ⌘⇧4. ⌘⇧W stays with apps, which use it to close windows.
    public func defaultCombo(replacingSystemScreenshots: Bool) -> KeyCombo? {
        guard replacingSystemScreenshots else {
            return defaultCombo
        }
        switch self {
        case .captureFullscreen: return KeyCombo(keyCode: 20, modifiers: KeyCombo.command | KeyCombo.shift)
        case .captureArea: return KeyCombo(keyCode: 21, modifiers: KeyCombo.command | KeyCombo.shift)
        case .record: return KeyCombo(keyCode: 23, modifiers: KeyCombo.command | KeyCombo.shift)
        case .captureWindow: return nil
        case .recordFullscreen, .recordWindow, .pickColor, .copyPath, .capturePrevious, .copyText, .focusQuickAccess: return defaultCombo
        }
    }

    /// Why `combo` can't be this action's shortcut.
    public enum Conflict: Equatable, Sendable {
        /// macOS or every app uses it: quit, close, switch apps, Spotlight, hide or minimise.
        case reserved
        /// Another of Shot's actions has it.
        case taken(by: ShotAction)
    }

    /// Shortcuts Shot never takes, since a global one would steal them from every app.
    /// ⌘Q, ⌘W, ⌘Tab, ⌘Space, ⌘H and ⌘M.
    public static let reservedCombos = Set([12, 13, 48, 49, 4, 46].map { KeyCombo(keyCode: $0, modifiers: KeyCombo.command) })

    /// Why `combo` can't be this action's shortcut given Shot's `bindings`, or `nil` when it can. Only Shot's own
    /// shortcuts and the reserved ones are checked; other apps' aren't known.
    public func conflict(for combo: KeyCombo, bindings: [ShotAction: KeyCombo]) -> Conflict? {
        if Self.reservedCombos.contains(combo) {
            return .reserved
        }
        // In `allCases` order, so the answer doesn't depend on the dictionary's.
        return Self.allCases.first { $0 != self && bindings[$0] == combo }.map { .taken(by: $0) }
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

    /// The combo of `keyCode` with the modifiers among `flags`, which `NSEvent.ModifierFlags` shares the bits of.
    public init(keyCode: UInt32, eventFlags flags: CGEventFlags) {
        var modifiers: UInt32 = 0
        if flags.contains(.maskCommand) { modifiers |= Self.command }
        if flags.contains(.maskShift) { modifiers |= Self.shift }
        if flags.contains(.maskAlternate) { modifiers |= Self.option }
        if flags.contains(.maskControl) { modifiers |= Self.control }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    /// The modifiers as event flags, which `NSEvent.ModifierFlags` shares the bits of.
    public var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers & Self.command != 0 { flags.insert(.maskCommand) }
        if modifiers & Self.shift != 0 { flags.insert(.maskShift) }
        if modifiers & Self.option != 0 { flags.insert(.maskAlternate) }
        if modifiers & Self.control != 0 { flags.insert(.maskControl) }
        return flags
    }

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
        36: "↩", 48: "⇥", 53: "⎋", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5",
        88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
    ]
}

extension ShotAction {
    public var title: String {
        switch self {
        case .captureArea: String(localized: "Capture Area")
        case .captureFullscreen: String(localized: "Capture Full Screen")
        case .captureWindow: String(localized: "Capture Window")
        case .record: String(localized: "Record Area")
        case .recordFullscreen: String(localized: "Record Full Screen")
        case .recordWindow: String(localized: "Record Window")
        case .pickColor: String(localized: "Pick Colour")
        case .copyPath: String(localized: "Copy Latest Capture's Path")
        case .capturePrevious: String(localized: "Capture Previous Area")
        case .copyText: String(localized: "Copy Text")
        case .focusQuickAccess: String(localized: "Focus Quick Access")
        }
    }
}

extension ShotAction.Conflict {
    public func message(for combo: KeyCombo) -> String {
        switch self {
        case .reserved: String(localized: "\(combo.displayString) is reserved by macOS")
        case let .taken(action): String(localized: "\(combo.displayString) is already used by \(action.title)")
        }
    }
}
