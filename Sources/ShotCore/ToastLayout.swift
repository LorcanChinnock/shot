import CoreGraphics

/// Where a toast sits: in the Quick Access corner, its outer edge in line with the cards', so the confirmation shows
/// where the eye already is. With cards showing it rests `gap` above them, as on the board; otherwise it takes the
/// place a card would. Frames are in AppKit's bottom-left-origin screen coordinates.
public enum ToastLayout {
    /// The space between the top of the Quick Access cards and the toast.
    public static let gap: CGFloat = 22

    /// The toast's frame for a pill `size` big on a screen whose visible frame is `visible`.
    /// - Parameters:
    ///   - side: the Quick Access corner.
    ///   - edgeInset: how far a Quick Access card sits in from the screen's side and bottom.
    ///   - cardsTop: the top of the Quick Access cards, or nil when none are showing.
    public static func frame(size: CGSize, in visible: CGRect, side: QuickAccessPosition, edgeInset: CGFloat, cardsTop: CGFloat?) -> CGRect {
        let left = side == .left ? visible.minX + edgeInset : visible.maxX - edgeInset - size.width
        let x = max(visible.minX, min(left, visible.maxX - size.width))
        let resting = cardsTop.map { $0 + gap } ?? visible.minY + edgeInset
        let y = max(visible.minY, min(resting, visible.maxY - size.height))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// `frame` changed to `size`, keeping its outer edge on `side` and its bottom where they were, so a toast whose text
    /// or progress changes grows away from the screen's side.
    public static func resized(_ frame: CGRect, to size: CGSize, side: QuickAccessPosition) -> CGRect {
        let x = side == .left ? frame.minX : frame.maxX - size.width
        return CGRect(x: x, y: frame.minY, width: size.width, height: size.height)
    }
}
