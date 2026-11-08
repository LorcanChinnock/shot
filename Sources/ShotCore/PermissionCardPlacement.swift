import CoreGraphics

/// Where the browser permission card sits on the selection overlay (Capture › Permission card…): next to the capture bar
/// whose Browser mode was picked, so it shows up where the person is looking.
public enum PermissionCardPlacement {
    /// The origin of a card of `size`, all in AppKit space. It is centred on `bar` and `gap` above it, or below it when
    /// there's no room above, as when the bar sits at the top of the screen. Without a bar, as after B once the bar has
    /// faded, it is centred on `screen`. It is kept `margin` inside `screen` either way.
    public static func origin(for size: CGSize, bar: CGRect?, screen: CGRect, gap: CGFloat = 16, margin: CGFloat = 8) -> CGPoint {
        let room = screen.insetBy(dx: margin, dy: margin)
        func clamp(_ origin: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max(origin.x, room.minX), room.maxX - size.width).rounded(),
                y: min(max(origin.y, room.minY), room.maxY - size.height).rounded()
            )
        }
        guard let bar else {
            return clamp(CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2))
        }
        let x = bar.midX - size.width / 2
        if bar.maxY + gap + size.height <= room.maxY {
            return clamp(CGPoint(x: x, y: bar.maxY + gap))
        }
        return clamp(CGPoint(x: x, y: bar.minY - gap - size.height))
    }
}
