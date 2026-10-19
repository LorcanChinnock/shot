import Foundation

// What the app calls ShotModel's types. They live here because the build extracts the catalog's strings from ShotCore,
// not ShotModel, and shotLocalized(_:) is ShotCore's.

extension ShotAction {
    public var title: String {
        switch self {
        case .captureArea: shotLocalized("Capture Area")
        case .captureFullscreen: shotLocalized("Capture Full Screen")
        case .captureWindow: shotLocalized("Capture Window")
        case .record: shotLocalized("Record Area")
        case .recordFullscreen: shotLocalized("Record Full Screen")
        case .recordWindow: shotLocalized("Record Window")
        case .pickColor: shotLocalized("Pick Colour")
        case .copyPath: shotLocalized("Copy Latest Capture's Path")
        case .capturePrevious: shotLocalized("Capture Previous Area")
        case .copyText: shotLocalized("Copy Text")
        case .focusQuickAccess: shotLocalized("Focus Quick Access")
        }
    }
}

extension ShotAction.Conflict {
    public func message(for combo: KeyCombo) -> String {
        switch self {
        case .reserved: shotLocalized("\(combo.displayString) is reserved by macOS")
        case let .taken(action): shotLocalized("\(combo.displayString) is already used by \(action.title)")
        }
    }
}

extension Easing {
    public var title: String {
        switch self {
        case .linear: shotLocalized("Linear")
        case .easeIn: shotLocalized("Ease in")
        case .easeOut: shotLocalized("Ease out")
        case .easeInOut: shotLocalized("Ease in-out")
        case .spring: shotLocalized("Spring")
        }
    }
}

extension AnimationPreset {
    public var title: String {
        switch self {
        case .fadeIn: shotLocalized("Fade In")
        case .fadeOut: shotLocalized("Fade Out")
        case .pop: shotLocalized("Pop")
        case .slideIn: shotLocalized("Slide In")
        case .drawOn: shotLocalized("Draw On")
        }
    }
}

extension AspectRatio {
    public var label: String {
        switch self {
        case .free: shotLocalized("Free")
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
        case .cli: shotLocalized("Command line")
        case .mcp: clientName.map { shotLocalized("Made by \($0)") } ?? shotLocalized("Made by an agent")
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
            ? shotLocalized("\(gifFrameRate) fps, full width, first \(seconds) seconds.")
            : shotLocalized("\(gifFrameRate) fps, up to \(gifWidth) px wide, first \(seconds) seconds.")
    }
}

extension EditorTool {
    public var title: String {
        switch self {
        case .select: shotLocalized("Select")
        case .hand: shotLocalized("Hand")
        case .arrow: shotLocalized("Arrow")
        case .line: shotLocalized("Line")
        case .shape: shotLocalized("Shape")
        case .pen: shotLocalized("Pen")
        case .text: shotLocalized("Text")
        case .note: shotLocalized("Sticky note")
        case .highlight: shotLocalized("Highlight")
        case .spotlight: shotLocalized("Spotlight")
        case .redact: shotLocalized("Redact")
        case .counter: shotLocalized("Counter")
        case .crop: shotLocalized("Crop")
        }
    }
}

extension BoxShape {
    public var title: String {
        switch self {
        case .rectangle: shotLocalized("Rectangle")
        case .ellipse: shotLocalized("Ellipse")
        case .triangle: shotLocalized("Triangle")
        case .diamond: shotLocalized("Diamond")
        case .star: shotLocalized("Star")
        }
    }
}

extension Redaction {
    public var title: String {
        switch self {
        case .blur: shotLocalized("Blur")
        case .pixelate: shotLocalized("Pixelate")
        }
    }
}

extension TextAlign {
    public var title: String {
        switch self {
        case .left: shotLocalized("Align Left")
        case .center: shotLocalized("Align Centre")
        case .right: shotLocalized("Align Right")
        }
    }
}

extension SpotlightStyle.Effect {
    public var title: String {
        switch self {
        case .darken: shotLocalized("Darken")
        case .blur: shotLocalized("Blur")
        }
    }
}

extension ShadowPreset {
    public var title: String {
        switch self {
        case .soft: shotLocalized("Soft")
        case .float: shotLocalized("Float")
        case .contact: shotLocalized("Contact")
        case .glow: shotLocalized("Glow")
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
        case let .counter(number, _): shotLocalized("Step \(number)")
        case .arrow, .line, .shape, .highlight, .pixelate, .blur, .spotlight, .freehand, .marker, .image: kindTitle
        }
    }

    /// What kind of annotation it is, whatever it's named.
    public var kindTitle: String {
        switch kind {
        case .arrow: shotLocalized("Arrow")
        case .line: shotLocalized("Line")
        case let .shape(shape, _): shape.title
        case .highlight: shotLocalized("Highlight")
        case .pixelate: shotLocalized("Pixelate")
        case .blur: shotLocalized("Blur")
        case .spotlight: shotLocalized("Spotlight")
        case .text: shotLocalized("Text")
        case .note: shotLocalized("Note")
        case .counter: shotLocalized("Step")
        case .freehand: shotLocalized("Pen")
        case .marker: shotLocalized("Highlighter")
        case .image: shotLocalized("Image")
        }
    }

    /// What VoiceOver says after its name: its kind, unless the name is just that.
    public var accessibilityKind: String {
        layerName == kindTitle ? shotLocalized("annotation") : kindTitle.localizedLowercase
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
