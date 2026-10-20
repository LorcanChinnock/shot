import Foundation

/// A text annotation's lines in the bold system font, one per paragraph.
public struct TextLayout {
    public let lines: [any ShapedLine]
    public let lineHeight: CGFloat
    public let ascent: CGFloat
    public let size: CGSize

    public init(string: String, fontSize: CGFloat, color: RGBA, shaper: any TextShaper) {
        let font = TextFont(size: fontSize, bold: true)
        let parts = string.isEmpty ? [" "] : string.components(separatedBy: "\n")
        lines = parts.map { shaper.line($0, font: font, color: color) }
        let metrics = shaper.metrics(of: font)
        ascent = metrics.ascent
        lineHeight = metrics.lineHeight
        let width = lines.map(\.width).max() ?? 0
        size = CGSize(width: width.rounded(.up), height: lineHeight * CGFloat(lines.count))
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
    public let lines: [any ShapedLine]
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

    public init(string: String, rect: CGRect, fontSize: CGFloat, color: RGBA, verticalAlignment: VerticalTextAlign = .top, shaper: any TextShaper) {
        self.fontSize = fontSize
        self.verticalAlignment = verticalAlignment
        padding = Self.padding(fontSize: fontSize)
        cornerRadius = fontSize * 0.35
        shadowOffset = fontSize * 0.15
        shadowBlur = fontSize * 0.5
        fill = color.noteFill
        ink = fill.contrastingInk

        let width = max(rect.width, Self.minWidth(fontSize: fontSize))
        let wrapWidth = width - padding * 2
        let font = TextFont(size: fontSize)
        var lines: [any ShapedLine] = []
        for paragraph in string.components(separatedBy: "\n") {
            let text = shaper.paragraph(paragraph, font: font, color: ink)
            guard text.length > 0 else {
                lines.append(shaper.line(paragraph, font: font, color: ink))
                continue
            }
            var start = 0
            while start < text.length {
                var count = text.lineBreak(from: start, width: wrapWidth)
                var line = text.line(from: start, count: count)
                // A word wider than the note has no word break to use, so break it between characters.
                if line.width - line.trailingWhitespaceWidth > wrapWidth {
                    count = max(1, text.clusterBreak(from: start, width: wrapWidth))
                    line = text.line(from: start, count: count)
                }
                lines.append(line)
                start += max(1, count)
            }
        }
        self.lines = lines
        let metrics = shaper.metrics(of: font)
        ascent = metrics.ascent
        lineHeight = metrics.lineHeight
        let textHeight = lineHeight * CGFloat(lines.count) + padding * 2
        frame = CGRect(x: rect.minX, y: rect.minY, width: width, height: max(rect.height, textHeight))
    }
}
