import CoreGraphics
import CoreText
import Foundation

/// Turns strings into lines of glyphs with Core Text, in the system font, falling back to Helvetica, so text can be laid
/// out and measured. Positions within a paragraph count its UTF-16 code units.
public enum CoreTextShaper {
    /// How tall `font` is, in points.
    public static func metrics(of font: TextFont) -> TextMetrics {
        let font = ctFont(font)
        return TextMetrics(ascent: CTFontGetAscent(font), descent: CTFontGetDescent(font), leading: CTFontGetLeading(font))
    }

    /// `string` as one line, however wide, in `font` and `color`.
    public static func line(_ string: String, font: TextFont, color: RGBA) -> CoreTextLine {
        CoreTextLine(CTLineCreateWithAttributedString(attributed(string, font: font, color: color)))
    }

    /// `string` as one line in `color`, each part in its font: `fonts` runs from the start, each with its length in UTF-16
    /// code units, and covers the string.
    public static func line(_ string: String, fonts: [(length: Int, font: TextFont)], color: RGBA) -> CoreTextLine {
        CoreTextLine(CTLineCreateWithAttributedString(attributed(string, fonts: fonts, color: color)))
    }

    /// `string`, one paragraph with no line breaks in it, ready to be broken into lines.
    public static func paragraph(_ string: String, font: TextFont, color: RGBA) -> CoreTextParagraph {
        CoreTextParagraph(attributed(string, font: font, color: color))
    }

    /// `string`, one paragraph with no line breaks in it, each part in its font as `line(_:fonts:color:)` takes them.
    public static func paragraph(_ string: String, fonts: [(length: Int, font: TextFont)], color: RGBA) -> CoreTextParagraph {
        CoreTextParagraph(attributed(string, fonts: fonts, color: color))
    }

    private static func ctFont(_ font: TextFont) -> CTFont {
        let regular = CTFontCreateUIFontForLanguage(.system, font.size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, font.size, nil)
        guard font.bold else {
            return regular
        }
        return CTFontCreateCopyWithSymbolicTraits(regular, font.size, nil, .traitBold, .traitBold) ?? regular
    }

    private static func attributed(_ string: String, font: TextFont, color: RGBA) -> CFAttributedString {
        let attributes = [kCTFontAttributeName: ctFont(font), kCTForegroundColorAttributeName: color.cgColor] as CFDictionary
        return CFAttributedStringCreate(nil, string as CFString, attributes)
    }

    private static func attributed(_ string: String, fonts: [(length: Int, font: TextFont)], color: RGBA) -> CFAttributedString {
        guard fonts.count > 1, let text = CFAttributedStringCreateMutable(nil, 0) else {
            return attributed(string, font: fonts.first?.font ?? TextFont(size: 12), color: color)
        }
        CFAttributedStringReplaceString(text, CFRange(location: 0, length: 0), string as CFString)
        let length = CFAttributedStringGetLength(text)
        CFAttributedStringSetAttribute(text, CFRange(location: 0, length: length), kCTForegroundColorAttributeName, color.cgColor)
        var start = 0
        for (count, font) in fonts where start < length {
            let range = CFRange(location: start, length: min(count, length - start))
            CFAttributedStringSetAttribute(text, range, kCTFontAttributeName, ctFont(font))
            start += count
        }
        return text
    }
}

/// A run of shaped glyphs: a `CTLine`, with its measurements.
public struct CoreTextLine {
    public let line: CTLine
    /// Its typographic width, trailing whitespace included.
    public let width: CGFloat
    /// How far its tallest glyph reaches above the baseline and its lowest below.
    public let ascent: CGFloat
    public let descent: CGFloat

    init(_ line: CTLine) {
        self.line = line
        var ascent: CGFloat = 0, descent: CGFloat = 0
        width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        self.ascent = ascent
        self.descent = descent
    }

    public var trailingWhitespaceWidth: CGFloat { CTLineGetTrailingWhitespaceWidth(line) }
}

/// A paragraph broken into lines by a `CTTypesetter`, made when it's first asked for a break. Each break is the length
/// of the line starting at `start`.
public final class CoreTextParagraph {
    private let text: CFAttributedString
    private lazy var typesetter = CTTypesetterCreateWithAttributedString(text)

    init(_ text: CFAttributedString) {
        self.text = text
    }

    /// Its length in UTF-16 code units.
    var length: Int { CFAttributedStringGetLength(text) }

    /// How much from `start` fits in `width`, ending at a word break where there is one.
    func lineBreak(from start: Int, width: CGFloat) -> Int {
        CTTypesetterSuggestLineBreak(typesetter, start, width)
    }

    /// How much from `start` fits in `width`, ending between any two characters.
    func clusterBreak(from start: Int, width: CGFloat) -> Int {
        CTTypesetterSuggestClusterBreak(typesetter, start, width)
    }

    /// The `count` code units from `start` as a line.
    func line(from start: Int, count: Int) -> CoreTextLine {
        CoreTextLine(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
    }
}
