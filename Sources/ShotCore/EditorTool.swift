import CoreGraphics
import Foundation

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

    /// The tool whose key `characters` types, in either case.
    public init?(key characters: String) {
        guard let tool = Self.allCases.first(where: { String($0.key) == characters.lowercased() }) else {
            return nil
        }
        self = tool
    }

    /// False for select, hand and crop, which an editor never starts with.
    public var isDrawing: Bool { self != .select && self != .hand && self != .crop }

    /// True for the tools that always show the selection's outline and handles and resize from them: select, and text
    /// and note, whose press picks existing text or a note to move. The others keep the mark just drawn selected for
    /// the style bar; see `showsHoverHandles` for which of them reveal its handles on hover.
    public var editsSelection: Bool {
        switch self {
        case .select, .text, .note: true
        case .hand, .arrow, .line, .shape, .pen, .highlight, .spotlight, .redact, .counter, .crop: false
        }
    }

    /// True for the tools whose mark just drawn shows its handles while the pointer hovers it: arrow and line (ends and
    /// bend), and the boxes of shape, spotlight and redact (corners, edges and corner radius). Pen and highlight never
    /// do, so strokes written close together always start new marks, and a counter has no handles.
    public var showsHoverHandles: Bool {
        switch self {
        case .arrow, .line, .shape, .spotlight, .redact: true
        case .select, .hand, .pen, .text, .note, .highlight, .counter, .crop: false
        }
    }

    /// Whether `selection` shows its outline and handles. The tools that edit the selection always show them. A tool
    /// that `showsHoverHandles` shows them round the mark just drawn only while the pointer, last moved to `hover`, is over the mark
    /// or within `tolerance` of one of its handles. `hover` is where the pointer last moved, not where it's pressed, so
    /// a press that lands on a handle the pointer never hovered finds it hidden and draws.
    public func showsHandles(of selection: Annotation, hoveredAt hover: CGPoint?, tolerance: CGFloat) -> Bool {
        if editsSelection {
            return true
        }
        guard showsHoverHandles, let hover else {
            return false
        }
        return selection.hitTest(hover, tolerance: tolerance) || selection.handle(at: hover, tolerance: tolerance) != nil
    }

    /// The handle of `selection` a press at `point` adjusts, or `nil` when the press draws or picks instead. Only a
    /// showing handle counts, and a drawing tool never adjusts a locked mark.
    public func pressedHandle(of selection: Annotation, at point: CGPoint, hoveredAt hover: CGPoint?, tolerance: CGFloat) -> AnnotationHandle? {
        guard showsHandles(of: selection, hoveredAt: hover, tolerance: tolerance), editsSelection || !selection.isLocked else {
            return nil
        }
        return selection.handle(at: point, tolerance: tolerance)
    }

    /// True for the tools that draw in the chosen colour and width.
    public var takesColorAndWidth: Bool {
        switch self {
        case .arrow, .line, .shape, .pen, .text, .note, .highlight, .counter: true
        case .select, .hand, .spotlight, .redact, .crop: false
        }
    }

    /// True for the tools whose width sets the size of their text.
    public var sizesText: Bool {
        switch self {
        case .text, .note, .counter: true
        case .select, .hand, .arrow, .line, .shape, .pen, .highlight, .spotlight, .redact, .crop: false
        }
    }

    /// True for the tools whose lines can be dashed or dotted.
    public var takesLineDash: Bool {
        switch self {
        case .arrow, .line: true
        case .select, .hand, .shape, .pen, .text, .note, .highlight, .spotlight, .redact, .counter, .crop: false
        }
    }
}

/// The tool, colours and width a new editor window starts with: the last ones used.
public struct EditorStyle: Equatable, Sendable {
    /// The line widths the style bar steps through, in points; the image's scale multiplies them. Each step is about a
    /// quarter to a half bigger than the last, and the three widths older versions offered, 2, 4 and 8, are on it, so
    /// their marks and remembered widths land on a step.
    public static let widths: [CGFloat] = [1, 1.5, 2, 3, 4, 5, 6, 8, 10, 12, 16]
    /// The three widths older versions offered, Thin, Medium and Thick, which the Style panel's border sizes still use.
    public static let presetWidths: [CGFloat] = [2, 4, 8]
    /// Medium, 4 pt.
    public static let defaultWidth: CGFloat = 4

    /// `points` within the thinnest and thickest of `widths`. A width between two steps stays as it is, as one typed in
    /// the style bar's size box does.
    public static func clampedWidth(_ points: CGFloat) -> CGFloat {
        min(max(points, widths[0]), widths[widths.count - 1])
    }

    /// The step after `points`, thicker with `up`, else thinner; `nil` past the thickest or thinnest. A width between two
    /// steps goes to the next one along.
    public static func step(from points: CGFloat, up: Bool) -> CGFloat? {
        let tolerance: CGFloat = 0.01
        return up ? widths.first { $0 > points + tolerance } : widths.last { $0 < points - tolerance }
    }

    /// The width that shows as `size` for `kind`, the inverse of `shownSize`, within the scale and rounded so the size
    /// shown is a whole or half point.
    public static func width(forShownSize size: CGFloat, sizing kind: SizeKind) -> CGFloat {
        let lowest = shownSize(width: widths[0], sizing: kind), highest = shownSize(width: widths[widths.count - 1], sizing: kind)
        let rounded = (min(max(size, lowest), highest) * 2).rounded() / 2
        // A counter's size is shown rounded, so the inverse below misses the step a menu entry came from.
        if let step = widths.first(where: { shownSize(width: $0, sizing: kind) == rounded }) {
            return step
        }
        let width = switch kind {
        case .line: rounded
        case .text: rounded / 6
        case .note: (rounded - 8) / 3
        case .counter: (rounded / 1.1 - 10) / 3
        }
        return clampedWidth(width)
    }

