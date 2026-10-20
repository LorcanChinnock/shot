import CPango
import Foundation

/// Linux's `TextShaper`: Pango, with fontconfig choosing the fonts. The Mac's system font is San Francisco, which Linux
/// doesn't have, so Shot asks fontconfig for `system-ui` and then `sans-serif`, which on most desktops is the interface
/// font, and DejaVu Sans where that's all there is. A character the font lacks, such as an emoji, comes from whichever
/// installed font has it, in colour when that font is a colour one.
///
/// Text is measured unhinted and at fractional positions, as Core Text measures it, so a line is as wide however the
/// canvas it's drawn on is scaled. Each thread shapes with its own Pango font map, since one isn't safe to share.
public struct PangoShaper: TextShaper {
    public init() {}

    /// The families asked for, first to last.
    static let families = "system-ui,sans-serif"

    public func metrics(of font: TextFont) -> TextMetrics {
        let context = Self.context()
        defer { g_object_unref(UnsafeMutableRawPointer(context)) }
        let description = Self.description(font)
        defer { pango_font_description_free(description) }
        let metrics = pango_context_get_metrics(context, description, nil)!
        defer { pango_font_metrics_unref(metrics) }
        let ascent = points(pango_font_metrics_get_ascent(metrics)), descent = points(pango_font_metrics_get_descent(metrics))
        let height = points(pango_font_metrics_get_height(metrics))
        return TextMetrics(ascent: ascent, descent: descent, leading: max(0, height - ascent - descent))
    }

    public func line(_ string: String, font: TextFont, color: RGBA) -> any ShapedLine {
        PangoLine(Layout(string, font: font), color: color)
    }

    public func paragraph(_ string: String, font: TextFont, color: RGBA) -> any ShapedParagraph {
        PangoParagraph(string, font: font, color: color)
    }

    /// A context on this thread's font map, measuring as `PangoShaper` measures.
    static func context() -> OpaquePointer {
        let context = pango_font_map_create_context(pango_cairo_font_map_get_default())!
        let options = cairo_font_options_create()!
        defer { cairo_font_options_destroy(options) }
        cairo_font_options_set_hint_metrics(options, CAIRO_HINT_METRICS_OFF)
        cairo_font_options_set_hint_style(options, CAIRO_HINT_STYLE_NONE)
        cairo_font_options_set_antialias(options, CAIRO_ANTIALIAS_GRAY)
        pango_cairo_context_set_font_options(context, options)
        pango_context_set_round_glyph_positions(context, 0)
        return context
    }

    /// `font` in the families asked for, its size in the canvas's units rather than in points of some resolution.
    static func description(_ font: TextFont) -> OpaquePointer {
        let description = pango_font_description_new()!
        pango_font_description_set_family(description, families)
        pango_font_description_set_weight(description, font.bold ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL)
        pango_font_description_set_absolute_size(description, Double(font.size) * Double(PANGO_SCALE))
        return description
    }

    /// Whether some installed font draws emoji in colour.
    public static var hasColorEmoji: Bool {
        guard let config = FcInitLoadConfigAndFonts() else {
            return false
        }
        defer { FcConfigDestroy(config) }
        let pattern = FcPatternCreate()!
        defer { FcPatternDestroy(pattern) }
        let charset = FcCharSetCreate()!
        defer { FcCharSetDestroy(charset) }
        // 😀, which every colour emoji font has.
        FcCharSetAddChar(charset, 0x1F600)
        FcPatternAddCharSet(pattern, FC_CHARSET, charset)
        FcPatternAddBool(pattern, FC_COLOR, 1)
        let objects = FcObjectSetCreate()!
        defer { FcObjectSetDestroy(objects) }
        FcObjectSetAdd(objects, FC_FAMILY)
        guard let fonts = FcFontList(config, pattern, objects) else {
            return false
        }
        defer { FcFontSetDestroy(fonts) }
        return fonts.pointee.nfont > 0
    }
}

/// Pango units as points.
private func points(_ units: Int32) -> CGFloat { CGFloat(units) / CGFloat(PANGO_SCALE) }

/// A `PangoLayout` of one line, unreferenced with the last reference to it.
final class Layout {
    let pointer: OpaquePointer

    init(_ string: String, font: TextFont) {
        let context = PangoShaper.context()
        pointer = pango_layout_new(context)
        g_object_unref(UnsafeMutableRawPointer(context))
        let description = PangoShaper.description(font)
        pango_layout_set_font_description(pointer, description)
        pango_font_description_free(description)
        pango_layout_set_single_paragraph_mode(pointer, 1)
        pango_layout_set_text(pointer, string, -1)
    }

    deinit {
        g_object_unref(UnsafeMutableRawPointer(pointer))
    }

    var line: UnsafeMutablePointer<PangoLayoutLine> { pango_layout_get_line_readonly(pointer, 0) }
}

/// A line of a `PangoLayout`, which `CairoCanvas` draws in `color`.
public struct PangoLine: ShapedLine {
    let layout: Layout
    let color: RGBA
    public let width: CGFloat
    public let trailingWhitespaceWidth: CGFloat
    public let ascent: CGFloat
    public let descent: CGFloat

