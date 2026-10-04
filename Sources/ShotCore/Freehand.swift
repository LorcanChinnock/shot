import CoreGraphics

/// A freehand pen stroke's geometry. Image pixels, top-left origin.
public enum Freehand {
    /// `points` with `point` added, unless it's within `minDistance` of the last one,
    /// so a slow drag doesn't pile up points the curve can't use.
    public static func adding(_ point: CGPoint, to points: [CGPoint], minDistance: CGFloat) -> [CGPoint] {
        if let last = points.last, hypot(point.x - last.x, point.y - last.y) < minDistance {
            return points
        }
        return points + [point]
    }

    /// A smooth curve through every point: a Catmull-Rom spline drawn as cubic Béziers.
    /// One point is a zero-length line, which a round cap draws as a dot.
    public static func path(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else {
            return path
        }
        path.move(to: first)
        guard points.count > 1 else {
            path.addLine(to: first)
            return path
        }
        for i in 0..<points.count - 1 {
            // The ends repeat themselves, so the curve starts and finishes heading at its neighbour.
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        return path
    }

    /// The smallest rect holding every point.
    static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else {
            return .null
        }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Maps each point from where it sits in `rect` to the same place in the box from `min` to `max`.
    /// The box may be flipped (`max` less than `min`), which mirrors the stroke. A flat side of `rect`
    /// has nothing to scale, so its points keep that coordinate.
    static func scaled(_ points: [CGPoint], from rect: CGRect, min: CGPoint, max: CGPoint) -> [CGPoint] {
        points.map { p in
            CGPoint(
                x: rect.width > 0 ? min.x + (p.x - rect.minX) * (max.x - min.x) / rect.width : p.x,
                y: rect.height > 0 ? min.y + (p.y - rect.minY) * (max.y - min.y) / rect.height : p.y
            )
        }
    }
}
