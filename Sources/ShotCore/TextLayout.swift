import Foundation

/// A text annotation's lines in the bold system font: one per paragraph, or wrapped to `width` when it has one.
public struct TextLayout {
    public let lines: [CoreTextLine]
    /// The height and ascent of a line in `fontSize`; a line with larger text in it is taller.
    public let lineHeight: CGFloat
    public let ascent: CGFloat
    /// How far down from the top each line's baseline is, which mixed sizes push down by their tallest text.
    public let baselines: [CGFloat]
    /// As wide as the longest line, or `width` for wrapped text, so its lines align across the whole box.
    public let size: CGSize

    /// The narrowest a text box wraps to.
    public static func minWidth(fontSize: CGFloat) -> CGFloat { fontSize * 2 }

    /// Where a press at `start` released at `end` puts text, and its size. A click, a move under `threshold`, places text
    /// in `fontSize` as wide as what's typed. A drag places a box from its top left that the text wraps in, as wide as the
    /// drag, with its height as one line of text, so the size is the one whose line is that tall. That size is a whole
    /// number of points, `scale` pixels each, within the text sizes the style bar offers.
    public static func placement(
        from start: CGPoint, to end: CGPoint, fontSize: CGFloat, threshold: CGFloat, scale: CGFloat
    ) -> (origin: CGPoint, width: CGFloat?, fontSize: CGFloat) {
        guard hypot(end.x - start.x, end.y - start.y) >= threshold else {
            return (start, nil, fontSize)
        }
        let rect = Geometry.normalized(from: start, to: end)
        let sizes = EditorStyle.widths.map { EditorStyle.shownSize(width: $0, sizing: .text) }
        let points = (rect.height / lineHeightPerPoint / scale).rounded()
        let dragged = min(max(points, sizes[0]), sizes[sizes.count - 1]) * scale
        return (rect.origin, max(rect.width, minWidth(fontSize: dragged)), dragged)
    }

    /// How tall a line of text is for each point of its size.
    public static let lineHeightPerPoint: CGFloat = CoreTextShaper.metrics(of: TextFont(size: 100, bold: true)).lineHeight / 100

    /// How tall a line of text in `fontSize` is.
    public static func lineHeight(fontSize: CGFloat) -> CGFloat {
        CoreTextShaper.metrics(of: TextFont(size: fontSize, bold: true)).lineHeight
    }

    /// `runs` gives each part of the text its own size, in pixels; `nil` sets it all in `fontSize`.
    public init(string: String, fontSize: CGFloat, color: RGBA, width: CGFloat? = nil, runs: TextRuns? = nil) {
        let font = TextFont(size: fontSize, bold: true)
        let sizes = Self.sizes(of: string, runs: runs, fontSize: fontSize)
        let laid: [LaidLine]
        if let width {
            let wrapWidth = max(width, Self.minWidth(fontSize: fontSize))
            laid = Self.wrapped(string, width: wrapWidth, sizes: sizes, fallback: fontSize, bold: true, color: color)
        } else if string.isEmpty {
            laid = [LaidLine(CoreTextShaper.line(" ", font: font, color: color), fonts: [font])]
        } else {
            laid = Self.paragraphs(of: string).map { paragraph in
                let fonts = Self.fonts(sizes.runs(in: paragraph.range), bold: true)
                guard !fonts.isEmpty else {
                    return Self.emptyLine(at: paragraph.range.lowerBound, sizes: sizes, fallback: fontSize, bold: true, color: color)
                }
                return LaidLine(CoreTextShaper.line(paragraph.text, fonts: fonts, color: color), fonts: fonts.map(\.font))
            }
        }
        lines = laid.map(\.line)
        let metrics = CoreTextShaper.metrics(of: font)
        ascent = metrics.ascent
        lineHeight = metrics.lineHeight
        let stacked = Self.stack(laid)
        baselines = stacked.baselines
        let lineWidth = width.map { max($0, Self.minWidth(fontSize: fontSize)) } ?? (lines.map(\.width).max() ?? 0)
        size = CGSize(width: lineWidth.rounded(.up), height: stacked.height)
    }

    /// A line and the fonts in it, which set how tall it is.
    struct LaidLine {
        let line: CoreTextLine
        let fonts: [TextFont]

        init(_ line: CoreTextLine, fonts: [TextFont]) {
            self.line = line
            self.fonts = fonts
        }
    }

    /// Each line's baseline from the top, and the height of them all. A line is as tall as the tallest of its fonts
    /// reaches above the baseline and the deepest reaches below it, rounded up to a whole point, so text all in one size
    /// steps down by its font's `lineHeight`.
    static func stack(_ lines: [LaidLine]) -> (baselines: [CGFloat], height: CGFloat) {
        var top: CGFloat = 0
        var baselines: [CGFloat] = []
        for line in lines {
            let metrics = line.fonts.map(CoreTextShaper.metrics(of:))
            let ascent = metrics.map(\.ascent).max() ?? 0
            let below = metrics.map { $0.descent + $0.leading }.max() ?? 0
            baselines.append(top + ascent)
            top += (ascent + below).rounded(.up)
        }
        return (baselines, top)
    }

