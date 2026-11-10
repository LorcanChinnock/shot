import CoreGraphics

/// The round crop badge on a placed image with a crop of its own, from Edit › Image editor · crop and combine. It shows
/// while the pointer is over the image or the image is selected, and clicking it adjusts that crop, as the Layers
/// panel's Crop badge does. It's drawn by the canvas only, so it never reaches a copy or a save.
public enum CanvasCropBadge {
    /// The badge's width and height, in view points.
    public static let diameter: CGFloat = 18
    /// How far the badge moves out along the corner's diagonal, on each axis, while the image's resize handles show, so
    /// the 8 pt corner handle and the badge are both clear to click.
    public static let handleClearance: CGFloat = 12
    /// How far past its edge a press still counts as on the badge, in view points.
    public static let hitSlop: CGFloat = 2

    /// Whether `annotation` shows the badge: a placed image with its own crop that's visible and unlocked, while it's
    /// `selected` or `hovered`.
    public static func shows(on annotation: Annotation, selected: Bool, hovered: Bool) -> Bool {
        annotation.imageFullRect != nil && annotation.imageCrop != nil && !annotation.isHidden && !annotation.isLocked
            && (selected || hovered)
    }

    /// The badge's centre for an image drawn at `imageRect` in a top-left-origin view: on its top-right corner, as on the
    /// board, or out past the corner's resize handle while `clearOfHandle`. It's kept wholly inside `view`, so an image
    /// against the canvas's edge still shows all of its badge.
    public static func center(of imageRect: CGRect, clearOfHandle: Bool, in view: CGRect = .infinite) -> CGPoint {
        let out = clearOfHandle ? handleClearance : 0
        var center = CGPoint(x: imageRect.maxX + out, y: imageRect.minY - out)
        let room = view.insetBy(dx: diameter / 2, dy: diameter / 2)
        if !view.isInfinite, !room.isNull {
            center.x = min(max(center.x, room.minX), room.maxX)
            center.y = min(max(center.y, room.minY), room.maxY)
        }
        return center
    }

    /// Whether `point` is on the badge centred at `center`.
    public static func contains(_ point: CGPoint, center: CGPoint) -> Bool {
        hypot(point.x - center.x, point.y - center.y) <= diameter / 2 + hitSlop
    }
}
