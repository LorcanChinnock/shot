import Foundation

/// How a drag held near either end of a scroll view scrolls it. Positions and lengths are in points along the scroll axis,
/// with 0 at the start of the viewport.
public enum EdgeScroll {
    /// The share of full speed to scroll at with the pointer at `position` in a viewport `length` long: negative towards
    /// the start, positive towards the end, and 0 away from both. It grows from 0 at `zone` inside an edge to 1 at the edge
    /// and past it.
    public static func speed(at position: CGFloat, length: CGFloat, zone: CGFloat) -> CGFloat {
        guard length > 0, zone > 0 else {
            return 0
        }
        let zone = min(zone, length / 2)
        if position < zone {
            return -min((zone - position) / zone, 1)
        }
        if position > length - zone {
            return min((position - (length - zone)) / zone, 1)
        }
        return 0
    }

    /// The content offset `step` points on from `offset`, clamped to the content.
    public static func offset(_ offset: CGFloat, by step: CGFloat, content: CGFloat, viewport: CGFloat) -> CGFloat {
        min(max(offset + step, 0), max(content - viewport, 0))
    }
}
