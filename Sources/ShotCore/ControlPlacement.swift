import CoreGraphics

public enum ControlPlacement {
    /// Below the region if there is room, else above it, else inside its bottom edge; all in AppKit space.
    public static func origin(for size: CGSize, region: CGRect, visible: CGRect, gap: CGFloat = 14, margin: CGFloat = 8) -> CGPoint {
        var origin = CGPoint(x: region.midX - size.width / 2, y: region.minY - gap - size.height)
        if origin.y < visible.minY + margin {
            let above = region.maxY + gap
            if above + size.height <= visible.maxY - margin {
                origin.y = above
            } else {
                origin.y = max(region.minY, visible.minY) + 20
            }
        }
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
        return origin
    }
}
