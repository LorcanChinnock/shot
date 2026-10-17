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

extension AnimationPreset {
    public var title: String {
        switch self {
        case .fadeIn: String(localized: "Fade In")
        case .fadeOut: String(localized: "Fade Out")
        case .pop: String(localized: "Pop")
        case .slideIn: String(localized: "Slide In")
        case .drawOn: String(localized: "Draw On")
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

extension ProjectOrigin {
    /// Who made a file and how, as the gallery's mark says: "Made by Claude Code · annotate · 14:03", or
    /// "Command line · trim · 14:03" for a `shot` run, whoever started it. The date shows too when it isn't today.
    public func summary(now: Date = Date(), calendar: Calendar = .current) -> String {
        let who: String? = switch via {
        case .app: nil
        case .cli: String(localized: "Command line")
        case .mcp: clientName.map { String(localized: "Made by \($0)") } ?? String(localized: "Made by an agent")
        }
        let when = calendar.isDate(date, inSameDayAs: now) ? date.formatted(date: .omitted, time: .shortened) : date.formatted(date: .abbreviated, time: .shortened)
        return [who, action, when].compactMap { $0 }.joined(separator: " · ")
    }
}

extension VideoExportOptions {
    /// Describes a GIF made with these options, for Settings.
    public var gifSummary: String {
        let seconds = Int(GIFExporter.maxDuration)
        return gifWidth == Self.originalWidth
            ? String(localized: "\(gifFrameRate) fps, full width, first \(seconds) seconds.")
            : String(localized: "\(gifFrameRate) fps, up to \(gifWidth) px wide, first \(seconds) seconds.")
    }
}
