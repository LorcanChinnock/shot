import Foundation

/// Turns strings into lines of glyphs, so text can be laid out and measured with whichever library the platform has.
/// Positions within a paragraph count its UTF-16 code units. A shaper is handed to any thread that lays out text.
public protocol TextShaper: Sendable {
    /// How tall `font` is, in points.
    func metrics(of font: TextFont) -> TextMetrics
    /// `string` as one line, however wide, in `font` and `color`.
    func line(_ string: String, font: TextFont, color: RGBA) -> any ShapedLine
    /// `string`, one paragraph with no line breaks in it, ready to be broken into lines.
    func paragraph(_ string: String, font: TextFont, color: RGBA) -> any ShapedParagraph
}

/// The system's interface font at `size` points, bold or regular.
public struct TextFont: Hashable, Sendable {
    public var size: CGFloat
    public var bold: Bool

    public init(size: CGFloat, bold: Bool = false) {
        self.size = size
        self.bold = bold
    }
}

public struct TextMetrics: Equatable, Sendable {
    public var ascent: CGFloat
    public var descent: CGFloat
    public var leading: CGFloat

    public init(ascent: CGFloat, descent: CGFloat, leading: CGFloat) {
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
    }

    /// The distance from one baseline to the next, rounded up to a whole point.
    public var lineHeight: CGFloat { (ascent + descent + leading).rounded(.up) }
}

/// A paragraph that can be broken into lines. Each break is the length of the line starting at `start`.
public protocol ShapedParagraph {
    /// Its length in UTF-16 code units.
    var length: Int { get }
    /// How much from `start` fits in `width`, ending at a word break where there is one.
    func lineBreak(from start: Int, width: CGFloat) -> Int
    /// How much from `start` fits in `width`, ending between any two characters.
    func clusterBreak(from start: Int, width: CGFloat) -> Int
    /// The `count` code units from `start` as a line.
    func line(from start: Int, count: Int) -> any ShapedLine
}

/// A run of shaped glyphs; only the canvas of the shaper that made it can draw it.
public protocol ShapedLine {
    /// Its typographic width, trailing whitespace included.
    var width: CGFloat { get }
    var trailingWhitespaceWidth: CGFloat { get }
    /// How far its tallest glyph reaches above the baseline and its lowest below.
    var ascent: CGFloat { get }
    var descent: CGFloat { get }
}
