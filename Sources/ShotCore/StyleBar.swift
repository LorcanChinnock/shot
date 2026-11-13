import CoreGraphics
import Foundation

/// What the image editor's style bar holds, from Edit › Image editor · annotate: the small floating bar beside the
/// selected mark, or at the top of the canvas for the tool's next mark.
public enum StyleBarContent: Equatable, Sendable {
    /// Colour swatches and three widths for arrows, lines, shapes, pens, text, notes, highlights and counters, with a
    /// second row for a shape's outlines and fill, or a text's or note's alignment.
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

    /// Whether the bar has a second row under its colours and widths: only for a mark with a shape, a fill or an
    /// alignment. A redaction and a spotlight have no colours, so their options fit in one row.
    public func hasSecondRow(hasShape: Bool, hasFill: Bool, hasAlignment: Bool) -> Bool {
        switch self {
        case .colorAndWidth: hasShape || hasFill || hasAlignment
        case .redaction, .spotlight: false
        }
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
        let room = CGRect(x: inset, y: inset, width: canvas.width - inset * 2, height: canvas.height - inset - floor)
        for origin in candidates {
            let frame = CGRect(origin: origin, size: bar)
            if room.contains(frame), !frame.intersects(mark) {
                return origin
            }
        }
        return CGPoint(x: x, y: inset)
    }

    /// Keeps a bar `size` long inside `length` with the inset either side, or at the inset when it can't fit.
    private static func clamp(_ value: CGFloat, size: CGFloat, within length: CGFloat) -> CGFloat {
        max(inset, min(value, length - inset - size))
    }
}
