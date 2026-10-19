#if canImport(Darwin)
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

extension EditorTool {
    public var title: String {
        switch self {
        case .select: String(localized: "Select")
        case .hand: String(localized: "Hand")
        case .arrow: String(localized: "Arrow")
        case .line: String(localized: "Line")
        case .shape: String(localized: "Shape")
        case .pen: String(localized: "Pen")
        case .text: String(localized: "Text")
        case .note: String(localized: "Sticky note")
        case .highlight: String(localized: "Highlight")
        case .spotlight: String(localized: "Spotlight")
        case .redact: String(localized: "Redact")
        case .counter: String(localized: "Counter")
        case .crop: String(localized: "Crop")
        }
    }
}

extension BoxShape {
    public var title: String {
        switch self {
        case .rectangle: String(localized: "Rectangle")
        case .ellipse: String(localized: "Ellipse")
        case .triangle: String(localized: "Triangle")
        case .diamond: String(localized: "Diamond")
        case .star: String(localized: "Star")
        }
    }
}

extension Redaction {
    public var title: String {
        switch self {
        case .blur: String(localized: "Blur")
        case .pixelate: String(localized: "Pixelate")
        }
    }
}

extension TextAlign {
    public var title: String {
        switch self {
        case .left: String(localized: "Align Left")
        case .center: String(localized: "Align Centre")
        case .right: String(localized: "Align Right")
        }
    }
}

extension SpotlightStyle.Effect {
    public var title: String {
        switch self {
        case .darken: String(localized: "Darken")
        case .blur: String(localized: "Blur")
        }
    }
}

extension ShadowPreset {
    public var title: String {
        switch self {
        case .soft: String(localized: "Soft")
        case .float: String(localized: "Float")
        case .contact: String(localized: "Contact")
        case .glow: String(localized: "Glow")
        }
    }
}

extension Annotation {
    /// What the layers panel and the timeline call it: the name it was given, else the first words of a text or note,
    /// else its kind.
    public var layerName: String {
        name ?? automaticName
    }

    /// Renames it as the layers panel's name field does: an empty name goes back to the automatic one, and the name it
    /// already shows leaves it as it is, so committing an untouched field doesn't fix an automatic name in place.
    public mutating func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != layerName else {
            return
        }
        name = trimmed
    }

    private var automaticName: String {
        switch kind {
        case let .text(string, _, _): Self.firstWords(of: string) ?? kindTitle
        case let .note(string, _): Self.firstWords(of: string) ?? kindTitle
        case let .counter(number, _): String(localized: "Step \(number)")
        case .arrow, .line, .shape, .highlight, .pixelate, .blur, .spotlight, .freehand, .marker, .image: kindTitle
        }
    }

    /// What kind of annotation it is, whatever it's named.
    public var kindTitle: String {
        switch kind {
        case .arrow: String(localized: "Arrow")
        case .line: String(localized: "Line")
        case let .shape(shape, _): shape.title
        case .highlight: String(localized: "Highlight")
        case .pixelate: String(localized: "Pixelate")
        case .blur: String(localized: "Blur")
        case .spotlight: String(localized: "Spotlight")
        case .text: String(localized: "Text")
        case .note: String(localized: "Note")
        case .counter: String(localized: "Step")
        case .freehand: String(localized: "Pen")
        case .marker: String(localized: "Highlighter")
        case .image: String(localized: "Image")
        }
    }

    /// What VoiceOver says after its name: its kind, unless the name is just that.
    public var accessibilityKind: String {
        layerName == kindTitle ? String(localized: "annotation") : kindTitle.localizedLowercase
    }


    private static func firstWords(of string: String, limit: Int = 24) -> String? {
        let words = string.split(whereSeparator: \.isWhitespace)
        guard let first = words.first else {
            return nil
        }
        var name = String(first.prefix(limit))
        for word in words.dropFirst() {
            guard name.count + 1 + word.count <= limit else {
                return name + "…"
            }
            name += " " + word
        }
        return name
    }
}
#endif
