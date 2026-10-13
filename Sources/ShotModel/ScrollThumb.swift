import Foundation

/// The thumb of a scroll bar, and the offsets a drag or a click on its track maps to. All lengths are in points along the
/// scroll axis, with offset 0 at the start of the content.
public struct ScrollThumb: Equatable, Sendable {
    public var length: CGFloat
    public var offset: CGFloat

    /// The thumb for `viewport` of `content` scrolled to `offset`, in a track `track` long; nil when the content fits, so
    /// there's no bar. The thumb is never shorter than `minLength`, so it stays easy to grab in a long page.
    public static func layout(content: CGFloat, viewport: CGFloat, offset: CGFloat, track: CGFloat, minLength: CGFloat) -> ScrollThumb? {
        guard viewport > 0, track > 0, content > viewport + 0.5 else {
            return nil
        }
        let length = min(track, max(minLength, track * viewport / content))
        let range = content - viewport
        let fraction = min(max(offset / range, 0), 1)
        return ScrollThumb(length: length, offset: (track - length) * fraction)
    }

    /// The content offset for a thumb dragged to `thumbOffset`, clamped to the ends.
    public func contentOffset(forThumbOffset thumbOffset: CGFloat, content: CGFloat, viewport: CGFloat, track: CGFloat) -> CGFloat {
        let travel = track - length
        guard travel > 0, content > viewport else {
            return 0
        }
        let fraction = min(max(thumbOffset / travel, 0), 1)
        return fraction * (content - viewport)
    }

    /// The offset one page on from `offset`, keeping a little of the old page in view, clamped to the content.
    public static func pagedOffset(content: CGFloat, viewport: CGFloat, offset: CGFloat, forward: Bool) -> CGFloat {
        let page = max(viewport * 0.9, 1)
        return min(max(offset + (forward ? page : -page), 0), max(content - viewport, 0))
    }
}
