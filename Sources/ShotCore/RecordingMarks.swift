import CoreGraphics
import Foundation

/// The border around an area while it records (spec › Recording border and clicks): a 2 pt ring hugging the area, then a
/// 4 pt glow outside it. Both sit outside the area, so neither covers what's recorded, and Shot leaves them out of the video.
public enum RecordingBorder {
    public static let lineWidth: CGFloat = 2
    public static let glowWidth: CGFloat = 4
    public static let glowOpacity: CGFloat = 0.22
    /// Increase Contrast's glow, which reads on busy content.
    public static let contrastGlowOpacity: CGFloat = 0.4
    /// The paused border's dash and gap, so paused differs from recording by more than its colour.
    public static let pausedDash: [CGFloat] = [10, 6]

    /// How far the border reaches outside the area.
    public static var outset: CGFloat { lineWidth + glowWidth }

    /// The ring's centre line and corner radius, in a panel whose bounds are `bounds`, `outset` larger than the area on
    /// each side. The ring's inner edge follows the area's square corners, and its outer corners round by its width.
    public static func ring(in bounds: CGRect) -> (rect: CGRect, radius: CGFloat) {
        let inset = glowWidth + lineWidth / 2
        return (bounds.insetBy(dx: inset, dy: inset), lineWidth / 2)
    }

    /// The glow's centre line and corner radius, in the same panel.
    public static func glow(in bounds: CGRect) -> (rect: CGRect, radius: CGFloat) {
        let inset = glowWidth / 2
        return (bounds.insetBy(dx: inset, dy: inset), lineWidth + glowWidth / 2)
    }
}

/// The ring Shot draws where you click while recording with Show clicks on: a 34 pt circle edged by a 3 pt accent ring and
/// a 6 pt halo outside that, centred on the pointer's tip.
public enum ClickRing {
    public static let diameter: CGFloat = 34
    public static let ringWidth: CGFloat = 3
    public static let haloWidth: CGFloat = 6
    public static let ringOpacity: CGFloat = 0.95
    public static let haloOpacity: CGFloat = 0.3
    /// Increase Contrast's halo, and the ink edge it adds inside the ring so it reads on white.
    public static let contrastHaloOpacity: CGFloat = 0.45
    public static let contrastEdgeWidth: CGFloat = 1
    /// How long a ring stays whole before `Moment.clickRing` fades it, long enough to see in a video played at speed.
    public static let hold: TimeInterval = 0.4

    /// The side of the square that holds the ring and its halo.
    public static var extent: CGFloat { diameter + 2 * (ringWidth + haloWidth) }

    /// The square that holds a ring for a click at `point`, in the same coordinates.
    public static func frame(at point: CGPoint) -> CGRect {
        CGRect(x: point.x - extent / 2, y: point.y - extent / 2, width: extent, height: extent)
    }

    /// The ring's and the halo's centre-line radii.
    public static var ringRadius: CGFloat { diameter / 2 + ringWidth / 2 }
    public static var haloRadius: CGFloat { diameter / 2 + ringWidth + haloWidth / 2 }

    /// Whether a click at `point` gets a ring: only inside the area being recorded.
    public static func shows(at point: CGPoint, in region: CGRect) -> Bool {
        region.contains(point)
    }

    /// Whether Shot draws the rings itself. A window recording captures only that window, so its rings would never reach
    /// the video; macOS draws its own there instead.
    public static func drawnByShot(recordsWindow: Bool) -> Bool {
        !recordsWindow
    }

    /// The opacity of a ring `elapsed` seconds after its click: whole for `hold`, then fading over the moment, or gone at
    /// once with Reduce Motion.
    public static func opacity(at elapsed: TimeInterval, reduceMotion: Bool) -> CGFloat {
        if elapsed < 0 {
            return 0
        }
        if elapsed < hold {
            return 1
        }
        let fade = Moment.clickRing.duration
        if reduceMotion || elapsed >= hold + fade {
            return 0
        }
        return CGFloat(1 - (elapsed - hold) / fade)
    }
}
