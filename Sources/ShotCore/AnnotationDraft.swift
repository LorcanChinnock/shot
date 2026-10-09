import CoreGraphics
import Foundation

/// What a drag with a drawing tool has drawn so far. Both editors' canvases build their drafts here, so a tool draws the
/// same in the photo and the video editor.
public enum AnnotationDraft {
    /// What the toolbar gives the next annotation.
    public struct Style: Equatable, Sendable {
        public var color: RGBA
        public var fill: RGBA?
        public var noteColor: RGBA
        public var lineWidth: CGFloat
        /// Canvas pixels, for shapes and spotlights that can be rounded.
        public var cornerRadius: CGFloat
        public var shape: BoxShape
        public var redaction: Redaction
        public var redactionAmount: CGFloat
        public var spotlight: SpotlightStyle
        public var alignment: TextAlign

        public init(
            color: RGBA, fill: RGBA?, noteColor: RGBA, lineWidth: CGFloat, cornerRadius: CGFloat, shape: BoxShape,
            redaction: Redaction, redactionAmount: CGFloat, spotlight: SpotlightStyle, alignment: TextAlign
        ) {
            self.color = color
            self.fill = fill
            self.noteColor = noteColor
            self.lineWidth = lineWidth
            self.cornerRadius = cornerRadius
            self.shape = shape
            self.redaction = redaction
            self.redactionAmount = redactionAmount
            self.spotlight = spotlight
            self.alignment = alignment
        }
    }

    /// The draft of a drag from `start` to `point` with `tool`, or `nil` for a tool that doesn't draw by dragging.
    /// `previous` is the draft the drag had drawn until now: a stroke grows from its points and the draft keeps its id.
    /// `constrain` (Shift) keeps boxes square and arrows, lines and highlighter strokes at 45° steps; `fromCenter` (Option)
    /// draws a box out from where it started. Stroke points closer than `minDistance` to the last are dropped, since the
    /// curve can't show them.
    public static func annotation(
        tool: EditorTool, from start: CGPoint, to point: CGPoint, previous: Annotation?,
        constrain: Bool, fromCenter: Bool, minDistance: CGFloat, style: Style
    ) -> Annotation? {
        let id = previous?.id ?? UUID()
        let kind: Annotation.Kind
        switch tool {
        case .select, .hand, .crop, .counter, .text:
            return nil
        case .arrow:
            kind = .arrow(from: start, to: constrain ? Geometry.snapped(from: start, to: point) : point)
        case .line:
            kind = .line(from: start, to: constrain ? Geometry.snapped(from: start, to: point) : point)
        case .shape:
            kind = .shape(style.shape, rect: box(from: start, to: point, constrain: constrain, fromCenter: fromCenter))
        case .redact:
            kind = .redaction(style.redaction, rect: box(from: start, to: point, constrain: constrain, fromCenter: fromCenter), amount: style.redactionAmount)
        case .spotlight:
            kind = .spotlight(box(from: start, to: point, constrain: constrain, fromCenter: fromCenter), style: style.spotlight)
        case .highlight:
            if constrain {
                kind = .marker([start, Geometry.snapped(from: start, to: point)])
            } else if let previous, case let .marker(drawn) = previous.kind {
                kind = .marker(Freehand.adding(point, to: drawn, minDistance: minDistance))
            } else {
                kind = .marker([start, point])
            }
        case .pen:
            let points: [CGPoint]
            if let previous, case let .freehand(drawn) = previous.kind {
                points = drawn
            } else {
                points = [start]
            }
            kind = .freehand(Freehand.adding(point, to: points, minDistance: minDistance))
        case .note:
            return note(id: id, from: start, to: point, style: style)
        }
        var shape = Annotation(id: id, kind: kind, color: style.color, lineWidth: style.lineWidth)
        if shape.supportsFill {
            shape.fill = style.fill
        }
        if shape.canRound {
            shape.cornerRadius = style.cornerRadius
        }
        return shape
    }

    /// An empty note placed by a drag from `start` to `end`, ready for its text.
    public static func note(id: UUID, from start: CGPoint, to end: CGPoint, style: Style) -> Annotation {
        var note = Annotation(id: id, kind: .note("", rect: .zero), color: style.noteColor, lineWidth: style.lineWidth)
        note.alignment = style.alignment
        note.kind = .note("", rect: NoteLayout.placementRect(from: start, to: end, fontSize: note.noteFontSize))
        return note
    }

    /// The box a drag draws: square with `constrain`, and centred on `start` with `fromCenter`.
    static func box(from start: CGPoint, to point: CGPoint, constrain: Bool, fromCenter: Bool) -> CGRect {
        var rect = constrain ? Geometry.square(from: start, to: point) : Geometry.normalized(from: start, to: point)
        if fromCenter {
            let corner = constrain ? CGPoint(x: rect.minX == start.x ? rect.maxX : rect.minX, y: rect.minY == start.y ? rect.maxY : rect.minY) : point
            rect = Geometry.normalized(from: CGPoint(x: 2 * start.x - corner.x, y: 2 * start.y - corner.y), to: corner)
        }
        return rect
    }
}
