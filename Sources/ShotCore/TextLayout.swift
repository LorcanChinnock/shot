import Foundation

/// A text annotation's lines in the bold system font: one per paragraph, or wrapped to `width` when it has one.
public struct TextLayout {
    public let lines: [CoreTextLine]
    public let lineHeight: CGFloat
    public let ascent: CGFloat
    /// As wide as the longest line, or `width` for wrapped text, so its lines align across the whole box.
    public let size: CGSize

    /// The narrowest a text box wraps to.
    public static func minWidth(fontSize: CGFloat) -> CGFloat { fontSize * 2 }

    /// Where a press at `start` released at `end` puts text: a click, a move under `threshold`, places text as wide as
    /// what's typed; a drag places a box from its left edge, as wide as the drag, that the text wraps in.
    public static func placement(from start: CGPoint, to end: CGPoint, fontSize: CGFloat, threshold: CGFloat) -> (origin: CGPoint, width: CGFloat?) {
        guard hypot(end.x - start.x, end.y - start.y) >= threshold else {
            return (start, nil)
        }
        let rect = Geometry.normalized(from: start, to: end)
        return (rect.origin, max(rect.width, minWidth(fontSize: fontSize)))
    }

    public init(string: String, fontSize: CGFloat, color: RGBA, width: CGFloat? = nil) {
        let font = TextFont(size: fontSize, bold: true)
        if let width {
            let wrapWidth = max(width, Self.minWidth(fontSize: fontSize))
            lines = Self.wrapped(string, width: wrapWidth, font: font, color: color)
        } else {
            let parts = string.isEmpty ? [" "] : string.components(separatedBy: "\n")
            lines = parts.map { CoreTextShaper.line($0, font: font, color: color) }
        }
        let metrics = CoreTextShaper.metrics(of: font)
        ascent = metrics.ascent
        lineHeight = metrics.lineHeight
        let lineWidth = width.map { max($0, Self.minWidth(fontSize: fontSize)) } ?? (lines.map(\.width).max() ?? 0)
        size = CGSize(width: lineWidth.rounded(.up), height: lineHeight * CGFloat(lines.count))
    }

    /// `string`'s paragraphs broken into lines no wider than `width`, between words where it can and between characters
    /// for a word wider than that.
    static func wrapped(_ string: String, width: CGFloat, font: TextFont, color: RGBA) -> [CoreTextLine] {
        var lines: [CoreTextLine] = []
        for paragraph in string.components(separatedBy: "\n") {
            let text = CoreTextShaper.paragraph(paragraph, font: font, color: color)
            guard text.length > 0 else {
                lines.append(CoreTextShaper.line(paragraph, font: font, color: color))
                continue
            }
            var start = 0
            while start < text.length {
                var count = text.lineBreak(from: start, width: width)
                var line = text.line(from: start, count: count)
                if line.width - line.trailingWhitespaceWidth > width {
                    count = max(1, text.clusterBreak(from: start, width: width))
                    line = text.line(from: start, count: count)
                }
                lines.append(line)
                start += max(1, count)
            }
        }
        return lines
    }
}

/// A sticky note's text wrapped to its width, with the paper around it. Image pixels, top-left origin.
public struct NoteLayout {
    public let fontSize: CGFloat
    public let padding: CGFloat
    public let cornerRadius: CGFloat
    public let shadowOffset: CGFloat
    public let shadowBlur: CGFloat
    public let fill: RGBA
    public let ink: RGBA
    public let lines: [CoreTextLine]
    public let lineHeight: CGFloat
    public let ascent: CGFloat
    /// The paper: the rect's origin and width (at least `minWidth`), and at least tall enough for the text.
    public let frame: CGRect
    public let verticalAlignment: VerticalTextAlign

    public var textRect: CGRect { frame.insetBy(dx: padding, dy: padding) }

    /// The part of `textRect` from the top of the first line down: the spare height `verticalAlignment` puts above the
    /// text is left off.
    public var alignedTextRect: CGRect {
        let text = textRect
        let spare = max(0, text.height - lineHeight * CGFloat(lines.count))
        return CGRect(x: text.minX, y: text.minY + spare * verticalAlignment.fraction, width: text.width, height: text.height - spare * verticalAlignment.fraction)
    }

    public static func padding(fontSize: CGFloat) -> CGFloat { fontSize * 0.6 }
    public static func minWidth(fontSize: CGFloat) -> CGFloat { fontSize * 3 + padding(fontSize: fontSize) * 2 }
    public static func defaultWidth(fontSize: CGFloat) -> CGFloat { fontSize * 10 }

    /// The note rect for a press at `start` released at `end`: a click places a default-width note, a drag sets its size.
    public static func placementRect(from start: CGPoint, to end: CGPoint, fontSize: CGFloat) -> CGRect {
        guard abs(end.x - start.x) >= 4 || abs(end.y - start.y) >= 4 else {
            return CGRect(origin: start, size: CGSize(width: defaultWidth(fontSize: fontSize), height: 0))
        }
        let rect = Geometry.normalized(from: start, to: end)
        return CGRect(x: rect.minX, y: rect.minY, width: max(rect.width, minWidth(fontSize: fontSize)), height: rect.height)
    }

    /// `textColor` colours the text; `nil` picks black or white, whichever reads better on the paper.
    public init(string: String, rect: CGRect, fontSize: CGFloat, color: RGBA, textColor: RGBA? = nil, verticalAlignment: VerticalTextAlign = .top) {
        self.fontSize = fontSize
        self.verticalAlignment = verticalAlignment
        padding = Self.padding(fontSize: fontSize)
        cornerRadius = fontSize * 0.35
        shadowOffset = fontSize * 0.15
        shadowBlur = fontSize * 0.5
        fill = color.noteFill
        ink = textColor ?? fill.contrastingInk

        let width = max(rect.width, Self.minWidth(fontSize: fontSize))
        let wrapWidth = width - padding * 2
        let font = TextFont(size: fontSize)
        let lines = TextLayout.wrapped(string, width: wrapWidth, font: font, color: ink)
        self.lines = lines
        let metrics = CoreTextShaper.metrics(of: font)
        ascent = metrics.ascent
        lineHeight = metrics.lineHeight
        let textHeight = lineHeight * CGFloat(lines.count) + padding * 2
        frame = CGRect(x: rect.minX, y: rect.minY, width: width, height: max(rect.height, textHeight))
    }
}
