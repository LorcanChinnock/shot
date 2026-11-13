import CoreGraphics
import Foundation

/// What the image editor's style bar holds, from Edit › Image editor · annotate: the small floating bar beside the
/// selected mark, or at the top of the canvas for the tool's next mark.
public enum StyleBarContent: Equatable, Sendable {
    /// Rows of colour swatches on the left for arrows, lines, shapes, pens, text, notes, highlights and counters, with the
    /// width or text size, a shape's outlines and a text's alignment on the right (`AnnotationPalette.colorRows` and
    /// `controlRows`).
    case colorAndWidth
    /// Blur or pixelate and the amount, in one row.
    case redaction
    /// The spotlight's shape, its dim or blur, its strength and its soft edge, in one row.
    case spotlight

    /// What the bar shows, in the same order the options row used: colour and width first, then a redaction and a
    /// spotlight. `nil` hides the bar, as for the select tool with nothing or an image selected, and in crop mode, where
    /// the crop bar takes its place.
    public static func content(showsStyle: Bool, tool: EditorTool, showsRedaction: Bool, showsSpotlight: Bool) -> StyleBarContent? {
        if tool == .crop {
            return nil
        }
        if showsStyle {
            return .colorAndWidth
        }
        if showsRedaction {
            return .redaction
        }
        if showsSpotlight {
            return .spotlight
        }
        return nil
    }
}

/// The colours the bar offers: every preset, red, orange, yellow, green, blue, black and white. The bar's rainbow swatch
/// picks any other.
public enum StyleBarSwatches {
    public static let colors: [RGBA] = RGBA.presets

    /// Whether `color` is one of the bar's swatches, so one shows as chosen.
    public static func contains(_ color: RGBA) -> Bool { colors.contains(color) }
}

/// Where the style bar goes on the canvas, in view points with y running down.
public enum StyleBarPlacement {
    /// The space between the bar and the mark it styles.
    public static let gap: CGFloat = 10
    /// The space the bar keeps from the canvas's edges.
    public static let inset: CGFloat = 12
    /// How far around a mark's outline the canvas reaches, so the bar clears its selection handles too.
    public static let markPadding: CGFloat = 8

    /// The bar's top-left corner. With no mark, the bar sits at the top centre of the canvas. With one, it sits centred
    /// above the mark, or else below it, to its right or to its left, whichever comes first with room, sliding along the
    /// edge it sits on to stay inside the canvas. Only a mark that leaves no room on any side is covered, by the bar at
    /// the top of the canvas. `bottom` is how much of the canvas's foot the zoom control and hint take, which the bar
    /// keeps clear of as it does the other edges.
    public static func origin(bar: CGSize, mark: CGRect?, in canvas: CGSize, bottom: CGFloat = 0) -> CGPoint {
        let centredX = clamp((canvas.width - bar.width) / 2, size: bar.width, within: canvas.width)
        guard let mark, !mark.isNull, !mark.isInfinite else {
            return CGPoint(x: centredX, y: inset)
        }
        let x = clamp(mark.midX - bar.width / 2, size: bar.width, within: canvas.width)
        let floor = max(inset, bottom)
        let y = max(inset, min(mark.midY - bar.height / 2, canvas.height - floor - bar.height))
        let candidates = [
            CGPoint(x: x, y: mark.minY - gap - bar.height),
            CGPoint(x: x, y: mark.maxY + gap),
            CGPoint(x: mark.maxX + gap, y: y),
            CGPoint(x: mark.minX - gap - bar.width, y: y),
        ]
        // A bar wider than the room between the side insets may use them, as `clamp` centres it.
        let side = min(inset, max(0, (canvas.width - bar.width) / 2))
        let room = CGRect(x: side, y: inset, width: canvas.width - side * 2, height: canvas.height - inset - floor)
        for origin in candidates {
            let frame = CGRect(origin: origin, size: bar)
            if room.contains(frame), !frame.intersects(mark) {
                return origin
            }
        }
        return CGPoint(x: x, y: inset)
    }