    /// The size the style bar shows for a width of `points`: the width itself for a line, or the text's size in points
    /// for text, a note or a counter, which their width sets.
    public static func shownSize(width points: CGFloat, sizing kind: SizeKind) -> CGFloat {
        switch kind {
        case .line: points
        case .text: points * 6
        case .note: points * 3 + 8
        case .counter: ((points * 3 + 10) * 1.1).rounded()
        }
    }

    /// What a width sets the size of.
    public enum SizeKind: Equatable, Sendable {
        case line, text, note, counter
    }

    public var tool: EditorTool
    public var color: RGBA
    /// Notes keep their own colour, pale yellow until the user picks another.
    public var noteColor: RGBA
    /// The highlighter keeps its own colour too, yellow until the user picks another.
    public var highlightColor: RGBA
    /// What new shapes are filled with; `nil` leaves them unfilled.
    public var fill: RGBA?
    /// The colour of a new note's text; `nil` picks black or white, whichever reads better on the paper.
    public var noteTextColor: RGBA?
    /// The line width in points, usually one of `widths`; the image's scale multiplies it.
    public var width: CGFloat
    /// Whether the next arrow or line is solid, dashed or dotted.
    public var lineDash: LineDash
    /// The last custom colour picked in each palette, which its rainbow swatch offers again.
    public var customColors: [ColorSlot: RGBA]
    public var shape: BoxShape
    public var redaction: Redaction
    /// How strongly the next redaction hides, within `Redaction.amounts`.
    public var redactionAmount: CGFloat
    public var spotlight: SpotlightStyle
    /// How the lines of the next text line up.
    public var alignment: TextAlign
    /// How the lines of the next note line up: centred until the user picks another.
    public var noteAlignment: TextAlign
    /// Where the next note's text sits in it: in the middle until the user picks another.
    public var verticalAlignment: VerticalTextAlign
    public var penLine: PenLine
    /// The last shadow and border given to each kind but the capture, in points, which new ones of that kind start
    /// with. A kind with none starts plain.
    public var objectStyles: [StyleKind: ObjectStyle]

    public init(
        tool: EditorTool = .arrow, color: RGBA = RGBA.presets[0], noteColor: RGBA = RGBA.presets[2],
        highlightColor: RGBA = RGBA.presets[2], fill: RGBA? = nil, noteTextColor: RGBA? = nil,
        width: CGFloat = EditorStyle.defaultWidth, lineDash: LineDash = .solid, customColors: [ColorSlot: RGBA] = [:],
        shape: BoxShape = .rectangle, redaction: Redaction = .blur, redactionAmount: CGFloat = Redaction.defaultAmount,
        spotlight: SpotlightStyle = SpotlightStyle(),
        alignment: TextAlign = .left, noteAlignment: TextAlign = .center, verticalAlignment: VerticalTextAlign = .middle, penLine: PenLine = .smooth,
        objectStyles: [StyleKind: ObjectStyle] = [:]
    ) {
        self.tool = tool
        self.color = color
        self.noteColor = noteColor
        self.highlightColor = highlightColor
        self.fill = fill
        self.noteTextColor = noteTextColor
        self.width = width
        self.lineDash = lineDash
        self.customColors = customColors
        self.shape = shape
        self.redaction = redaction
        self.redactionAmount = redactionAmount
        self.spotlight = spotlight
        self.alignment = alignment
        self.noteAlignment = noteAlignment
        self.verticalAlignment = verticalAlignment
        self.penLine = penLine
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

    /// The style a new object of `kind` starts with in the image editor: the last one given to that kind, else
    /// `StyleKind.editorDefaultStyle`, so a placed image starts with the Soft shadow until an image is given another
    /// style. The capture always starts plain. The video editor keeps `objectStyle(for:scale:)`.
    public func editorObjectStyle(for kind: StyleKind, scale: CGFloat) -> ObjectStyle {
        guard kind != .capture else {
            return ObjectStyle()
        }
        return (objectStyles[kind] ?? kind.editorDefaultStyle).scaled(by: scale)
    }
}

/// A palette that remembers its own last custom colour.
public enum ColorSlot: String, Codable, CodingKeyRepresentable, Sendable {
    /// `noteText` is a note's text colour, which only `AnnotationPalette.pickCustomNoteText(_:)` picks.
    case stroke, fill, note, highlight, noteText

    /// The fill palette's slot, else the note's or highlighter's for the one shown or about to be drawn, else the stroke's.
    public init(forFill: Bool, shown: Annotation?, tool: EditorTool?) {
        if forFill {
            self = .fill
        } else if let shown {
            switch shown.kind {
            case .note: self = .note
            case .marker: self = .highlight
            case .arrow, .line, .shape, .highlight, .pixelate, .blur, .spotlight, .text, .counter, .freehand, .image: self = .stroke
            }
        } else {
            switch tool {
            case .note: self = .note
            case .highlight: self = .highlight
            case .select, .hand, .arrow, .line, .shape, .pen, .text, .spotlight, .redact, .counter, .crop, nil: self = .stroke
            }
        }
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
