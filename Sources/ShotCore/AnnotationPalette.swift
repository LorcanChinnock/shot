import CoreGraphics
import Foundation

/// What the annotation toolbar shows and sets, for the photo and the video editor alike: the text being typed's style,
/// else the selected annotation's, else the style the tool's next annotation gets.
///
/// A value built from an editor's state when it's read. Its setters change `editingText`, `selection` and `style` here;
/// the editor then adopts them, recording a changed selection as an undo step its own way.
public struct AnnotationPalette: Equatable, Sendable {
    /// The style the next annotation gets.
    public var style: EditorStyle
    /// The text or note whose text field is open.
    public var editingText: Annotation?
    /// True when `editingText` isn't in the document yet, so its style also becomes the next one's.
    public var editingTextIsNew: Bool
    /// The selected annotation.
    public var selection: Annotation?
    /// `nil` when no tool is picked, as in the video editor with nothing drawing.
    public var tool: EditorTool?
    /// Pixels per point of the image or canvas the annotations are drawn on, which line widths are multiplied by.
    public var scale: CGFloat
    /// The longer side of the image or canvas, which redaction amounts are fractions of.
    public var imageLength: CGFloat
    /// The effect and strength the spotlights already there share; `nil` when there are none.
    public var sharedSpotlight: SpotlightStyle?

    public init(
        style: EditorStyle, editingText: Annotation?, editingTextIsNew: Bool, selection: Annotation?, tool: EditorTool?,
        scale: CGFloat, imageLength: CGFloat, sharedSpotlight: SpotlightStyle?
    ) {
        self.style = style
        self.editingText = editingText
        self.editingTextIsNew = editingTextIsNew
        self.selection = selection
        self.tool = tool
        self.scale = scale
        self.imageLength = imageLength
        self.sharedSpotlight = sharedSpotlight
    }

    private var shown: Annotation? { editingText ?? selection }

    /// True when the toolbar sets the style of the next annotation: nothing is selected, or the selection is the
    /// annotation just drawn, so fixing its style fixes the tool's too. One picked with the select tool restyles alone.
    public var stylesNextAnnotation: Bool {
        selection == nil || tool != .select
    }

    // MARK: Colour

    /// The colour shown: the text being typed's, else the selection's, else the colour for the tool's next annotation.
    public var color: RGBA {
        editingText?.color ?? selection?.color ?? nextColor
    }

    /// The colour for the tool's next annotation: notes and the highlighter keep their own.
    public var nextColor: RGBA {
        get {
            switch tool {
            case .note: style.noteColor
            case .highlight: style.highlightColor
            case .select, .hand, .arrow, .line, .shape, .pen, .text, .spotlight, .redact, .counter, .crop, nil: style.color
            }
        }
        set {
            switch tool {
            case .note: style.noteColor = newValue
            case .highlight: style.highlightColor = newValue
            case .select, .hand, .arrow, .line, .shape, .pen, .text, .spotlight, .redact, .counter, .crop, nil: style.color = newValue
            }
        }
    }

    public mutating func setColor(_ color: RGBA) {
        if let text = editingText {
            editingText?.color = color
            // New text or a new note also sets the colour for the next one.
            if editingTextIsNew {
                if case .note = text.kind {
                    style.noteColor = color
                } else {
                    style.color = color
                }
            }
            return
        }
        selection?.color = color
        if stylesNextAnnotation {
            nextColor = color
        }
    }

    /// The fill shown, `nil` for none: the selection's, else the fill for the next shape.
    public var fill: RGBA? {
        selection != nil ? selection?.fill : style.fill
    }

    public mutating func setFill(_ fill: RGBA?) {
        selection?.fill = fill
        if stylesNextAnnotation {
            style.fill = fill
        }
    }

    /// Sets the colour, or the fill, to one picked from the colour editor, which also becomes the palette's last custom colour.
    public mutating func pickCustom(_ color: RGBA, forFill: Bool) {
        if forFill {
            setFill(color)
        } else {
            setColor(color)
        }
        style.customColors[customSlot(forFill: forFill)] = color
    }

    /// The colour or fill palette's last custom colour.
    public func lastCustom(forFill: Bool) -> RGBA? {
        style.customColors[customSlot(forFill: forFill)]
    }

    public func customSlot(forFill: Bool) -> ColorSlot {
        ColorSlot(forFill: forFill, shown: shown, tool: tool)
    }

    // MARK: What the toolbar offers

    /// True when the toolbar offers a colour and width: the text being typed or the selection takes them, or else the tool does.
    public var showsStyle: Bool {
        editingText != nil || (selection?.isStyled ?? tool?.isStyled ?? false)
    }

