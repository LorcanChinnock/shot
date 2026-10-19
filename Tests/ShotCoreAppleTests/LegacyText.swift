import CoreGraphics
import CoreText
import Foundation
@testable import ShotCore
import ShotCoreApple

// The text path from before #650, Core Text called straight from the layouts and the renderer, kept so `TextGoldenTests`
// can check `CoreTextShaper` lays out and draws the same. Both go in #650's PR 2.

struct LegacyTextLayout {
    let lines: [CTLine]
    let lineHeight: CGFloat
    let ascent: CGFloat
    let size: CGSize

    init(string: String, fontSize: CGFloat, color: RGBA) {
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

struct LegacyNoteLayout {
    let padding: CGFloat
    let cornerRadius: CGFloat
    let shadowOffset: CGFloat
    let shadowBlur: CGFloat
    let fill: RGBA
    let ink: RGBA
    let lines: [CTLine]
    let lineHeight: CGFloat
    let ascent: CGFloat
    let frame: CGRect

    var textRect: CGRect { frame.insetBy(dx: padding, dy: padding) }

    init(string: String, rect: CGRect, fontSize: CGFloat, color: RGBA) {
        padding = NoteLayout.padding(fontSize: fontSize)
        cornerRadius = fontSize * 0.35
        shadowOffset = fontSize * 0.15
        shadowBlur = fontSize * 0.5
        fill = color.noteFill
        ink = fill.contrastingInk

        let width = max(rect.width, NoteLayout.minWidth(fontSize: fontSize))
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

enum LegacyText {
    static func offset(of line: CTLine, in width: CGFloat, alignment: TextAlign) -> CGFloat {
        let visible = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))
        return (width - visible) * alignment.fraction
    }

    /// `CGCanvas.draw(_:at:outlined:)` as it was.
    static func draw(_ line: CTLine, at position: CGPoint, outlined: Bool, in context: CGContext) {
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = position
        if outlined {
            context.setTextDrawingMode(.stroke)
        }
        CTLineDraw(line, context)
        if outlined {
            context.setTextDrawingMode(.fill)
        }
    }

    /// A text annotation, counter or note without a shadow, drawn in a top-left-origin context as the renderer drew it.
    static func draw(_ annotation: Annotation, in canvas: CGCanvas) {
        let context = canvas.context
        canvas.saveState()
        defer { canvas.restoreState() }
        canvas.setStrokeColor(annotation.color)
        canvas.setFillColor(annotation.color)
        canvas.setLineWidth(annotation.lineWidth)
        canvas.setLineCap(.round)
        canvas.setLineJoin(.round)

        switch annotation.kind {
        case let .text(string, origin, fontSize):
            let layout = LegacyTextLayout(string: string, fontSize: fontSize, color: annotation.color)
            func drawLines(_ lines: [CTLine], outlined: Bool = false) {
                for (index, line) in lines.enumerated() {
                    let x = origin.x + offset(of: line, in: layout.size.width, alignment: annotation.alignment)
                    draw(line, at: CGPoint(x: x, y: origin.y + layout.ascent + CGFloat(index) * layout.lineHeight), outlined: outlined, in: context)
                }
            }
            if let outline = annotation.style.border, outline.kind == .outline {
                canvas.saveState()
                canvas.setLineWidth(outline.width * 2)
                canvas.setStrokeColor(outline.paint)
                drawLines(LegacyTextLayout(string: string, fontSize: fontSize, color: outline.paint).lines, outlined: true)
                canvas.restoreState()
            }
            drawLines(layout.lines)
        case let .counter(number, center):
            let radius = annotation.counterRadius
            canvas.fill(CanvasPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)))
            let layout = LegacyTextLayout(string: "\(number)", fontSize: radius * 1.1, color: RGBA(1, 1, 1))
            guard let line = layout.lines.first else {
                return
            }
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            draw(line, at: CGPoint(x: center.x - lineWidth / 2, y: center.y + (ascent - descent) / 2), outlined: false, in: context)
        case let .note(string, rect):
            let layout = LegacyNoteLayout(string: string, rect: rect, fontSize: annotation.noteFontSize, color: annotation.color)
            canvas.saveState()
            canvas.setShadow(offset: CGSize(width: 0, height: layout.shadowOffset), blur: layout.shadowBlur, color: RGBA(0, 0, 0, 0.3))
            canvas.setFillColor(layout.fill)
            canvas.fill(CanvasPath(roundedRect: layout.frame, cornerRadius: layout.cornerRadius))
            canvas.restoreState()
            let text = layout.textRect
            for (index, line) in layout.lines.enumerated() {
                let x = text.minX + offset(of: line, in: text.width, alignment: annotation.alignment)
                draw(line, at: CGPoint(x: x, y: text.minY + layout.ascent + CGFloat(index) * layout.lineHeight), outlined: false, in: context)
            }
        default:
            preconditionFailure("LegacyText draws only text, counters and notes")
        }
    }
}
