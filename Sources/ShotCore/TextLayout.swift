import CoreGraphics
import CoreText
import Foundation

public struct TextLayout {
    public let lines: [CTLine]
    public let lineHeight: CGFloat
    public let ascent: CGFloat
    public let size: CGSize

    public init(string: String, fontSize: CGFloat, color: RGBA) {
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let bold = CTFontCreateCopyWithSymbolicTraits(font, fontSize, nil, .traitBold, .traitBold) ?? font
        let attributes = [kCTFontAttributeName: bold, kCTForegroundColorAttributeName: color.cgColor] as CFDictionary
        let parts = string.isEmpty ? [" "] : string.components(separatedBy: "\n")
        lines = parts.map { CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, $0 as CFString, attributes)) }
        ascent = CTFontGetAscent(bold)
        lineHeight = (ascent + CTFontGetDescent(bold) + CTFontGetLeading(bold)).rounded(.up)
        let width = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
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
    public let lines: [CTLine]
    public let lineHeight: CGFloat
    public let ascent: CGFloat
    /// The paper: the rect's origin and width (at least `minWidth`), and at least tall enough for the text.
    public let frame: CGRect

    public var textRect: CGRect { frame.insetBy(dx: padding, dy: padding) }

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

    public init(string: String, rect: CGRect, fontSize: CGFloat, color: RGBA) {
        self.fontSize = fontSize
        padding = Self.padding(fontSize: fontSize)
        cornerRadius = fontSize * 0.35
        shadowOffset = fontSize * 0.15
        shadowBlur = fontSize * 0.5
        fill = color.noteFill
        ink = fill.contrastingInk

        let width = max(rect.width, Self.minWidth(fontSize: fontSize))
        let wrapWidth = Double(width - padding * 2)
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: ink.cgColor] as CFDictionary
        var lines: [CTLine] = []
        for paragraph in string.components(separatedBy: "\n") {
            let text = CFAttributedStringCreate(nil, paragraph as CFString, attributes)!
            let length = CFAttributedStringGetLength(text)
            guard length > 0 else {
                lines.append(CTLineCreateWithAttributedString(text))
                continue
            }
            let typesetter = CTTypesetterCreateWithAttributedString(text)
            var start = 0
            while start < length {
                var count = CTTypesetterSuggestLineBreak(typesetter, start, wrapWidth)
                var line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                // A word wider than the note has no word break to use, so break it between characters.
                if CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line) > wrapWidth {
                    count = max(1, CTTypesetterSuggestClusterBreak(typesetter, start, wrapWidth))
                    line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                }
                lines.append(line)
                start += max(1, count)
            }
        }
        self.lines = lines
        ascent = CTFontGetAscent(font)
        lineHeight = (ascent + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded(.up)
        let textHeight = lineHeight * CGFloat(lines.count) + padding * 2
        frame = CGRect(x: rect.minX, y: rect.minY, width: width, height: max(rect.height, textHeight))
    }
}