    var text: String { String(cString: pango_layout_get_text(layout.pointer)) }

    init(_ layout: Layout, color: RGBA) {
        self.layout = layout
        self.color = color
        let line = layout.line
        var logical = PangoRectangle()
        pango_layout_line_get_extents(line, nil, &logical)
        width = points(logical.width)
        ascent = points(-logical.y)
        descent = points(logical.height + logical.y)
        // The whitespace the line ends with, measured from where it starts.
        let text = pango_layout_get_text(layout.pointer)!
        var end = Int(line.pointee.start_index + line.pointee.length)
        while end > Int(line.pointee.start_index), [9, 32].contains(text[end - 1]) {
            end -= 1
        }
        if end == Int(line.pointee.start_index + line.pointee.length) {
            trailingWhitespaceWidth = 0
        } else {
            var x: Int32 = 0
            pango_layout_line_index_to_x(line, Int32(end), 0, &x)
            trailingWhitespaceWidth = max(0, width - points(x))
        }
    }
}

/// A paragraph Pango shapes as one line, broken where its log attributes allow. Positions are UTF-16 code units, as
/// `ShapedParagraph` counts them; Pango counts characters and bytes.
final class PangoParagraph: ShapedParagraph {
    private let string: String
    private let font: TextFont
    private let color: RGBA
    /// For each character and the end: where it starts in UTF-16 code units, and where in the paragraph's line it starts,
    /// measured as the sum of the characters' advances before it.
    private let units: [Int]
    private let offsets: [CGFloat]
    /// Each character's and the end's log attributes: whether a line or cluster may end before it, and whether it's space.
    private let attributes: [PangoLogAttr]

    init(_ string: String, font: TextFont, color: RGBA) {
        self.string = string
        self.font = font
        self.color = color
        let layout = Layout(string, font: font)
        let line = layout.line
        var units = [0], bytes = [0]
        for scalar in string.unicodeScalars {
            units.append(units[units.count - 1] + scalar.utf16.count)
            bytes.append(bytes[bytes.count - 1] + scalar.utf8.count)
        }
        // A character's advance is the width of the ranges it covers, which holds for text in either direction.
        var offsets: [CGFloat] = [0]
        for index in 0..<(bytes.count - 1) {
            var ranges: UnsafeMutablePointer<Int32>?
            var count: Int32 = 0
            pango_layout_line_get_x_ranges(line, Int32(bytes[index]), Int32(bytes[index + 1]), &ranges, &count)
            var advance: CGFloat = 0
            for range in 0..<Int(count) {
                advance += points(ranges![range * 2 + 1] - ranges![range * 2])
            }
            g_free(ranges)
            offsets.append(offsets[offsets.count - 1] + advance)
        }
        var count: Int32 = 0
        let attributes = pango_layout_get_log_attrs_readonly(layout.pointer, &count)!
        self.units = units
        self.offsets = offsets
        self.attributes = Array(UnsafeBufferPointer(start: attributes, count: Int(count)))
    }

    var length: Int { units[units.count - 1] }

    /// The character starting at or before `unit`.
    private func character(at unit: Int) -> Int {
        var low = 0, high = units.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if units[middle] <= unit {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    private var characters: Int { units.count - 1 }

    /// A hair over `width`, so a line that fits exactly but for rounding still fits.
    private func fits(_ start: Int, _ end: Int, in width: CGFloat) -> Bool {
        offsets[end] - offsets[start] <= width + 0.001
    }

    func lineBreak(from start: Int, width: CGFloat) -> Int {
        let first = character(at: start)
        guard first < characters else {
            return 0
        }
        var best: Int?
        var lastInk = first
        for end in (first + 1)...characters {
            if attributes[end - 1].is_white == 0 {
                lastInk = end
            }
            guard end == characters || attributes[end].is_line_break != 0 else {
                continue
            }
            // Whitespace at the end of a line may hang past its width. A word wider than the line overflows it.
            guard fits(first, lastInk, in: width) else {
                return units[best ?? end] - start
            }
            best = end
            if end < characters, attributes[end].is_mandatory_break != 0 {
                break
            }
        }
        return units[best ?? characters] - start
    }

    func clusterBreak(from start: Int, width: CGFloat) -> Int {
        let first = character(at: start)
        guard first < characters else {
            return 0
        }
        var best: Int?
        for end in (first + 1)...characters where attributes[end].is_cursor_position != 0 {
            // At least one cluster, so a break never splits one.
            guard fits(first, end, in: width) else {
                return units[best ?? end] - start
            }
            best = end
        }
        return units[best ?? characters] - start
    }

    func line(from start: Int, count: Int) -> any ShapedLine {
        let utf16 = Array(string.utf16)
        let text = String(decoding: utf16[min(start, utf16.count)..<min(start + count, utf16.count)], as: UTF16.self)
        return PangoLine(Layout(text, font: font), color: color)
    }
}
