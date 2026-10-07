import CoreGraphics

/// Keyboard and placement rules for a dropdown menu. Items that can't be picked (dividers, headers, disabled items) are
/// skipped.
public enum Dropdown {
    /// The next pickable item `step` away from `current`, wrapping round the ends; from nothing, Down starts at the top and
    /// Up at the bottom.
    public static func step(from current: Int?, by step: Int, pickable: [Bool]) -> Int? {
        let count = pickable.count
        guard count > 0, pickable.contains(true) else {
            return nil
        }
        var index = current ?? (step > 0 ? -1 : count)
        repeat {
            index = ((index + step) % count + count) % count
        } while !pickable[index]
        return index
    }

    /// The first pickable item from `current` on, wrapping, whose title starts with `typed`, ignoring case.
    public static func match(_ typed: String, titles: [String?], from current: Int?) -> Int? {
        guard !typed.isEmpty, !titles.isEmpty else {
            return nil
        }
        let start = current ?? 0
        let prefix = typed.lowercased()
        return (0..<titles.count).lazy
            .map { (start + $0) % titles.count }
            .first { titles[$0]?.lowercased().hasPrefix(prefix) == true }
    }

    /// The menu's origin in AppKit space: under `anchor`, or above it when there's no room below, kept inside `visible`.
    public static func origin(size: CGSize, anchor: CGRect, visible: CGRect, gap: CGFloat) -> CGPoint {
        var y = anchor.minY - gap - size.height
        if y < visible.minY {
            y = min(anchor.maxY + gap, visible.maxY - size.height)
        }
        let x = max(min(anchor.minX, visible.maxX - size.width), visible.minX)
        return CGPoint(x: x, y: y)
    }
}
