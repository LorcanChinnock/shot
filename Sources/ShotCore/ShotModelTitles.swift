import Foundation

// What the app calls ShotModel's types. They live here because String(localized:) doesn't exist on Linux, where
// ShotModel builds and tests.

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

extension Easing {
    public var title: String {
        switch self {
        case .linear: String(localized: "Linear")
        case .easeIn: String(localized: "Ease in")
        case .easeOut: String(localized: "Ease out")
        case .easeInOut: String(localized: "Ease in-out")
        case .spring: String(localized: "Spring")
        }
    }
}

extension AspectRatio {
    public var label: String {
        switch self {
        case .free: String(localized: "Free")
        case .square: "1:1"
        case .fourThree: "4:3"
        case .threeTwo: "3:2"
        case .sixteenNine: "16:9"
        }
    }

    /// The label with its sides swapped when `portrait`, e.g. 9:16.
    public func label(portrait: Bool) -> String {
        portrait ? label.split(separator: ":").reversed().joined(separator: ":") : label
    }
}
