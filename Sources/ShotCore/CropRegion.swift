import Foundation

/// A part of an image in its pixels from the top left, as `shot crop` and the MCP `zoom` tool take it. The maths is here,
/// apart from the pixels, so it's tested on its own.
public enum CropRegion {
    /// `[x, y, width, height]` from a tool's `rect`: four finite numbers, with a width and height above 0.
    public static func rect(_ value: JSONValue?) -> [Double]? {
        guard case let .array(items)? = value else {
            return nil
        }
        let rect = items.compactMap { $0.number.flatMap { $0.isFinite ? $0 : nil } }
        return rect.count == 4 && items.count == 4 && rect[2] > 0 && rect[3] > 0 ? rect : nil
    }

    /// `rect` on whole pixels, grown out to every pixel it touches and kept within a `width` by `height` image, as
    /// `[x, y, width, height]`; `nil` when none of it lies on the image or it isn't a rectangle.
    public static func clamped(_ rect: [Double], width: Int, height: Int) -> [Int]? {
        guard rect.count == 4, rect.allSatisfy(\.isFinite), rect[2] > 0, rect[3] > 0, width > 0, height > 0 else {
            return nil
        }
        // Clamped as doubles first, so a huge value can't trap converting to Int.
        func span(_ start: Double, _ length: Double, within limit: Int) -> (Int, Int) {
            let low = min(max(start, 0), Double(limit)), high = min(max(start + length, 0), Double(limit))
            return (Int(low.rounded(.down)), Int(high.rounded(.up)))
        }
        let (left, right) = span(rect[0], rect[2], within: width)
        let (top, bottom) = span(rect[1], rect[3], within: height)
        guard right > left, bottom > top else {
            return nil
        }
        return [left, top, right - left, bottom - top]
    }

    /// `rect` as `x,y,width,height` with up to two decimals, for messages.
    public static func text(_ rect: [Double]) -> String {
        rect.map { String(format: "%g", ($0 * 100).rounded() / 100) }.joined(separator: ",")
    }
}
