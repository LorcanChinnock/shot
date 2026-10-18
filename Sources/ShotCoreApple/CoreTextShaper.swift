import CoreGraphics
import CoreText
import Foundation

/// A `TextShaper` on Core Text, with the system font, falling back to Helvetica.
public struct CoreTextShaper: TextShaper {
    public init() {}

    public func metrics(of font: TextFont) -> TextMetrics {
        let font = ctFont(font)
        return TextMetrics(ascent: CTFontGetAscent(font), descent: CTFontGetDescent(font), leading: CTFontGetLeading(font))
    }

    public func line(_ string: String, font: TextFont, color: RGBA) -> any ShapedLine {
        CoreTextLine(CTLineCreateWithAttributedString(attributed(string, font: font, color: color)))
    }

    public func paragraph(_ string: String, font: TextFont, color: RGBA) -> any ShapedParagraph {
        CoreTextParagraph(attributed(string, font: font, color: color))
    }

    private func ctFont(_ font: TextFont) -> CTFont {
        let regular = CTFontCreateUIFontForLanguage(.system, font.size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, font.size, nil)
        guard font.bold else {
            return regular
        }
        return CTFontCreateCopyWithSymbolicTraits(regular, font.size, nil, .traitBold, .traitBold) ?? regular
    }

    private func attributed(_ string: String, font: TextFont, color: RGBA) -> CFAttributedString {
        let attributes = [kCTFontAttributeName: ctFont(font), kCTForegroundColorAttributeName: color.cgColor] as CFDictionary
        return CFAttributedStringCreate(nil, string as CFString, attributes)
    }
}

/// A `CTLine`, which `CGCanvas` draws.
public struct CoreTextLine: ShapedLine {
    public let line: CTLine
    public let width: CGFloat
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

/// A paragraph broken into lines by a `CTTypesetter`, made when it's first asked for a break.
final class CoreTextParagraph: ShapedParagraph {
    private let text: CFAttributedString
    private lazy var typesetter = CTTypesetterCreateWithAttributedString(text)

    init(_ text: CFAttributedString) {
        self.text = text
    }

    var length: Int { CFAttributedStringGetLength(text) }

    func lineBreak(from start: Int, width: CGFloat) -> Int {
        CTTypesetterSuggestLineBreak(typesetter, start, width)
    }

    func clusterBreak(from start: Int, width: CGFloat) -> Int {
        CTTypesetterSuggestClusterBreak(typesetter, start, width)
    }

    func line(from start: Int, count: Int) -> any ShapedLine {
        CoreTextLine(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
    }
}
