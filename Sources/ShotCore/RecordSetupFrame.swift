import CoreGraphics
import Foundation

/// The frame drawn around the area before a recording starts (Record › Check before recording): the dim outside it, the
/// size and ratio chip, and the microphone's level bars in the setup bar. Rects are in AppKit space, with y going up.
public enum RecordSetupFrame {
    /// The four rects that dim `bounds` outside `hole`: below and above it across the whole width, then left and right of
    /// it. Empty ones are left out, so a hole that fills the screen dims nothing.
    public static func dimRects(around hole: CGRect, in bounds: CGRect) -> [CGRect] {
        let hole = hole.intersection(bounds)
        guard !hole.isNull, hole.width > 0, hole.height > 0 else {
            return [bounds]
        }
        let rects = [
            CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: hole.minY - bounds.minY),
            CGRect(x: bounds.minX, y: hole.maxY, width: bounds.width, height: bounds.maxY - hole.maxY),
            CGRect(x: bounds.minX, y: hole.minY, width: hole.minX - bounds.minX, height: hole.height),
            CGRect(x: hole.maxX, y: hole.minY, width: bounds.maxX - hole.maxX, height: hole.height),
        ]
        return rects.filter { $0.width > 0 && $0.height > 0 }
    }

    /// The chip's text: the size in pixels, then the ratio the handles keep when the area was picked with one, such as
    /// "1280 × 720 · 16:9". A ratio that isn't one of `AspectRatio`'s is left out rather than shown as a long fraction.
    public static func label(pixels: CGSize, ratio: CGFloat?) -> String {
        let size = "\(Int(pixels.width)) × \(Int(pixels.height))"
        guard let name = ratioName(ratio, portrait: pixels.height > pixels.width) else {
            return size
        }
        return "\(size) · \(name)"
    }

    /// `ratio` is width over height, as `RegionHandle.adjust` keeps it.
    static func ratioName(_ ratio: CGFloat?, portrait: Bool) -> String? {
        guard let ratio, ratio > 0 else {
            return nil
        }
        let long = max(ratio, 1 / ratio)
        let match = AspectRatio.allCases.first { candidate in
            guard let value = candidate.value else { return false }
            return abs(value - long) < 0.01
        }
        return match?.label(portrait: portrait)
    }
}

/// The microphone's level as a row of bars (Record › Check before recording).
public enum LevelBars {
    /// Bars in the row, as on the board.
    public static let count = 10
    /// Bars from this index up are lit in the warning colour, since the level is near clipping.
    public static let loudFrom = 8

    /// How many bars a `level` from 0 to 1 lights. Any sound at all lights the first bar.
    public static func lit(_ level: Double, of count: Int = count) -> Int {
        guard level > 0 else {
            return 0
        }
        return min(max(Int((level * Double(count)).rounded(.up)), 1), count)
    }
}