    /// The runs of `string`, or all of it in `fontSize` when `runs` doesn't cover it.
    static func sizes(of string: String, runs: TextRuns?, fontSize: CGFloat) -> TextRuns {
        let length = string.utf16.count
        guard let runs, runs.length == length else {
            return TextRuns(length: length, size: fontSize)
        }
        return runs
    }

    /// An empty paragraph at `offset`, as tall as the line break that ends it, or the text before it at the end;
    /// `fallback` tall when there's no text.
    static func emptyLine(at offset: Int, sizes: TextRuns, fallback: CGFloat, bold: Bool, color: RGBA) -> LaidLine {
        let font = TextFont(size: sizes.size(at: offset) ?? sizes.caretSize(at: offset) ?? fallback, bold: bold)
        return LaidLine(CoreTextShaper.line("", font: font, color: color), fonts: [font])
    }

    /// The fonts for `runs`, each with its length.
    static func fonts(_ runs: [TextRun], bold: Bool) -> [(length: Int, font: TextFont)] {
        runs.map { ($0.length, TextFont(size: $0.size, bold: bold)) }
    }

    /// `string` split at its line breaks, each part with where it sits in the whole, in UTF-16 code units.
    static func paragraphs(of string: String) -> [(text: String, range: Range<Int>)] {
        var start = 0
        return string.components(separatedBy: "\n").map { paragraph in
            let length = paragraph.utf16.count
            defer { start += length + 1 }
            return (paragraph, start..<(start + length))
        }
    }

    /// `string`'s paragraphs broken into lines no wider than `width`, between words where it can and between characters
    /// for a word wider than that, each part in its size from `sizes`. An empty paragraph is as tall as the line break
    /// that ends it.
    static func wrapped(_ string: String, width: CGFloat, sizes: TextRuns, fallback: CGFloat, bold: Bool, color: RGBA) -> [LaidLine] {
        var lines: [LaidLine] = []
        for (paragraph, range) in paragraphs(of: string) {
            let fonts = fonts(sizes.runs(in: range), bold: bold)
            guard !fonts.isEmpty else {
                lines.append(emptyLine(at: range.lowerBound, sizes: sizes, fallback: fallback, bold: bold, color: color))
                continue
            }
            let text = CoreTextShaper.paragraph(paragraph, fonts: fonts, color: color)
            var start = 0
            while start < text.length {
                var count = text.lineBreak(from: start, width: width)
                var line = text.line(from: start, count: count)
                if line.width - line.trailingWhitespaceWidth > width {
                    count = max(1, text.clusterBreak(from: start, width: width))
                    line = text.line(from: start, count: count)
                }
                let inLine = sizes.runs(in: (range.lowerBound + start)..<(range.lowerBound + start + max(1, count)))
                lines.append(LaidLine(line, fonts: Self.fonts(inLine, bold: bold).map(\.font)))
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
    /// The height and ascent of a line in `fontSize`; a line with larger text in it is taller.
    public let lineHeight: CGFloat
    public let ascent: CGFloat
    /// How far down from the top of the text each line's baseline is.
    public let baselines: [CGFloat]
    /// How tall the lines are together.
    public let textHeight: CGFloat
    /// The paper: the rect's origin and width (at least `minWidth`), and at least tall enough for the text.
    public let frame: CGRect
    public let verticalAlignment: VerticalTextAlign

    public var textRect: CGRect { frame.insetBy(dx: padding, dy: padding) }

    /// The part of `textRect` from the top of the first line down: the spare height `verticalAlignment` puts above the
    /// text is left off.
    public var alignedTextRect: CGRect {
        let text = textRect
        let spare = max(0, text.height - textHeight)
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

    /// `textColor` colours the text; `nil` picks black or white, whichever reads better on the paper. `runs` gives each
    /// part of the text its own size, in pixels; `nil` sets it all in `fontSize`, which the padding follows either way.
    public init(
        string: String, rect: CGRect, fontSize: CGFloat, color: RGBA, textColor: RGBA? = nil, verticalAlignment: VerticalTextAlign = .top,
        runs: TextRuns? = nil
    ) {
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
        let sizes = TextLayout.sizes(of: string, runs: runs, fontSize: fontSize)
        let laid = TextLayout.wrapped(string, width: wrapWidth, sizes: sizes, fallback: fontSize, bold: false, color: ink)
        lines = laid.map(\.line)
        let metrics = CoreTextShaper.metrics(of: font)
        ascent = metrics.ascent
        lineHeight = metrics.lineHeight
        let stacked = TextLayout.stack(laid)
        baselines = stacked.baselines
        textHeight = stacked.height
        frame = CGRect(x: rect.minX, y: rect.minY, width: width, height: max(rect.height, textHeight + padding * 2))
    }
}
