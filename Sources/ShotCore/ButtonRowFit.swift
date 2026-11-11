import CoreGraphics

/// The widths of a card's row of buttons, such as Cancel and Move to Trash, which a board draws side by side in fixed
/// proportions. When a translation leaves a name wider than its share, the buttons go one above another instead.
public enum ButtonRowFit {
    /// Each button's width when the row is `width` wide, split by `shares` (such as `[1, 1.3]`) after the gaps.
    public static func widths(width: CGFloat, gap: CGFloat, shares: [CGFloat]) -> [CGFloat] {
        let total = shares.reduce(0, +)
        guard total > 0 else {
            return shares.map { _ in 0 }
        }
        let room = max(0, width - gap * CGFloat(max(0, shares.count - 1)))
        return shares.map { (room * $0 / total).rounded(.down) }
    }

    /// True when every button's natural width fits its share, so the row stays side by side.
    public static func fits(natural: [CGFloat], widths: [CGFloat]) -> Bool {
        natural.count == widths.count && zip(natural, widths).allSatisfy { $0 <= $1 }
    }
}
