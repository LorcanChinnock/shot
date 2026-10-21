import Foundation

public enum Snapping {
    /// How close, in points, a time has to be to a snap point to jump to it.
    public static let reach: CGFloat = 8

    /// The nearest of `points` within `threshold` of `time`; nil when none is.
    public static func snap(_ time: Double, to points: [Double], within threshold: Double) -> Double? {
        points.filter { abs($0 - time) <= threshold }.min { abs($0 - time) < abs($1 - time) }
    }
}

/// How far the lanes are zoomed in: 1 fits the whole project in the window.
public enum TimelineZoom {
    public static let range: ClosedRange<Double> = 1...64
    static let step = 1.5

    public static func zoomed(_ zoom: Double, bySteps steps: Int) -> Double {
        min(max(zoom * pow(step, Double(steps)), range.lowerBound), range.upperBound)
    }

    /// The zoom that keeps `time` under the same x after the change: the scroll offset to use, in points.
    public static func offset(keeping time: Double, atViewX viewX: CGFloat, duration: Double, zoom: Double, viewWidth: CGFloat) -> CGFloat {
        guard duration > 0 else {
            return 0
        }
        let contentWidth = viewWidth * CGFloat(zoom)
        let offset = contentWidth * CGFloat(time / duration) - viewX
        return min(max(offset, 0), max(0, contentWidth - viewWidth))
    }
}

public enum TimelineRuler {
    private static let intervals: [Double] = [0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600]

    /// The smallest round number of seconds between labels that keeps them `minSpacing` points apart.
    public static func interval(pointsPerSecond: CGFloat, minSpacing: CGFloat = 64) -> Double {
        guard pointsPerSecond > 0 else {
            return intervals.last!
        }
        return intervals.first { Double(pointsPerSecond) * $0 >= Double(minSpacing) } ?? intervals.last!
    }

    /// Labelled times from 0 up to `duration`.
    public static func ticks(duration: Double, interval: Double) -> [Double] {
        guard duration > 0, interval > 0 else {
            return []
        }
        return (0...Int((duration / interval).rounded(.down))).map { Double($0) * interval }
    }

    /// `1:05`, or `0:01.5` when the labels are closer than a second.
    public static func label(_ seconds: Double, interval: Double) -> String {
        let hundredths = Int((seconds * 100).rounded())
        let whole = hundredths / 100
        let base = "\(whole / 60):" + String(format: "%02d", whole % 60)
        return interval < 1 ? base + String(format: ".%d", hundredths % 100 / 10) : base
    }
}
