import Foundation

/// A key that works while picking what to capture, and what it does, for the reference in Settings › Shortcuts.
public struct PickingKey: Equatable, Sendable {
    public let key: String
    public let label: String
}

extension PickingKey {
    /// The overlay's keys in the order Settings lists them, with the choices they step through taken from the overlay's
    /// own values, so the reference changes when they do. The guide's Keyboard shortcuts › While selecting has the rest.
    public static var all: [PickingKey] {
        let targets = CaptureTarget.allCases.map(\.title).joined(separator: " · ")
        let delays = CaptureDelay.choices.filter { $0 > 0 }.map(String.init).joined(separator: ", ")
        let ratios = AspectRatio.allCases.filter { $0 != .free }.map(\.label).joined(separator: ", ")
        return [
            PickingKey(key: "Tab", label: targets),
            PickingKey(key: "B", label: String(localized: "Browser page only")),
            PickingKey(key: "D", label: String(localized: "Delay \(delays) s")),
            PickingKey(key: "S", label: String(localized: "Scrolling capture")),
            PickingKey(key: "R", label: String(localized: "Ratio \(ratios)")),
            PickingKey(key: "M", label: String(localized: "Magnifier")),
            PickingKey(key: "C", label: String(localized: "Crosshair")),
            PickingKey(key: "I", label: String(localized: "Size label")),
            PickingKey(key: "⌥", label: String(localized: "Adjust before recording")),
            PickingKey(key: "Esc", label: String(localized: "Cancel")),
        ]
    }
}

extension ShotAction {
    /// The SF Symbol beside the action in the menu bar menu and in Settings › Shortcuts.
    public var symbol: String {
        switch self {
        case .screenshot: "viewfinder"
        case .record: "record.circle"
        case .pickColor: "eyedropper"
        case .copyPath: "doc.on.clipboard"
        }
    }
}
