import CoreGraphics
import Foundation

/// Where the video editor's clip handles go: the rotate handle sits on a stem above the clip's outline, and steps inside
/// it when above would put it outside the well, where it would be clipped and out of reach, such as on a clip that fills
/// the frame.
public enum TransformHandles {
    /// How far the rotate handle sits from the outline's top edge, above it or, when flipped, below it.
    public static let knobDistance: CGFloat = 22

    /// Where the rotate handle goes, in the video's view points, and whether it's flipped inside the outline.
    /// - Parameters:
    ///   - center: the point the outline turns about.
    ///   - topMiddle: the middle of the outline's top edge from `center`, before the turn.
    ///   - rotation: the clip's turn, in radians.
    ///   - video: the video's size; the well reaches `inset` beyond it on every side.
    ///   - margin: how far inside the well the handle's centre has to be to stay grabbable.
    public static func rotateHandle(center: CGPoint, topMiddle: CGVector, rotation: CGFloat, video: CGSize, inset: CGSize, margin: CGFloat = 10) -> (point: CGPoint, flipped: Bool) {
        let outside = point(center: center, offset: CGVector(dx: topMiddle.dx, dy: topMiddle.dy - knobDistance), rotation: rotation)
        let well = CGRect(x: -inset.width, y: -inset.height, width: video.width + inset.width * 2, height: video.height + inset.height * 2)
        if well.insetBy(dx: margin, dy: margin).contains(outside) {
            return (outside, false)
        }
        return (point(center: center, offset: CGVector(dx: topMiddle.dx, dy: topMiddle.dy + knobDistance), rotation: rotation), true)
    }

    private static func point(center: CGPoint, offset: CGVector, rotation: CGFloat) -> CGPoint {
        CGPoint(x: center.x + offset.dx * cos(rotation) - offset.dy * sin(rotation), y: center.y + offset.dx * sin(rotation) + offset.dy * cos(rotation))
    }
}