    /// True when the width sets a text size, so the toolbar offers sizes rather than line widths.
    public var sizesText: Bool {
        shown?.sizesText ?? tool?.sizesText ?? false
    }

    /// True when the toolbar offers a fill: a shape is selected, or is the tool.
    public var showsFill: Bool {
        selection?.supportsFill ?? (tool == .shape)
    }

    // MARK: Width

    /// The width of the next annotation, in pixels.
    public var lineWidth: CGFloat { EditorStyle.widths[style.widthIndex] * scale }

    /// The width shown, as an index into `EditorStyle.widths`: the text being typed's, else the selection's, the nearest
    /// one to it, else the next annotation's.
    public var lineWidthIndex: Int {
        guard let shown else {
            return style.widthIndex
        }
        return EditorStyle.widths.indices.min { abs(EditorStyle.widths[$0] * scale - shown.lineWidth) < abs(EditorStyle.widths[$1] * scale - shown.lineWidth) } ?? style.widthIndex
    }

    public mutating func setLineWidthIndex(_ index: Int) {
        let width = EditorStyle.widths[index] * scale
        if editingText != nil {
            // Text resizes as it's typed; new text also sets the width for the next annotation.
            editingText?.setLineWidth(width)
            if editingTextIsNew {
                style.widthIndex = index
            }
            return
        }
        selection?.setLineWidth(width)
        if stylesNextAnnotation {
            style.widthIndex = index
        }
    }

    // MARK: Shape

    /// The outline shown: the selected shape's, else the next shape's. `nil` when neither is a shape.
    public var shape: BoxShape? {
        if let selection {
            guard case let .shape(shape, _) = selection.kind else {
                return nil
            }
            return shape
        }
        return tool == .shape ? style.shape : nil
    }

    public mutating func setShape(_ shape: BoxShape) {
        if case let .shape(_, rect) = selection?.kind {
            selection?.kind = .shape(shape, rect: rect)
        }
        if stylesNextAnnotation {
            style.shape = shape
        }
    }

    // MARK: Redaction

    /// How a redaction hides: the selected one's, else the next one's. `nil` when neither is one.
    public var redaction: Redaction? {
        if let selection {
            return selection.redaction
        }
        return tool == .redact ? style.redaction : nil
    }

    public mutating func setRedaction(_ redaction: Redaction) {
        selection?.setRedaction(redaction)
        if stylesNextAnnotation {
            style.redaction = redaction
        }
    }

    /// How strongly a redaction hides: the selected one's, else the next one's.
    public var redactionAmount: CGFloat {
        selection?.redactionAmount(imageLength: imageLength) ?? style.redactionAmount
    }

    public mutating func setRedactionAmount(_ amount: CGFloat) {
        selection?.setRedactionAmount(amount)
        if stylesNextAnnotation {
            style.redactionAmount = amount
        }
    }

    // MARK: Spotlight

    /// The next spotlight's style: the chosen shape and edge, with the effect and strength the spotlights already share.
    public var nextSpotlightStyle: SpotlightStyle {
        let shared = sharedSpotlight ?? style.spotlight
        return SpotlightStyle(shape: style.spotlight.shape, effect: shared.effect, strength: shared.strength, softEdge: style.spotlight.softEdge)
    }

    /// The spotlight style shown: the selected spotlight's, else the next one's. `nil` when neither is one.
    public var spotlight: SpotlightStyle? {
        if let selection {
            guard case let .spotlight(_, style) = selection.kind else {
                return nil
            }
            return style
        }
        return tool == .spotlight ? nextSpotlightStyle : nil
    }

    public mutating func setSpotlightShape(_ shape: BoxShape) {
        selection?.restyleSpotlight { $0.shape = shape }
        if stylesNextAnnotation {
            style.spotlight.shape = shape
        }
    }

    public mutating func setSpotlightSoftEdge(_ softEdge: Double) {
        selection?.restyleSpotlight { $0.softEdge = softEdge }
        if stylesNextAnnotation {
            style.spotlight.softEdge = softEdge
        }
    }

    // MARK: Alignment

    /// The alignment shown: the text being typed's, else the selection's, else the next text's or note's.
    /// `nil` when none of them is text or a note.
    public var alignment: TextAlign? {
        if let shown {
            return shown.alignsText ? shown.alignment : nil
        }
        return tool == .text || tool == .note ? style.alignment : nil
    }

    public mutating func setAlignment(_ alignment: TextAlign) {
        if editingText != nil {
            editingText?.alignment = alignment
            if editingTextIsNew {
                style.alignment = alignment
            }
            return
        }
        selection?.alignment = alignment
        if stylesNextAnnotation {
            style.alignment = alignment
        }
    }
}
