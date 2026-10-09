import CoreGraphics

public enum EditorTool: String, CaseIterable, Identifiable, Sendable {
    case select, hand, arrow, line, shape, pen, text, note, highlight, spotlight, redact, counter, crop

    public var id: String { rawValue }

    public var key: Character {
        switch self {
        case .select: "v"
        case .hand: "h"
        case .arrow: "a"
        case .line: "l"
        case .shape: "r"
        case .pen: "d"
        case .text: "t"
        case .note: "s"
        case .highlight: "m"
        case .spotlight: "f"
        case .redact: "b"
        case .counter: "n"
        case .crop: "c"
        }
    }

    public var title: String {
        switch self {
        case .select: "Select"
        case .hand: "Hand"
        case .arrow: "Arrow"
        case .line: "Line"
        case .shape: "Shape"
        case .pen: "Pen"
        case .text: "Text"
        case .note: "Sticky Note"
        case .highlight: "Highlight"
        case .spotlight: "Spotlight"
        case .redact: "Redact"
        case .counter: "Counter"
        case .crop: "Crop"
        }
    }

    /// False for select, hand and crop, which an editor never starts with.
    public var isDrawing: Bool { self != .select && self != .hand && self != .crop }

    /// True for the tools that draw in the chosen colour and width.
    public var isStyled: Bool {
        switch self {
        case .arrow, .line, .shape, .pen, .text, .note, .highlight, .counter: true
        case .select, .hand, .spotlight, .redact, .crop: false
        }
    }

    /// True for the tools whose width sets the size of their text.
    public var sizesText: Bool {
        switch self {
        case .text, .note, .counter: true
        default: false
        }
    }
}

/// The tool, colours and width a new editor window starts with: the last ones used.
public struct EditorStyle: Equatable, Sendable {
    /// Line widths in points; the image's scale multiplies them.
    public static let widths: [CGFloat] = [2, 4, 8]

    public var tool: EditorTool
    public var color: RGBA
    /// Notes keep their own colour, pale yellow until the user picks another.
    public var noteColor: RGBA
    /// The highlighter keeps its own colour too, yellow until the user picks another.
    public var highlightColor: RGBA
    /// What new shapes are filled with; `nil` leaves them unfilled.
    public var fill: RGBA?
    /// Index into `widths`.
    public var widthIndex: Int
    /// The last custom colour picked in each palette, which its rainbow swatch offers again.
    public var customColors: [ColorSlot: RGBA]
    public var shape: BoxShape
    public var redaction: Redaction
    /// How strongly the next redaction hides, within `Redaction.amounts`.
    public var redactionAmount: CGFloat
    public var spotlight: SpotlightStyle
    public var alignment: TextAlign
    /// The last shadow and border given to each kind but the capture, in points, which new ones of that kind start
    /// with. A kind with none starts plain.
    public var objectStyles: [StyleKind: ObjectStyle]

    public init(
        tool: EditorTool = .arrow, color: RGBA = RGBA.presets[0], noteColor: RGBA = RGBA.presets[2],
        highlightColor: RGBA = RGBA.presets[2], fill: RGBA? = nil, widthIndex: Int = 1, customColors: [ColorSlot: RGBA] = [:],
        shape: BoxShape = .rectangle, redaction: Redaction = .blur, redactionAmount: CGFloat = Redaction.defaultAmount,
        spotlight: SpotlightStyle = SpotlightStyle(),
        alignment: TextAlign = .left, objectStyles: [StyleKind: ObjectStyle] = [:]
    ) {
        self.tool = tool
        self.color = color
        self.noteColor = noteColor
        self.highlightColor = highlightColor
        self.fill = fill
        self.widthIndex = widthIndex
        self.customColors = customColors
        self.shape = shape
        self.redaction = redaction
        self.redactionAmount = redactionAmount
        self.spotlight = spotlight
        self.alignment = alignment
        self.objectStyles = objectStyles
    }

    /// The style a new object of `kind` starts with on a document of `scale` pixels per point: the last one given to
    /// that kind, else none. The capture always starts plain.
    public func objectStyle(for kind: StyleKind, scale: CGFloat) -> ObjectStyle {
        guard kind != .capture else {
            return ObjectStyle()
        }
        return (objectStyles[kind] ?? ObjectStyle()).scaled(by: scale)
    }
}

/// A palette that remembers its own last custom colour.
public enum ColorSlot: String, Codable, CodingKeyRepresentable, Sendable {
    case stroke, fill, note, highlight

    /// The fill palette's slot, else the note's or highlighter's for the one shown or about to be drawn, else the stroke's.
    public init(forFill: Bool, shown: Annotation?, tool: EditorTool?) {
        if forFill {
            self = .fill
        } else if let shown {
            switch shown.kind {
            case .note: self = .note
            case .marker: self = .highlight
            default: self = .stroke
            }
        } else {
            switch tool {
            case .note: self = .note
            case .highlight: self = .highlight
            default: self = .stroke
            }
        }
    }
}
