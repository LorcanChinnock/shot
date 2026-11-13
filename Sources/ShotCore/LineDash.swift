import CoreGraphics
import Foundation

/// How an arrow's or line's stroke is drawn. An arrow's head stays solid whichever it is.
public enum LineDash: String, Codable, CaseIterable, Sendable {
    case solid, dashed, dotted

    /// The dash lengths to stroke a path `length` long and `width` wide with, with round caps from the start of the path;
    /// `nil` for solid. They scale with the width and stretch a little so the path starts and ends on a dash or dot.
    ///
    /// Round caps add half the width to each end of a dash, so a dash shows `3 × width` long with gaps of `2 × width`.
    /// A dot is a dash of no length, which its caps draw as a round dot `width` across, `2 × width` from the next.
    public func pattern(width: CGFloat, length: CGFloat) -> [CGFloat]? {
        guard width > 0, length > 0, length.isFinite else {
            return nil
        }
        switch self {
        case .solid:
            return nil
        case .dashed:
            let dash = width * 2, gap = width * 3
            let count = max(1, ((length + gap) / (dash + gap)).rounded())
            let stretch = length / (count * dash + (count - 1) * gap)
            return [dash * stretch, gap * stretch]
        case .dotted:
            let spaces = max(1, (length / (width * 2)).rounded())
            // A hair short, so the last dot lands inside the path rather than just past its end.
            return [0, length / spaces * 0.9999]
        }
    }

    /// The length of `path`, with each curve measured along 16 straight steps.
    public static func length(of path: CGPath) -> CGFloat {
        var total: CGFloat = 0
        var current = CGPoint.zero
        var start = CGPoint.zero
        func walk(_ point: (CGFloat) -> CGPoint) {
            var last = current
            for step in 1...16 {
                let next = point(CGFloat(step) / 16)
                total += hypot(next.x - last.x, next.y - last.y)
                last = next
            }
        }
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                current = points[0]
                start = current
            case .addLineToPoint:
                total += hypot(points[0].x - current.x, points[0].y - current.y)
                current = points[0]
            case .addQuadCurveToPoint:
                let (from, control, to) = (current, points[0], points[1])
                walk { t in
                    let u = 1 - t
                    return CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x, y: u * u * from.y + 2 * u * t * control.y + t * t * to.y)
                }
                current = to
            case .addCurveToPoint:
                let (from, c1, c2, to) = (current, points[0], points[1], points[2])
                walk { t in
                    let u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    return CGPoint(x: a * from.x + b * c1.x + c * c2.x + d * to.x, y: a * from.y + b * c1.y + c * c2.y + d * to.y)
                }
                current = to
            case .closeSubpath:
                total += hypot(start.x - current.x, start.y - current.y)
                current = start
            @unknown default:
                break
            }
        }
        return total
    }
}