    /// Keeps a bar `size` long inside `length` with the inset either side. One that fits only by going into the insets is
    /// centred, so all of it shows, and one longer than `length` stays at the inset.
    private static func clamp(_ value: CGFloat, size: CGFloat, within length: CGFloat) -> CGFloat {
        if size > length - inset * 2, size <= length {
            return (length - size) / 2
        }
        return max(inset, min(value, length - inset - size))
    }
}

/// A row of colours in the style bar, each named on its left. Every row has the same swatches: the seven presets and the
/// custom colour, then transparent where `offersTransparent`.
public enum StyleBarColorRow: Equatable, Sendable {
    /// The colour of an arrow, line, pen or highlighter stroke, named Line.
    case line
    /// A shape's outline, named Line. Transparent leaves only its fill.
    case outline
    /// A shape's inside, named Fill. Transparent leaves it unfilled.
    case fill
    /// A text's colour, named Text.
    case text
    /// A note's text, named Text. With no swatch chosen it's black or white, whichever reads better on the paper.
    case noteText
    /// A note's paper, named Background.
    case paper
    /// A counter's disc, named Fill, behind its white number.
    case counter

    /// The rows for a mark of `kind`, top to bottom: Line above Fill for a shape, Text above Background for a note.
    public static func rows(for kind: Annotation.Kind) -> [StyleBarColorRow] {
        switch kind {
        case .shape: [.outline, .fill]
        case .text: [.text]
        case .note: [.noteText, .paper]
        case .counter: [.counter]
        case .arrow, .line, .freehand, .marker, .highlight: [.line]
        case .pixelate, .blur, .spotlight, .image: []
        }
    }

    /// The rows for the next mark `tool` draws.
    public static func rows(for tool: EditorTool) -> [StyleBarColorRow] {
        switch tool {
        case .shape: [.outline, .fill]
        case .text: [.text]
        case .note: [.noteText, .paper]
        case .counter: [.counter]
        case .arrow, .line, .pen, .highlight: [.line]
        case .select, .hand, .spotlight, .redact, .crop: []
        }
    }

    /// The row that shows the main colour (`Annotation.color`) of the next mark `tool` draws: a shape's outline, a note's
    /// paper, else its only row.
    public static func colorRow(for tool: EditorTool) -> StyleBarColorRow? {
        switch tool {
        case .shape: .outline
        case .note: .paper
        default: rows(for: tool).first
        }
    }

    /// Whether the row ends with a transparent swatch: only where the mark keeps another part that shows, a shape's
    /// outline and fill and a note's paper. Elsewhere transparent would make the mark vanish.
    public var offersTransparent: Bool {
        switch self {
        case .outline, .fill, .paper: true
        case .line, .text, .noteText, .counter: false
        }
    }

    /// Whether this row's transparent swatch clears the colour to `nil` rather than to `RGBA.clear`: only a fill, which
    /// has always kept none that way.
    public var clearsToNone: Bool { self == .fill }
}

/// A control on the right of the style bar's colour rows.
public enum StyleBarControl: Equatable, Sendable {
    /// Thinner and thicker, or for text, a note or a counter, smaller and larger, with the size between them.
    case width
    /// A shape's five outlines.
    case outline
    /// Left, centre or right.
    case alignment
    /// A note's text at the top, middle or bottom.
    case verticalAlignment
}

/// What's typed in the style bar's size box.
public enum SizeInput {
    /// The size typed, with a comma or a point before any decimals and an optional "pt" after; `nil` for anything that
    /// isn't a positive number.
    public static func parse(_ text: String) -> CGFloat? {
        var trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasSuffix("pt") {
            trimmed = String(trimmed.dropLast(2)).trimmingCharacters(in: .whitespaces)
        }
        guard let number = Double(trimmed.replacingOccurrences(of: ",", with: ".")), number.isFinite, number > 0 else {
            return nil
        }
        return CGFloat(number)
    }
}
