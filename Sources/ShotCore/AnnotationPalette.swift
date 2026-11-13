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
    /// What's selected in the text being typed, in UTF-16 code units; empty for a caret, `nil` when no text is typed.
    public var editingSelection: Range<Int>?
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
        style: EditorStyle, editingText: Annotation?, editingTextIsNew: Bool, editingSelection: Range<Int>? = nil, selection: Annotation?,
        tool: EditorTool?, scale: CGFloat, imageLength: CGFloat, sharedSpotlight: SpotlightStyle?
    ) {
        self.style = style
        self.editingText = editingText
        self.editingTextIsNew = editingTextIsNew
        self.editingSelection = editingSelection
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

    /// The colour for the tool's next annotation: notes and the highlighter keep their own. A transparent colour,
    /// remembered from a shape's outline, goes back to the default for a tool whose colour row has no transparent swatch,
    /// so the next mark never draws invisible.
    public var nextColor: RGBA {
        get {
            let defaults = EditorStyle()
            let (color, fallback) = switch tool {
            case .note: (style.noteColor, defaults.noteColor)
            case .highlight: (style.highlightColor, defaults.highlightColor)
            case .select, .hand, .arrow, .line, .shape, .pen, .text, .spotlight, .redact, .counter, .crop, nil: (style.color, defaults.color)
            }
            guard color.a == 0, let row = tool.flatMap(StyleBarColorRow.colorRow(for:)), !row.offersTransparent else {
                return color
            }
            return fallback
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

    /// The colour of the note shown's text, or the next note's; `nil` when it follows the paper, as it does until one is
    /// picked, and when the one shown isn't a note.
    public var noteTextColor: RGBA? {
        if let shown {
            return shown.noteTextColor
        }
        return tool == .note ? style.noteTextColor : nil
    }

    /// Sets the colour of the note shown's text, and the next note's; `nil` goes back to following the paper.
    public mutating func setNoteTextColor(_ color: RGBA?) {
        if editingText != nil {
            editingText?.noteTextColor = color
            if editingTextIsNew {
                style.noteTextColor = color
            }
            return
        }
        selection?.noteTextColor = color
        if stylesNextAnnotation {
            style.noteTextColor = color
        }
    }

    /// Sets a note's text colour to one picked from the colour editor, which becomes that palette's last custom colour.
    public mutating func pickCustomNoteText(_ color: RGBA) {
        setNoteTextColor(color)
        style.customColors[.noteText] = color
    }

    /// The colour rows the style bar shows, top to bottom, for the text being typed, else the selection, else the tool.
    public var colorRows: [StyleBarColorRow] {
        guard showsStyle else {
            return []
        }
        if let shown {
            return StyleBarColorRow.rows(for: shown.kind)
        }
        return tool.map(StyleBarColorRow.rows(for:)) ?? []
    }

    /// The controls on the right of the colour rows, a row at a time, top to bottom: the width first, an arrow's or line's
    /// dashes beside it, then a shape's outlines under it, and a text's alignment beside it. A note's alignments go under its size, one a row, since beside
    /// it they'd make the bar too wide to fit a small window with its panels open.
    public var controlRows: [[StyleBarControl]] {
        guard showsStyle else {
            return []
        }
        var rows: [[StyleBarControl]] = [[.width]]
        if lineDash != nil {
            rows[0].append(.lineDash)
        }
        if shape != nil {
            rows.append([.outline])
        }
        if alignment != nil {
            if verticalAlignment != nil {
                rows += [[.alignment], [.verticalAlignment]]
            } else {
                rows[0].append(.alignment)
            }
        }
        return rows
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
        editingText != nil || (selection?.takesColorAndWidth ?? tool?.takesColorAndWidth ?? false)
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
    public var lineWidth: CGFloat { style.width * scale }

    /// The width shown, in points: the text being typed's, else the selection's, else the next annotation's.
    public var shownWidth: CGFloat {
        shown.map { $0.lineWidth / scale } ?? style.width
    }

    /// What the width shown sets the size of, which the style bar's size box shows.
    public var sizeKind: EditorStyle.SizeKind {
        switch shown?.kind {
        case .text: return .text
        case .note: return .note
        case .counter: return .counter
        case nil:
            switch tool {
            case .text: return .text
            case .note: return .note
            case .counter: return .counter
            default: return .line
            }
        default: return .line
        }
    }

    /// The size the style bar's size box shows: the line width in points, or for text, a note or a counter, its text size.
    /// For text in more than one size it's the size of the part selected, or at the caret, and `nil` when what it
    /// stands for is in more than one size.
    public var shownSize: CGFloat? {
        guard let target = sizeTarget else {
            return EditorStyle.shownSize(width: shownWidth, sizing: sizeKind)
        }
        return target.shown.map { points(pixels: $0) }
    }

    /// The sizes the size box's menu lists: one for each step of `EditorStyle.widths`.
    public var sizeChoices: [CGFloat] {
        EditorStyle.widths.map { EditorStyle.shownSize(width: $0, sizing: sizeKind) }
    }

    /// Whether the width can step thicker (`by` above 0) or thinner: not past the thickest or thinnest step. Only the sign
    /// of `steps` counts, as each click steps once.
    public func canStepLineWidth(by steps: Int) -> Bool {
        guard let target = sizeTarget else {
            return EditorStyle.step(from: shownWidth, up: steps > 0) != nil
        }
        return target.reference.flatMap { nextSize(after: points(pixels: $0), up: steps > 0) } != nil
    }

    /// Steps the width shown one step thicker (`by` above 0) or thinner along `EditorStyle.widths`. From between two steps
    /// it goes to the next one along. Text in more than one size steps the size shown, or the largest when none is,
    /// and scales the rest of what's selected with it.
    public mutating func stepLineWidth(by steps: Int) {
        guard let target = sizeTarget else {
            if let next = EditorStyle.step(from: shownWidth, up: steps > 0) {
                setLineWidth(points: next)
            }
            return
        }
        guard let reference = target.reference, let next = nextSize(after: points(pixels: reference), up: steps > 0) else {
            return
        }
        setTextRuns(target.runs.mapping(in: target.range) { fitted($0 * pixels(points: next) / reference) })
    }

    /// Sets the size the size box shows, as typed or picked from its menu: kept within the scale's smallest and largest,
    /// and rounded to a half point. Part of a text selected all takes the size; the whole of a text in more than one size
    /// scales so the size shown, or the largest when none is, becomes it.
    public mutating func setShownSize(_ size: CGFloat) {
        guard let target = sizeTarget else {
            setLineWidth(points: EditorStyle.width(forShownSize: size, sizing: sizeKind))
            return
        }
        let wanted = fitted(pixels(points: size))
        if target.isPart {
            setTextRuns(target.runs.setting(wanted, in: target.range))
        } else if let reference = target.reference {
            setTextRuns(target.runs.mapping(in: target.range) { fitted($0 * wanted / reference) })
        }
    }

    /// What the size box sizes when it isn't the plain width: part of the text being typed, or text in more than one
    /// size, with the size it shows and the size it steps from, in pixels.
    private struct SizeTarget {
        var runs: TextRuns
        var range: Range<Int>
        var isPart: Bool
        /// The one size of what's selected, or at the caret; `nil` when it's more than one.
        var shown: CGFloat?
        /// The size stepping and typing start from: `shown`, else the largest selected.
        var reference: CGFloat? { shown ?? runs.largest(in: range) }
    }

    /// `nil` when the size box sizes the whole text, or anything else, by its width as it always has: text all in one size
    /// with none of it, or all of it, selected.
    private var sizeTarget: SizeTarget? {
        guard let shown, let runs = shown.textRuns else {
            return nil
        }
        let whole = 0..<runs.length
        let selected = editingText == nil ? nil : editingSelection.map { $0.clamped(to: whole) }
        if let selected, !selected.isEmpty, selected != whole {
            return SizeTarget(runs: runs, range: selected, isPart: true, shown: runs.uniformSize(in: selected))
        }
        guard !runs.isUniform else {
            return nil
        }
        let caret = selected.flatMap { $0.isEmpty ? runs.caretSize(at: $0.lowerBound) : nil }
        return SizeTarget(runs: runs, range: whole, isPart: false, shown: caret)
    }

    /// The size the size box shows for text `pixels` tall, to a hundredth of a point.
    private func points(pixels: CGFloat) -> CGFloat {
        let points = sizeKind == .note ? (pixels - 8) / scale + 8 : pixels / scale
        return (points * 100).rounded() / 100
    }

    /// The text size in pixels that the size box shows as `size`.
    private func pixels(points size: CGFloat) -> CGFloat {
        sizeKind == .note ? (size - 8) * scale + 8 : size * scale
    }

    /// `pixels` kept within the sizes the menu lists and rounded so it shows as a whole or half point.
    private func fitted(_ pixels: CGFloat) -> CGFloat {
        let choices = sizeChoices
        let size = min(max(points(pixels: pixels), choices[0]), choices[choices.count - 1])
        return self.pixels(points: (size * 2).rounded() / 2)
    }

    /// The size the menu lists after `size`, larger with `up`; `nil` past the largest or smallest.
    private func nextSize(after size: CGFloat, up: Bool) -> CGFloat? {
        let tolerance: CGFloat = 0.01
        return up ? sizeChoices.first { $0 > size + tolerance } : sizeChoices.last { $0 < size - tolerance }
    }

    /// Gives the text being typed, else the selection, these sizes. The next text's size stays as it was.
    private mutating func setTextRuns(_ runs: TextRuns) {
        if editingText != nil {
            editingText?.setTextRuns(runs)
        } else {
            selection?.setTextRuns(runs)
        }
    }

    /// Puts the text being typed, or the selection, all in the size of its largest part.
    private mutating func makeTextOneSize() {
        guard let target = editingText ?? selection, let runs = target.textRuns, let largest = runs.largest, !runs.isUniform else {
            return
        }
        setTextRuns(TextRuns(length: runs.length, size: largest))
    }

    /// Sets the width, in points, of the text being typed or the selection, and of the next annotation as the toolbar does.
    public mutating func setLineWidth(points: CGFloat) {
        let width = points * scale
        if editingText != nil {
            // Text resizes as it's typed; new text also sets the width for the next annotation.
            editingText?.setLineWidth(width)
            if editingTextIsNew {
                style.width = points
            }
            return
        }
        selection?.setLineWidth(width)
        if stylesNextAnnotation {
            style.width = points
        }
    }

    // MARK: Dashes

    /// Whether the line shown is solid, dashed or dotted: the selected arrow's or line's, else the next one's. `nil` when
    /// neither is an arrow or line.
    public var lineDash: LineDash? {
        if let shown {
            return shown.takesLineDash ? shown.lineDash : nil
        }
        return tool?.takesLineDash == true ? style.lineDash : nil
    }

    public mutating func setLineDash(_ dash: LineDash) {
        selection?.lineDash = dash
        if stylesNextAnnotation {
            style.lineDash = dash
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
        switch tool {
        case .text: return style.alignment
        case .note: return style.noteAlignment
        default: return nil
        }
    }

    public mutating func setAlignment(_ alignment: TextAlign) {
        if editingText != nil {
            editingText?.alignment = alignment
            if editingTextIsNew {
                setNextAlignment(alignment)
            }
            return
        }
        selection?.alignment = alignment
        if stylesNextAnnotation {
            setNextAlignment(alignment)
        }
    }

    /// Whether the alignment shown is a note's, which keeps its own for the next note.
    private var alignsNote: Bool {
        if let shown {
            if case .note = shown.kind { return true }
            return false
        }
        return tool == .note
    }

    private mutating func setNextAlignment(_ alignment: TextAlign) {
        if alignsNote {
            style.noteAlignment = alignment
        } else {
            style.alignment = alignment
        }
    }

    /// Where the note shown puts its text: the one being typed's, else the selection's, else the next note's.
    /// `nil` when none of them is a note.
    public var verticalAlignment: VerticalTextAlign? {
        if let shown {
            guard case .note = shown.kind else {
                return nil
            }
            return shown.verticalAlignment
        }
        return tool == .note ? style.verticalAlignment : nil
    }

    public mutating func setVerticalAlignment(_ alignment: VerticalTextAlign) {
        if editingText != nil {
            editingText?.verticalAlignment = alignment
            if editingTextIsNew {
                style.verticalAlignment = alignment
            }
            return
        }
        selection?.verticalAlignment = alignment
        if stylesNextAnnotation {
            style.verticalAlignment = alignment
        }
    }

    // MARK: Reset

    /// True when the toolbar has options to reset, which it offers for drawing tools, redaction and spotlight.
    public var offersReset: Bool {
        showsStyle || redaction != nil || spotlight != nil
    }

    /// True when `reset()` would change something: the options shown, or the ones the next annotation starts with, aren't
    /// the defaults a fresh install starts with.
    public var canReset: Bool {
        guard offersReset else {
            return false
        }
        var reset = self
        reset.reset()
        if selection?.isLocked == true {
            // The editor never restyles a locked selection, so only the rest can change.
            reset.selection = selection
        }
        return reset != self
    }

    /// Puts the options the toolbar shows back to the defaults of a fresh install, as picking each would: the text being
    /// typed's or the selection's, and the next annotation's. Saved custom colours stay. A spotlight's effect and strength
    /// are shared by every spotlight, so they go back for all of them (`sharedSpotlight` here; the editor sets the rest).
    public mutating func reset() {
        let defaults = EditorStyle()
        if showsStyle {
            switch ColorSlot(forFill: false, shown: shown, tool: tool) {
            case .note: setColor(defaults.noteColor)
            case .highlight: setColor(defaults.highlightColor)
            case .stroke, .fill, .noteText: setColor(defaults.color)
            }
            if colorRows.contains(.noteText) {
                setNoteTextColor(defaults.noteTextColor)
            }
            makeTextOneSize()
            setLineWidth(points: defaults.width)
            if showsFill {
                setFill(defaults.fill)
            }
        }
        if lineDash != nil {
            setLineDash(defaults.lineDash)
        }
        if shape != nil {
            setShape(defaults.shape)
        }
        if redaction != nil {
            setRedaction(defaults.redaction)
            setRedactionAmount(defaults.redactionAmount)
        }
        if spotlight != nil {
            setSpotlightShape(defaults.spotlight.shape)
            setSpotlightSoftEdge(defaults.spotlight.softEdge)
            selection?.restyleSpotlight { $0.effect = defaults.spotlight.effect; $0.strength = defaults.spotlight.strength }
            style.spotlight.effect = defaults.spotlight.effect
            style.spotlight.strength = defaults.spotlight.strength
            if sharedSpotlight != nil {
                sharedSpotlight?.effect = defaults.spotlight.effect
                sharedSpotlight?.strength = defaults.spotlight.strength
            }
        }
        if alignment != nil {
            setAlignment(alignsNote ? defaults.noteAlignment : defaults.alignment)
        }
        if verticalAlignment != nil {
            setVerticalAlignment(defaults.verticalAlignment)
        }
    }
}
